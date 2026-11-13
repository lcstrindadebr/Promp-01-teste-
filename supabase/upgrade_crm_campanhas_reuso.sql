begin;
create table public.crm_campanhas_reuso (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 origem uuid not null, nome text not null, convenio text not null, created_at timestamptz not null default now(),
 resposta jsonb not null, pedido jsonb not null
);
alter table public.crm_campanhas_reuso enable row level security;
revoke all on public.crm_campanhas_reuso from public,anon,authenticated;
grant select on public.crm_campanhas_reuso to authenticated;
create policy reuso_leitura on public.crm_campanhas_reuso for select to authenticated using (user_id=(select auth.uid()));
create index crm_campanhas_reuso_origem on public.crm_campanhas_reuso(user_id,origem,created_at desc);

create function apoiarcred_private.crm_base_reuso(p_uid uuid,p_origem uuid,p_convenio text)
returns table(cpf text,nome text,telefone text,margem text,saque text)
language sql stable set search_path='' as $$
 with base as (
  select distinct on (j.cpf) j.cpf,j.nome,j.telefone from public.consulta_jobs j
  join public.consulta_lotes l on l.id=j.lote_id and l.user_id=p_uid and l.tipo='campanha'
  where j.user_id=p_uid and j.lote_id=p_origem and j.status not in ('aguardando','processando')
  order by j.cpf,j.created_at desc,j.id desc
 ), estados as (
  select b.cpf,b.nome,b.telefone,m.tipo,
   case when h.pendente then 'pendente' when h.consultado then 'consultado'
    when m.tipo='margem' and c.resumo_consultas ? ('margem_importada_'||p_convenio) then 'importado'
    when m.tipo='saque' and c.resumo_consultas->('amigoz_saque_'||p_convenio)->>'origem'='importacao' then 'importado'
    when h.falha then 'falha' else 'faltante' end situacao
  from base b cross join (values ('margem'),('saque')) m(tipo)
  left join public.crm_cadastros c on c.user_id=p_uid and c.cpf=b.cpf
  left join lateral (
   select bool_or(j.status in ('aguardando','processando')) pendente,
    bool_or(j.resultado->m.tipo->>'status'='respondido') consultado,
    bool_or(j.status in ('erro','revisao')) falha
   from public.amigoz_jobs j
   where j.user_id=p_uid and j.cpf=b.cpf and j.convenio=p_convenio and j.modo in (m.tipo,'ambos')
    and (m.tipo='saque' or j.numero_matricula is null)
  ) h on true
 )
 select cpf,nome,telefone,max(situacao) filter(where tipo='margem'),max(situacao) filter(where tipo='saque')
 from estados group by cpf,nome,telefone;
$$;
revoke all on function apoiarcred_private.crm_base_reuso(uuid,uuid,text) from public,anon,authenticated;

create function public.crm_prever_reuso(p_origem uuid,p_convenio text,p_apos text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); saida jsonb;
begin
 if uid is null then raise insufficient_privilege;end if;
 perform public.authorize_amigoz(uid,false);
 if not exists(select 1 from public.consulta_lotes where id=p_origem and user_id=uid and tipo='campanha') then raise insufficient_privilege;end if;
 if not exists(select 1 from public.crm_catalogo_importacao where codigo=p_convenio and servicos && array['amigoz_saque','amigoz_margem']) then
  raise exception 'Escolha um convênio Amigoz válido.';
 end if;
 with base as materialized (select * from apoiarcred_private.crm_base_reuso(uid,p_origem,p_convenio)),
 pagina as (select cpf,nome,margem,saque from base where cpf>coalesce(p_apos,'') order by cpf limit 51)
 select jsonb_build_object('total',(select count(*) from base),
  'ambos_sugeridos',(select count(*) from base where margem in ('faltante','falha') and saque in ('faltante','falha')),
  'margem',(select jsonb_object_agg(margem,n) from (select margem,count(*) n from base group by margem) t),
  'saque',(select jsonb_object_agg(saque,n) from (select saque,count(*) n from base group by saque) t),
  'linhas',coalesce((select jsonb_agg(to_jsonb(p) order by p.cpf) from (select * from pagina limit 50) p),'[]'),
  'proxima',case when (select count(*) from pagina)>50 then (select cpf from pagina order by cpf offset 49 limit 1) end)
 into saida;
 if jsonb_array_length(saida->'linhas')<50 then saida:=saida-'proxima';end if;
 return saida;
end $$;

create function public.crm_confirmar_reuso(p_id uuid,p_origem uuid,p_convenio text,p_nome text,p_modalidades text[],p_incluir jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); uf_alvo text; servicos text[]; pedido jsonb;
 anterior public.crm_campanhas_reuso; escolhido record; modo text; leads integer:=0; consultas integer:=0; saida jsonb;
begin
 if uid is null then raise insufficient_privilege;end if;
 if p_id is null or p_origem is null or p_nome is null or length(btrim(p_nome)) not between 1 and 160
  or p_modalidades is null or cardinality(p_modalidades)=0 or array_position(p_modalidades,null) is not null
  or not p_modalidades <@ array['margem','saque'] or jsonb_typeof(p_incluir) is distinct from 'object' then
  raise exception 'Confira o nome e as modalidades da campanha.';
 end if;
 perform public.authorize_amigoz(uid,false);
 perform pg_advisory_xact_lock(hashtextextended('crm-reuso:'||uid::text,0));
 pedido:=jsonb_build_array(p_origem,p_convenio,btrim(p_nome),p_modalidades,p_incluir);
 select * into anterior from public.crm_campanhas_reuso where id=p_id and user_id=uid;
 if found then
  if anterior.pedido<>pedido then raise exception 'A confirmação já foi usada com outra seleção.';end if;
  return anterior.resposta;
 end if;
 if not exists(select 1 from public.consulta_lotes where id=p_origem and user_id=uid and tipo='campanha') then raise insufficient_privilege;end if;
 select c.uf,c.servicos into uf_alvo,servicos from public.crm_catalogo_importacao c where c.codigo=p_convenio and c.servicos && array['amigoz_saque','amigoz_margem'];
 if not found or not (array(select 'amigoz_'||m from unnest(p_modalidades) m) <@ servicos) then raise exception 'Modalidade indisponível neste convênio.';end if;
 for escolhido in
  select b.*,
   'margem'=any(p_modalidades) and (b.margem in ('faltante','falha') or (b.margem in ('consultado','importado') and coalesce((p_incluir->b.cpf) ? 'margem',false))) fazer_margem,
   'saque'=any(p_modalidades) and (b.saque in ('faltante','falha') or (b.saque in ('consultado','importado') and coalesce((p_incluir->b.cpf) ? 'saque',false))) fazer_saque
  from apoiarcred_private.crm_base_reuso(uid,p_origem,p_convenio) b order by b.cpf
 loop
  if not escolhido.fazer_margem and not escolhido.fazer_saque then continue;end if;
  modo:=case when escolhido.fazer_margem and escolhido.fazer_saque then 'ambos' when escolhido.fazer_margem then 'margem' else 'saque' end;
  perform public.authorize_amigoz(uid,true);
  insert into public.crm_cadastros(user_id,cpf,nome,telefone) values(uid,escolhido.cpf,escolhido.nome,escolhido.telefone) on conflict(user_id,cpf) do nothing;
  insert into public.amigoz_jobs(user_id,cpf,nome,telefone,convenio,uf,modo,import_id)
  values(uid,escolhido.cpf,escolhido.nome,escolhido.telefone,p_convenio,uf_alvo,modo,p_id);
  leads:=leads+1;
  consultas:=consultas+case when modo='ambos' then 2 else 1 end;
 end loop;
 if leads=0 then raise exception 'Nenhum lead disponível para as consultas escolhidas.';end if;
 saida:=jsonb_build_object('id',p_id,'leads',leads,'consultas',consultas);
 insert into public.crm_campanhas_reuso(id,user_id,origem,nome,convenio,resposta,pedido)
 values(p_id,uid,p_origem,btrim(p_nome),p_convenio,saida,pedido);
 return saida;
end $$;

create function public.crm_status_reuso(p_origem uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') from (
  select c.id,c.nome,c.created_at,c.resposta,
   (select count(*) from public.amigoz_jobs j where j.user_id=c.user_id and j.import_id=c.id and j.status in ('aguardando','processando')) pendentes,
   (select count(*) from public.amigoz_jobs j where j.user_id=c.user_id and j.import_id=c.id and j.status in ('erro','revisao')) atencao
  from public.crm_campanhas_reuso c where c.user_id=auth.uid() and c.origem=p_origem
  order by c.created_at desc limit 20
 ) x;
$$;
revoke all on function public.crm_prever_reuso(uuid,text,text),public.crm_confirmar_reuso(uuid,uuid,text,text,text[],jsonb),public.crm_status_reuso(uuid) from public,anon;
grant execute on function public.crm_prever_reuso(uuid,text,text),public.crm_confirmar_reuso(uuid,uuid,text,text,text[],jsonb),public.crm_status_reuso(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
