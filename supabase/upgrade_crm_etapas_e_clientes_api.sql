begin;
create table public.crm_etapas (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 codigo text not null,
 nome text not null check(length(btrim(nome)) between 1 and 100),
 posicao integer not null check(posicao>=0),
 tipo text not null default 'aberta' check(tipo in ('aberta','ganho','perdido')),
 inicial boolean not null default false,
 destino_exportacao boolean not null default false,
 arquivada boolean not null default false,
 unique(user_id,id), unique(user_id,codigo)
);
create unique index crm_etapas_inicial on public.crm_etapas(user_id) where inicial;
create unique index crm_etapas_exportacao on public.crm_etapas(user_id) where destino_exportacao;
alter table public.crm_etapas enable row level security;
create policy crm_etapas_conta on public.crm_etapas for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.crm_etapas from public,anon,authenticated;
grant select on public.crm_etapas to authenticated;
grant select on public.crm_etapas to service_role;

create function apoiarcred_private.crm_semear_etapas(uid uuid) returns void
language sql security definer set search_path='' as $$
 insert into public.crm_etapas(user_id,codigo,nome,posicao,tipo,inicial,destino_exportacao)
 select uid,codigo,nome,posicao,tipo,codigo='novo',codigo='exportada'
 from (values ('novo','Novo',10,'aberta'),('exportada','Exportadas',20,'aberta'),
 ('contato','Em contato',30,'aberta'),('simulacao','Simulação enviada',40,'aberta'),
 ('negociacao','Em negociação',50,'aberta'),('ganho','Ganho',60,'ganho'),('perdido','Perdido',70,'perdido'))
 defaults(codigo,nome,posicao,tipo)
 where not exists(select 1 from public.crm_etapas where user_id=uid)
 on conflict do nothing;
$$;
revoke all on function apoiarcred_private.crm_semear_etapas(uuid) from public,anon,authenticated;
select apoiarcred_private.crm_semear_etapas(id) from auth.users;

alter table public.crm_cadastros add column cliente_id uuid not null default gen_random_uuid();
create unique index crm_cadastros_cliente_id on public.crm_cadastros(cliente_id);
alter table public.crm_oportunidades add column etapa_id uuid;
update public.crm_oportunidades o set etapa_id=e.id from public.crm_etapas e
 where e.user_id=o.user_id and e.codigo=o.etapa;
alter table public.crm_oportunidades alter column etapa_id set not null;
alter table public.crm_oportunidades drop constraint crm_oportunidades_etapa_check;
alter table public.crm_oportunidades add constraint crm_oportunidades_etapa_conta_fk
 foreign key(user_id,etapa_id) references public.crm_etapas(user_id,id);
create index crm_oportunidades_etapa_pagina on public.crm_oportunidades(user_id,etapa_id,created_at desc,id desc);

create table public.crm_movimentacoes (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null,
 oportunidade_id uuid not null references public.crm_oportunidades(id) on delete cascade,
 etapa_anterior_id uuid not null,
 etapa_id uuid not null,
 nome_anterior text not null,
 nome_destino text not null,
 origem text not null,
 alterado_em timestamptz not null default clock_timestamp()
);
create index crm_movimentacoes_pagina on public.crm_movimentacoes(user_id,oportunidade_id,alterado_em desc,id desc);
alter table public.crm_movimentacoes enable row level security;
create policy crm_movimentacoes_conta on public.crm_movimentacoes for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.crm_movimentacoes from public,anon,authenticated;
grant select on public.crm_movimentacoes to authenticated,service_role;

create function apoiarcred_private.crm_sincronizar_etapa() returns trigger
language plpgsql security definer set search_path='' as $$
declare destino public.crm_etapas; anterior text;
begin
 if tg_op='UPDATE' and new.etapa_id is not distinct from old.etapa_id and new.etapa is not distinct from old.etapa then return new;end if;
 if tg_op='INSERT' then
  perform apoiarcred_private.crm_semear_etapas(new.user_id);
  select * into destino from public.crm_etapas where user_id=new.user_id and not arquivada
   and case when new.etapa_id is not null then id=new.etapa_id when new.etapa='novo' then inicial else codigo=new.etapa end
   for share;
 elsif new.etapa_id is distinct from old.etapa_id then
  select * into destino from public.crm_etapas where user_id=new.user_id and id=new.etapa_id and not arquivada for share;
 else
  select * into destino from public.crm_etapas where user_id=new.user_id and codigo=new.etapa and not arquivada for share;
 end if;
 if destino.id is null then raise exception using errcode='22023',message='Etapa indisponível para a conta.';end if;
 new.etapa_id=destino.id;new.etapa=destino.codigo;
 if tg_op='UPDATE' and new.etapa_id<>old.etapa_id then
  select nome into anterior from public.crm_etapas where user_id=old.user_id and id=old.etapa_id;
  insert into public.crm_movimentacoes(user_id,oportunidade_id,etapa_anterior_id,etapa_id,nome_anterior,nome_destino,origem)
  values(new.user_id,new.id,old.etapa_id,new.etapa_id,anterior,destino.nome,
   coalesce(nullif(current_setting('apoiarcred.crm_origem',true),''),'painel'));
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.crm_sincronizar_etapa() from public,anon,authenticated;
create trigger crm_sincronizar_etapa before insert or update of etapa,etapa_id on public.crm_oportunidades
 for each row execute function apoiarcred_private.crm_sincronizar_etapa();

create function public.crm_listar_etapas() returns setof public.crm_etapas
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();
begin
 if uid is null then raise insufficient_privilege;end if;
 perform apoiarcred_private.crm_semear_etapas(uid);
 return query select * from public.crm_etapas e where e.user_id=uid order by e.posicao,e.id;
end $$;
revoke all on function public.crm_listar_etapas() from public,anon,authenticated;
grant execute on function public.crm_listar_etapas() to authenticated,service_role;

create function public.crm_salvar_etapa(p_id uuid,p_input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); e public.crm_etapas; destino uuid; novo_nome text; nova_posicao integer; arquivar boolean;
begin
 if not coalesce(apoiarcred_private.is_admin(uid),false) then raise insufficient_privilege;end if;
 perform pg_advisory_xact_lock(hashtextextended('crm_etapas:'||uid::text,0));
 perform apoiarcred_private.crm_semear_etapas(uid);
 if p_id is not null then
  select * into e from public.crm_etapas where user_id=uid and id=p_id for update;
  if not found then return null;end if;
 end if;
 novo_nome=btrim(coalesce(p_input->>'nome',e.nome));
 nova_posicao=coalesce((p_input->>'posicao')::integer,e.posicao,(select max(s.posicao)+10 from public.crm_etapas s where s.user_id=uid));
 arquivar=coalesce((p_input->>'arquivada')::boolean,e.arquivada,false);
 if coalesce(length(novo_nome),0) not between 1 and 100 or nova_posicao<0 then raise exception using errcode='22023',message='Informe nome e posição válidos.';end if;
 if arquivar and (coalesce(e.inicial,false) or coalesce(e.destino_exportacao,false)
  or coalesce((p_input->>'inicial')::boolean,false) or coalesce((p_input->>'destino_exportacao')::boolean,false)) then
  raise exception using errcode='22023',message='Defina outra etapa inicial ou de exportação antes de arquivar esta.';
 end if;
 if p_id is null then
  p_id=gen_random_uuid();
  insert into public.crm_etapas(id,user_id,codigo,nome,posicao,arquivada) values(p_id,uid,p_id::text,novo_nome,nova_posicao,arquivar) returning * into e;
 elsif arquivar and not e.arquivada then
  destino=(p_input->>'destino_id')::uuid;
  if exists(select 1 from public.crm_oportunidades where user_id=uid and etapa_id=e.id) then
   if destino is null or destino=e.id or not exists(select 1 from public.crm_etapas where user_id=uid and id=destino and not arquivada)
    then raise exception using errcode='22023',message='Escolha uma etapa ativa de destino para os cartões.';
   end if;
   update public.crm_oportunidades set etapa_id=destino where user_id=uid and etapa_id=e.id;
  end if;
 end if;
 if coalesce((p_input->>'inicial')::boolean,false) then update public.crm_etapas set inicial=false where user_id=uid and inicial and id<>p_id;end if;
 if coalesce((p_input->>'destino_exportacao')::boolean,false) then update public.crm_etapas set destino_exportacao=false where user_id=uid and destino_exportacao and id<>p_id;end if;
 update public.crm_etapas set nome=novo_nome,posicao=nova_posicao,arquivada=arquivar,
  inicial=inicial or coalesce((p_input->>'inicial')::boolean,false),
  destino_exportacao=destino_exportacao or coalesce((p_input->>'destino_exportacao')::boolean,false)
 where user_id=uid and id=p_id returning * into e;
 return to_jsonb(e)-'user_id';
end $$;
revoke all on function public.crm_salvar_etapa(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.crm_salvar_etapa(uuid,jsonb) to authenticated,service_role;

create function public.crm_mover_etapa(p_id uuid,p_etapa_id uuid,p_etapa_original_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); o public.crm_oportunidades;
begin
 if uid is null then raise insufficient_privilege;end if;
 if p_etapa_id is null or p_etapa_original_id is null then raise exception using errcode='22023',message='Informe os IDs das etapas de origem e destino.';end if;
 select * into o from public.crm_oportunidades where user_id=uid and id=p_id for update;
 if not found then return null;end if;
 if o.etapa_id<>p_etapa_original_id then
  return jsonb_build_object('conflito',true,'id',o.id,'etapa_id',o.etapa_id,'etapa',o.etapa);
 end if;
 if o.etapa_id<>p_etapa_id then
  update public.crm_oportunidades set etapa_id=p_etapa_id where user_id=uid and id=p_id returning * into o;
 end if;
 return jsonb_build_object('id',o.id,'etapa_id',o.etapa_id,'etapa',o.etapa);
end $$;
revoke all on function public.crm_mover_etapa(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_mover_etapa(uuid,uuid,uuid) to authenticated,service_role;

create or replace view public.crm_opportunity_cards with(security_invoker=true) as
 select o.id,o.user_id,o.cpf,o.nome,o.produto,o.convenio,o.etapa,o.proxima_acao,o.created_at,o.campos,
 q.saldo_liquidacao,q.emprestimo_disponivel,q.consultado_em as resultado_em,q.created_at as resultado_criado_em,q.servico as resultado_fonte,
 o.automatica,o.sinais_consulta,o.responsavel,o.etapa_id,cl.cliente_id,e.nome as etapa_nome
 from public.crm_oportunidades o left join lateral (
 select c.saldo_liquidacao,c.emprestimo_disponivel,c.consultado_em,c.created_at,c.servico
 from public.crm_consultas c where c.user_id=o.user_id and c.cpf=o.cpf and
 ((o.produto='recompra' and c.servico='digimais_saldo_parcela' and c.saldo_liquidacao is not null)
 or (o.produto='margem' and o.convenio<>'' and c.convenio=o.convenio and c.servico='tjba_margem' and c.emprestimo_disponivel is not null))
 order by c.consultado_em desc nulls last,c.created_at desc,c.id desc limit 1
 ) q on true
 left join public.crm_cadastros cl on cl.user_id=o.user_id and cl.cpf=o.cpf
 join public.crm_etapas e on e.user_id=o.user_id and e.id=o.etapa_id;
create or replace function public.crm_export_opportunities(p_uf text,p_convenio text,p_tipos text[],p_etapa text,p_after uuid default null)
returns setof public.crm_opportunity_cards language sql stable security invoker set search_path='' as $$
 select o.* from public.crm_opportunity_cards o
 where o.user_id=auth.uid()
 and exists(select 1 from public.crm_etapas e where e.user_id=o.user_id and e.id=o.etapa_id and e.tipo='aberta' and not e.arquivada and not e.destino_exportacao and e.codigo<>'exportada')
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
create or replace function public.crm_marcar_exportadas(p_itens jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare total integer;
begin
 if auth.uid() is null then raise insufficient_privilege; end if;
 update public.crm_oportunidades o set etapa=(select codigo from public.crm_etapas where user_id=auth.uid() and destino_exportacao)
 from jsonb_to_recordset(p_itens) as item(id uuid, etapa text)
 where o.id=item.id and o.user_id=auth.uid() and o.etapa=item.etapa
 and exists(select 1 from public.crm_etapas e where e.user_id=o.user_id and e.id=o.etapa_id and e.tipo='aberta' and not e.arquivada and not e.destino_exportacao and e.codigo<>'exportada');
 get diagnostics total=row_count;
 return total;
end $$;

create function public.crm_kanban(p_produto text default '',p_convenio text default '',p_responsavel text default '',
 p_etapa_id uuid default null,p_offset integer default 0) returns jsonb
language sql stable security invoker set search_path='' as $$
 with filtered as materialized (
  select o.id,o.etapa_id,o.created_at from public.crm_oportunidades o
  where o.user_id=auth.uid() and (p_etapa_id is null or o.etapa_id=p_etapa_id)
  and (p_produto='' or o.produto=p_produto)
  and (p_responsavel='' or position(lower(p_responsavel) in lower(coalesce(o.responsavel,'')))>0)
  and (p_convenio='' or o.convenio=p_convenio or (o.convenio='' and exists(
   select 1 from public.crm_classificacao_filtros v where v.user_id=o.user_id and v.cpf=o.cpf and v.convenio=p_convenio
   and (not exists(select 1 from jsonb_object_keys(o.sinais_consulta) k where k<>'digimais')
    or exists(select 1 from jsonb_object_keys(o.sinais_consulta) k
     where regexp_replace(k,'^(amigoz_(margem|saque)|consigx_margem|margem_importada)_','')=v.convenio))
  )))
 ), totals as (select etapa_id,count(*) as total from filtered group by etapa_id)
 select coalesce(jsonb_agg(to_jsonb(e)-'user_id'||jsonb_build_object('total',coalesce(t.total,0),'cartoes',cards.rows)
  order by e.posicao,e.id),'[]'::jsonb)
 from public.crm_etapas e left join totals t on t.etapa_id=e.id
 cross join lateral (
  select coalesce(jsonb_agg(to_jsonb(c)-'user_id' order by c.created_at desc,c.id desc),'[]'::jsonb) rows
  from (select id from filtered where etapa_id=e.id order by created_at desc,id desc offset greatest(p_offset,0) limit 25) page
  join public.crm_opportunity_cards c on c.id=page.id and c.user_id=e.user_id
 ) cards
 where e.user_id=auth.uid() and not e.arquivada and (p_etapa_id is null or e.id=p_etapa_id)
$$;
revoke all on function public.crm_kanban(text,text,text,uuid,integer) from public,anon;
grant execute on function public.crm_kanban(text,text,text,uuid,integer) to authenticated;

create function apoiarcred_private.crm_cliente_perfil(uid uuid,p_cpf text,p_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('cliente_id',c.cliente_id,'cpf',regexp_replace(c.cpf,'^([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{2})$', '\1.\2.\3-\4'),
  'nome',c.nome,'telefone',c.telefone,'data_nascimento',c.data_nascimento,
  'convenios',coalesce((select jsonb_agg(to_jsonb(v)-'user_id'-'cpf' order by v.uf,v.convenio) from public.crm_classificacoes v where v.user_id=uid and v.cpf=c.cpf),'[]'),
  'vinculos',coalesce((select jsonb_agg(to_jsonb(v)-'user_id'-'cpf' order by v.uf,v.convenio,v.matricula) from public.crm_vinculos v where v.user_id=uid and v.cpf=c.cpf),'[]'),
  'margens',coalesce((select jsonb_agg(to_jsonb(m)-'user_id'-'cpf' order by m.observado_em desc,m.convenio,m.matricula,m.produto) from public.crm_margens_vinculo m where m.user_id=uid and m.cpf=c.cpf),'[]'),
  'resultados',coalesce((select jsonb_agg(to_jsonb(f)-'user_id'-'cpf' order by f.registrado_em desc,f.referencia) from public.crm_dados_cliente f where f.user_id=uid and f.cpf=c.cpf),'[]'),
  'oportunidades',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'produto',o.produto,'convenio',o.convenio,
    'etapa_id',o.etapa_id,'etapa',e.codigo,'etapa_nome',e.nome) order by o.created_at desc,o.id)
   from public.crm_oportunidades o join public.crm_etapas e on e.user_id=o.user_id and e.id=o.etapa_id where o.user_id=uid and o.cpf=c.cpf),'[]'))
 from public.crm_cadastros c where c.user_id=uid and (p_cpf is null or c.cpf=p_cpf) and (p_id is null or c.cliente_id=p_id)
 and (p_cpf is not null or p_id is not null)
$$;
revoke all on function apoiarcred_private.crm_cliente_perfil(uuid,text,uuid) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_cliente_perfil(uuid,text,uuid) to service_role;

create or replace function apoiarcred_private.api_route_oportunidades(uid uuid,method text,route text,p jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 stages text[]:=array['novo','exportada','contato','simulacao','negociacao','ganho','perdido'];
 open_stages text[]:=array['novo','contato','simulacao','negociacao'];
 products text[]:=array['margem','recompra','saque'];
 selected text[];
 stage text;
 opportunity_id uuid;
 data jsonb;
 total integer;
 page_no integer;
 page_size integer;
begin
 select array_agg(codigo),array_agg(codigo) filter(where tipo='aberta' and not destino_exportacao and codigo<>'exportada')
 into stages,open_stages from public.crm_etapas where user_id=uid and not arquivada;
 if route <> '/oportunidades' and route not like '/oportunidades/%' then
  return apoiarcred_private.api_route_legacy(uid,method,route,p);
 end if;

 if method='GET' and route='/oportunidades' then
  stage:=p->>'etapa';
  selected:=string_to_array(p->>'tipos',',');
  page_no:=coalesce((p->>'page')::integer,1);
  page_size:=coalesce((p->>'page_size')::integer,50);
  if (stage is not null and not stage=any(stages)) or (selected is not null and not selected<@products)
   or page_no not between 1 and 1000000 or page_size not between 1 and 100
   or coalesce(p->>'exportaveis','false') not in ('true','false') then
   return apoiarcred_private.api_error(422,'invalid_filter','Confira etapa, tipos, exportaveis e paginação.');
  end if;
  with filtered as materialized (
   select c.* from public.crm_opportunity_cards c
   where c.user_id=uid and (stage is null or c.etapa=stage)
    and (selected is null or c.produto=any(selected))
    and (coalesce(p->>'exportaveis','false')='false' or c.etapa=any(open_stages))
  )
  select (select count(*) from filtered),
   coalesce((select jsonb_agg(to_jsonb(x)-'user_id' order by x.created_at desc,x.id)
    from (select * from filtered order by created_at desc,id limit page_size offset (page_no-1)*page_size) x),'[]')
  into total,data;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page_no,'page_size',page_size,'total',total)));
 end if;

 if method='GET' and route ~ '^/oportunidades/[0-9a-fA-F-]{36}$' then
  opportunity_id:=split_part(route,'/',3)::uuid;
  select to_jsonb(c)-'user_id' into data from public.crm_opportunity_cards c where c.user_id=uid and c.id=opportunity_id;
  if not found then return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.'); end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;

 if method='POST' and route ~ '^/oportunidades/[0-9a-fA-F-]{36}/etapa$' then
  opportunity_id:=split_part(route,'/',3)::uuid;
  stage:=p->>'etapa';
  if stage is null or not stage=any(stages) or (p->>'etapa_original') is null or not (p->>'etapa_original')=any(stages) then
   return apoiarcred_private.api_error(422,'invalid_stage','Informe etapa e etapa_original válidas.');
  end if;
  update public.crm_oportunidades o set etapa=stage
  where o.user_id=uid and o.id=opportunity_id and o.etapa=p->>'etapa_original'
  returning jsonb_build_object('id',o.id,'etapa',o.etapa) into data;
  if not found then
   if exists(select 1 from public.crm_oportunidades o where o.user_id=uid and o.id=opportunity_id) then
    return apoiarcred_private.api_error(409,'stage_changed','A etapa mudou. Consulte a oportunidade novamente.');
   end if;
   return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.');
  end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;

 if method='POST' and route='/oportunidades/exportacao' then
  if jsonb_typeof(p->'itens') is distinct from 'array' then
   return apoiarcred_private.api_error(422,'invalid_items','Informe itens com id e etapa.');
  end if;
  if jsonb_array_length(p->'itens') not between 1 and 500 or exists(
   select 1 from jsonb_to_recordset(p->'itens') item(id uuid,etapa text)
   where item.id is null or item.etapa is null or not item.etapa=any(open_stages)
  ) then
   return apoiarcred_private.api_error(422,'invalid_items','Envie de 1 a 500 itens com id e etapa aberta.');
  end if;
  with moved as (
   update public.crm_oportunidades o set etapa=(select codigo from public.crm_etapas where user_id=uid and destino_exportacao)
   from jsonb_to_recordset(p->'itens') item(id uuid,etapa text)
   where o.user_id=uid and o.id=item.id and o.etapa=item.etapa and o.etapa=any(open_stages)
   returning o.id
  )
  select count(*),coalesce(jsonb_agg(id order by id),'[]') into total,data from moved;
  return apoiarcred_private.api_response(200,jsonb_build_object('movidas',total,'ids',data));
 end if;
 return apoiarcred_private.api_error(404,'route_not_found','Rota não encontrada.');
end $$;

alter function apoiarcred_private.api_route(uuid,text,text,jsonb) rename to api_route_antes_etapas;
create function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare parts text[]=string_to_array(trim(both '/' from route),'/');
 data jsonb; response jsonb; card_id uuid; client_id uuid; cpf_value text; code text;
 stage_id uuid; previous_id uuid; total integer; page integer; size integer;
begin
 perform set_config('apoiarcred.crm_origem','api',true);
 if route='/crm/etapas' and method='GET' then
  perform set_config('request.jwt.claim.sub',uid::text,true);
  select coalesce(jsonb_agg(to_jsonb(e)-'user_id' order by e.posicao,e.id),'[]') into data from public.crm_listar_etapas() e;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if (route='/crm/etapas' and method='POST') or (route ~ '^/crm/etapas/[0-9a-fA-F-]{36}$' and method='PATCH') then
  perform set_config('request.jwt.claim.sub',uid::text,true);
  data=public.crm_salvar_etapa(nullif(parts[3],'')::uuid,p);
  if data is null then return apoiarcred_private.api_error(404,'not_found','Etapa não encontrada.');end if;
  return apoiarcred_private.api_response(case when method='POST' then 201 else 200 end,jsonb_build_object('data',data));
 end if;
 if route ~ '^/oportunidades/[0-9a-fA-F-]{36}/etapa$' and method='POST' then
  card_id=parts[2]::uuid;
  if p ? 'etapa_id' or p ? 'etapa_original_id' then
   stage_id=(p->>'etapa_id')::uuid;previous_id=(p->>'etapa_original_id')::uuid;
  else
   select id into stage_id from public.crm_etapas where user_id=uid and codigo=p->>'etapa' and not arquivada;
   select id into previous_id from public.crm_etapas where user_id=uid and codigo=p->>'etapa_original';
  end if;
  perform set_config('request.jwt.claim.sub',uid::text,true);
  data=public.crm_mover_etapa(card_id,stage_id,previous_id);
  if data is null then return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.');end if;
  if data ? 'conflito' then
   return apoiarcred_private.api_response(409,jsonb_build_object('error',jsonb_build_object('code','stage_changed',
    'message','A etapa mudou. Consulte a oportunidade novamente.','details',data-'conflito')));
  end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if (route='/clientes/buscar' and method='POST') or (route ~ '^/clientes/[0-9a-fA-F-]{36}$' and method='GET') then
  if method='POST' then
   cpf_value=regexp_replace(coalesce(p->>'cpf',''),'[^0-9]','','g');
   if cpf_value!~'^[0-9]{11}$' then return apoiarcred_private.api_error(422,'invalid_cpf','Informe CPF com 11 dígitos.');end if;
  else client_id=parts[2]::uuid;end if;
  data=apoiarcred_private.crm_cliente_perfil(uid,cpf_value,client_id);
  if data is null then return apoiarcred_private.api_error(404,'not_found','Cliente não encontrado.');end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if method='GET' and (route ~ '^/clientes/[0-9a-fA-F-]{36}/consultas$' or route ~ '^/oportunidades/[0-9a-fA-F-]{36}/movimentacoes$') then
  page=coalesce((p->>'page')::integer,1);size=coalesce((p->>'page_size')::integer,50);
  if page not between 1 and 1000000 or size not between 1 and 100 then return apoiarcred_private.api_error(422,'invalid_filter','Paginação inválida.');end if;
  if parts[1]='clientes' then
   select cpf into cpf_value from public.crm_cadastros where user_id=uid and cliente_id=parts[2]::uuid;
   if not found then return apoiarcred_private.api_error(404,'not_found','Cliente não encontrado.');end if;
   select count(*) into total from public.crm_consultas where user_id=uid and cpf=cpf_value;
   select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') into data from (
    select id,servico,convenio,status,created_at,consultado_em,matricula,saldo_liquidacao,valor_parcela,emprestimo_disponivel,cartao_disponivel
    from public.crm_consultas where user_id=uid and cpf=cpf_value order by created_at desc,id desc offset (page-1)*size limit size
   ) x;
  else
   card_id=parts[2]::uuid;
   if not exists(select 1 from public.crm_oportunidades where user_id=uid and id=card_id) then return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.');end if;
   select count(*) into total from public.crm_movimentacoes where user_id=uid and oportunidade_id=card_id;
   select coalesce(jsonb_agg(to_jsonb(x)-'user_id' order by x.alterado_em desc,x.id desc),'[]') into data from (
    select * from public.crm_movimentacoes where user_id=uid and oportunidade_id=card_id order by alterado_em desc,id desc offset (page-1)*size limit size
   ) x;
  end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 if method='GET' and route='/oportunidades' and p ? 'etapa_id' then
  select codigo into code from public.crm_etapas where user_id=uid and id=(p->>'etapa_id')::uuid and not arquivada;
  if not found then return apoiarcred_private.api_error(422,'invalid_stage','Etapa indisponível.');end if;
  p=p||jsonb_build_object('etapa',code);
 end if;
 response=apoiarcred_private.api_route_antes_etapas(uid,method,route,p);
 if method='GET' and route ~ '^/oportunidades/[0-9a-fA-F-]{36}$' and p->>'include'='cliente'
  and response->>'status'='200' then
  client_id=(response#>>'{body,data,cliente_id}')::uuid;
  data=apoiarcred_private.crm_cliente_perfil(uid,null,client_id);
  response=jsonb_set(response,'{body,data,cliente}',coalesce(data,'null'::jsonb));
 end if;
 return response;
exception when invalid_parameter_value then
 return apoiarcred_private.api_error(422,'validation_error',sqlerrm);
end $$;
revoke all on function apoiarcred_private.api_route(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.api_route(uuid,text,text,jsonb) to service_role;

create or replace function public.api_execute(p_hash text,p_method text,p_route text,p_payload jsonb default '{}',p_key text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t apoiarcred_private.api_tokens;scope text;fingerprint text;cached apoiarcred_private.api_idempotency;result jsonb;
begin
 select * into t from apoiarcred_private.api_tokens where token_hash=p_hash for update;
 if not found or t.revoked_at is not null or (t.expires_at is not null and t.expires_at<=now()) then return apoiarcred_private.api_error(401,'invalid_token','Token inválido, expirado ou revogado.');end if;
 if not apoiarcred_private.can_integrate(t.user_id) then return apoiarcred_private.api_error(403,'integrations_disabled','Integrações não estão liberadas para esta conta.');end if;
 scope=case when p_method='GET' or p_route in ('/leads/buscar','/clientes/buscar') then 'read' when p_route='/consultas' then 'consultas:create' else 'campanhas:write' end;
 if not scope=any(t.scopes) then return apoiarcred_private.api_error(403,'insufficient_scope','O token não possui esta permissão.');end if;
 if t.rate_window is null or t.rate_window<now()-interval '1 minute' then t.rate_count=0;t.rate_window=now();end if;
 if t.rate_count>=120 then return apoiarcred_private.api_error(429,'rate_limit','Limite de 120 requisições por minuto.');end if;
 update apoiarcred_private.api_tokens set rate_count=t.rate_count+1,rate_window=t.rate_window,last_used_at=now() where id=t.id;
 if p_method not in ('GET','POST','PATCH') or jsonb_typeof(p_payload) is distinct from 'object' then return apoiarcred_private.api_error(400,'invalid_request','Requisição inválida.');end if;
 if p_method in ('POST','PATCH') and p_route not in ('/leads/buscar','/clientes/buscar') and (p_key is null or length(p_key) not between 1 and 128) then return apoiarcred_private.api_error(400,'idempotency_required','Envie Idempotency-Key de 1 a 128 caracteres.');end if;
 delete from apoiarcred_private.api_idempotency where token_id=t.id and created_at<now()-interval '24 hours';
 if p_method in ('POST','PATCH') and p_route not in ('/leads/buscar','/clientes/buscar') then
  fingerprint=encode(extensions.digest(p_method||p_route||p_payload::text,'sha256'),'hex');
  select * into cached from apoiarcred_private.api_idempotency where token_id=t.id and key=p_key;
  if found then
   if cached.fingerprint<>fingerprint then return apoiarcred_private.api_error(409,'idempotency_conflict','Chave já usada com outra rota ou payload.');end if;
   return cached.response||'{"replayed":true}';
  end if;
 end if;
 begin
  result=apoiarcred_private.api_route(t.user_id,p_method,p_route,p_payload);
 exception when insufficient_privilege then
  result=apoiarcred_private.api_error(403,'partner_permission',sqlerrm);
 when sqlstate 'PT429' then
  result=apoiarcred_private.api_error(429,'daily_limit',sqlerrm);
 when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value or check_violation or not_null_violation then
  result=apoiarcred_private.api_error(422,'validation_error','Dados inválidos. Confira UUIDs, paginação e campos obrigatórios.');
 end;
 if fingerprint is not null and (result->>'status')::integer<300 then insert into apoiarcred_private.api_idempotency(token_id,key,fingerprint,response) values(t.id,p_key,fingerprint,result);end if;
 return result;
end $$;
notify pgrst,'reload schema';

commit;
