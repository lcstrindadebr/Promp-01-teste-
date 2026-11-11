begin;
create table public.crm_dados_cliente (
 user_id uuid not null, cpf text not null, referencia text not null,
 instituicao text not null, tipo text not null check(tipo in ('margem','saque_complementar','saldo_parcela')),
 convenio text, origem text not null check(origem in ('consulta','importacao')),
 registrado_em timestamptz not null, dados jsonb not null,
 primary key(user_id,cpf,referencia),
 foreign key(user_id,cpf) references public.crm_cadastros(user_id,cpf) on delete cascade
);
alter table public.crm_dados_cliente enable row level security;
revoke all on public.crm_dados_cliente from public,anon,authenticated;
grant select on public.crm_dados_cliente to authenticated;
create policy crm_dados_cliente_leitura on public.crm_dados_cliente for select to authenticated using(user_id=(select auth.uid()));

create function apoiarcred_private.crm_sync_dados_cliente()
returns trigger language plpgsql security definer set search_path='' as $$
declare item record;
begin
 for item in select key,value from jsonb_each(new.resumo_consultas) loop
  if tg_op='UPDATE' and old.resumo_consultas->item.key is not distinct from item.value then continue;end if;
  insert into public.crm_dados_cliente(user_id,cpf,referencia,instituicao,tipo,convenio,origem,registrado_em,dados)
  values(new.user_id,new.cpf,item.key,
   case when left(item.key,7)='amigoz_' then 'amigoz' when left(item.key,8)='consigx_' then 'consigx'
        when item.key='digimais' then 'digimais' else 'informada' end,
   case when left(item.key,13)='amigoz_saque_' then 'saque_complementar'
        when item.key='digimais' then 'saldo_parcela' else 'margem' end,
   nullif(regexp_replace(item.key,'^(amigoz_(margem|saque)|consigx_margem|margem_importada)_|^digimais$',''),''),
   coalesce(item.value->>'origem','consulta'),(item.value->>'data')::timestamptz,item.value->'dados')
  on conflict(user_id,cpf,referencia) do update set origem=excluded.origem,registrado_em=excluded.registrado_em,dados=excluded.dados;
 end loop;
 return new;
end $$;
revoke all on function apoiarcred_private.crm_sync_dados_cliente() from public,anon,authenticated;
create trigger crm_dados_cliente_sync after insert or update of resumo_consultas on public.crm_cadastros
for each row execute function apoiarcred_private.crm_sync_dados_cliente();

-- Reapply existing snapshots to the profile table without launching consultations.
insert into public.crm_dados_cliente(user_id,cpf,referencia,instituicao,tipo,convenio,origem,registrado_em,dados)
select c.user_id,c.cpf,s.key,
 case when left(s.key,7)='amigoz_' then 'amigoz' when left(s.key,8)='consigx_' then 'consigx'
      when s.key='digimais' then 'digimais' else 'informada' end,
 case when left(s.key,13)='amigoz_saque_' then 'saque_complementar' when s.key='digimais' then 'saldo_parcela' else 'margem' end,
 nullif(regexp_replace(s.key,'^(amigoz_(margem|saque)|consigx_margem|margem_importada)_|^digimais$',''),''),
 'consulta',(s.value->>'data')::timestamptz,s.value->'dados'
from public.crm_cadastros c cross join lateral jsonb_each(c.resumo_consultas) s;

create function public.crm_filtrar_kanban(p_etapa text,p_produto text,p_convenio text,p_responsavel text,p_offset integer)
returns setof public.crm_opportunity_cards language sql stable security invoker set search_path='' as $$
 select o.* from public.crm_opportunity_cards o
 where o.user_id=auth.uid() and o.etapa=p_etapa
 and (p_produto='' or o.produto=p_produto)
 and (p_responsavel='' or position(lower(p_responsavel) in lower(coalesce(o.responsavel,'')))>0)
 and (p_convenio='' or o.convenio=p_convenio or (o.convenio='' and exists(
  select 1 from public.crm_classificacao_filtros v where v.user_id=o.user_id and v.cpf=o.cpf and v.convenio=p_convenio
  and (not exists(select 1 from jsonb_object_keys(o.sinais_consulta) k where k<>'digimais')
   or exists(select 1 from jsonb_object_keys(o.sinais_consulta) k
    where regexp_replace(k,'^(amigoz_(margem|saque)|consigx_margem|margem_importada)_','')=v.convenio))
 )))
 order by o.created_at desc,o.id desc offset greatest(p_offset,0) limit 26
$$;
revoke all on function public.crm_filtrar_kanban(text,text,text,text,integer) from public,anon;
grant execute on function public.crm_filtrar_kanban(text,text,text,text,integer) to authenticated;
create or replace function apoiarcred_private.crm_import_and_start(p_request_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); fingerprint text; previous public.crm_import_requests;
 count_clients integer; n integer=0; cid uuid; lots jsonb='[]'; mode text;
 agreement public.crm_catalogo_importacao; result jsonb; row jsonb; imported record; ref text;
begin
 if uid is null or p_request_id is null then raise insufficient_privilege;end if;
 -- Serialize retries of one confirmation; an ambiguous HTTP response is safe to retry.
 perform pg_advisory_xact_lock(hashtextextended(uid::text||p_request_id::text,0));
 fingerprint=md5(jsonb_build_object('uf',p_uf,'convenio',p_convenio,'servicos',p_servicos,'rows',p_rows)::text);
 select * into previous from public.crm_import_requests where user_id=uid and request_id=p_request_id;
 if found then
  if previous.fingerprint<>fingerprint then raise exception 'Esta confirmação já foi usada com outros dados. Reabra a importação.';end if;
  return previous.response;
 end if;
 count_clients=apoiarcred_private.crm_import_catalog_clients(p_uf,p_convenio,p_servicos,p_rows);
 update public.crm_cadastros c set data_nascimento=x.data_nascimento::date
 from jsonb_to_recordset(p_rows) x(cpf text,data_nascimento text)
 where c.user_id=uid and c.cpf=x.cpf and nullif(x.data_nascimento,'') is not null;
 insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,fonte,confirmado_em)
 select uid,x.cpf,p_uf,p_convenio,btrim(x.numero_matricula),'importacao',now()
 from jsonb_to_recordset(p_rows) x(cpf text,numero_matricula text)
 where nullif(btrim(x.numero_matricula),'') is not null
 on conflict(user_id,cpf,uf,convenio,matricula) do nothing;

 for imported in select * from jsonb_to_recordset(p_rows) x(cpf text,margem_livre numeric,saque_amigoz_elegivel boolean,saque_amigoz_valor numeric) loop
  if imported.saque_amigoz_valor<0 or (imported.saque_amigoz_elegivel=false and imported.saque_amigoz_valor>0) then
   raise exception 'Dados de saque complementar Amigoz incompatíveis.';
  end if;
  if imported.margem_livre is not null then
   ref:='margem_importada_'||p_convenio;
   perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,now(),
    jsonb_build_object('margem_emprestimo',imported.margem_livre),case when imported.margem_livre>20 then 'margem' end);
   update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref,'origem'],'"importacao"')
    where user_id=uid and cpf=imported.cpf;
  end if;
  if imported.saque_amigoz_elegivel is not null or imported.saque_amigoz_valor is not null then
   ref:='amigoz_saque_'||p_convenio;
   perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,now(),
    jsonb_build_array(jsonb_build_object('elegivel',case when imported.saque_amigoz_elegivel is true then 'Sim'
      when imported.saque_amigoz_elegivel is false then 'Não' end,'valor_saque_disponivel',imported.saque_amigoz_valor)),
    case when imported.saque_amigoz_elegivel is true and imported.saque_amigoz_valor>0 then 'saque' end);
   update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref,'origem'],'"importacao"')
    where user_id=uid and cpf=imported.cpf;
  end if;
 end loop;

 select * into agreement from public.crm_catalogo_importacao where uf=p_uf and codigo=p_convenio;
 if 'digimais_saldo'=any(p_servicos) then
  if exists(select 1 from jsonb_to_recordset(p_rows) x(nome text,telefone text) where coalesce(length(btrim(nome)),0)=0 or coalesce(telefone,'')!~'^[0-9]{10,13}$') then
   raise exception 'Digi+ exige nome e telefone com DDD em todas as linhas.';
  end if;
  cid=public.create_consulta_campaign('Importação · '||left(agreement.nome,100)||' · Digi+',p_rows);
  lots=lots||jsonb_build_array(jsonb_build_object('id',cid,'servico','digimais_saldo_parcela'));
  n=n+count_clients;
 end if;
 if 'consigx_margem'=any(p_servicos) then
  cid=public.create_consigx_campaign('Importação · '||left(agreement.nome,100)||' · ConsigX',p_rows,p_convenio);
  lots=lots||jsonb_build_array(jsonb_build_object('id',cid,'servico','tjba_margem'));
  n=n+count_clients;
 end if;
 if p_servicos && array['amigoz_saque','amigoz_margem'] then
  mode=case when array['amigoz_saque','amigoz_margem'] <@ p_servicos then 'ambos' when 'amigoz_margem'=any(p_servicos) then 'margem' else 'saque' end;
  if exists(select 1 from jsonb_array_elements(p_rows) x where length(coalesce(x->>'numero_matricula',''))>256) then raise exception 'Matrícula deve ter até 256 caracteres.';end if;
  -- Same shared quota and access contract as the Amigoz individual API.
  for row in select value from jsonb_array_elements(p_rows) loop
   perform public.authorize_amigoz(uid,true);
   insert into public.amigoz_jobs(user_id,cpf,nome,telefone,convenio,uf,modo,numero_matricula,import_id)
   values(uid,row->>'cpf',row->>'nome',row->>'telefone',p_convenio,p_uf,mode,nullif(btrim(row->>'numero_matricula'),''),p_request_id);
  end loop;
  n=n+count_clients;
 end if;
 result=jsonb_build_object('clientes',count_clients,'consultas',n,'campanhas',lots);
 insert into public.crm_import_requests(user_id,request_id,fingerprint,response) values(uid,p_request_id,fingerprint,result);
 return result;
end $$;
create or replace function public.crm_export_opportunities(p_uf text,p_convenio text,p_tipos text[],p_etapa text,p_after uuid default null)
returns setof public.crm_opportunity_cards language sql stable security invoker set search_path='' as $$
 select o.* from public.crm_opportunity_cards o
 where o.user_id=auth.uid()
 and o.etapa in ('novo','contato','simulacao','negociacao')
 and (p_etapa='' or o.etapa=p_etapa)
 and o.produto=any(p_tipos)
 and (p_after is null or o.id>p_after)
 and ((p_uf='' and p_convenio='') or exists(
  select 1 from public.crm_classificacao_filtros v
  where v.user_id=o.user_id and v.cpf=o.cpf
   and (p_uf='' or v.uf=p_uf) and (p_convenio='' or v.convenio=p_convenio)
   and (o.convenio='' or v.convenio=o.convenio)
   and (not exists(select 1 from jsonb_object_keys(o.sinais_consulta) k where k<>'digimais')
        or exists(select 1 from jsonb_object_keys(o.sinais_consulta) k
           where regexp_replace(k,'^(amigoz_(margem|saque)|consigx_margem|margem_importada)_','')=v.convenio))
 ))
 order by o.id limit 500
$$;
revoke all on function public.crm_export_opportunities(text,text,text[],text,uuid) from public,anon;
grant execute on function public.crm_export_opportunities(text,text,text[],text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
