begin;
alter table public.crm_movimentacoes add column autor_id uuid, add column api_token_id uuid;

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
 clients integer;
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
  select (select count(*) from filtered),(select count(distinct cpf) from filtered),
   coalesce((select jsonb_agg(to_jsonb(x)-'user_id' order by x.created_at desc,x.id)
    from (select * from filtered order by created_at desc,id limit page_size offset (page_no-1)*page_size) x),'[]')
  into total,clients,data;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page_no,'page_size',page_size,'total',total,'clientes_unicos',clients)));
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

create or replace function apoiarcred_private.crm_sincronizar_etapa() returns trigger
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
  insert into public.crm_movimentacoes(user_id,oportunidade_id,etapa_anterior_id,etapa_id,nome_anterior,nome_destino,origem,autor_id,api_token_id)
  values(new.user_id,new.id,old.etapa_id,new.etapa_id,anterior,destino.nome,
   coalesce(nullif(current_setting('apoiarcred.crm_origem',true),''),'painel'),auth.uid(),
   nullif(current_setting('apoiarcred.crm_token_id',true),'')::uuid);
 end if;
 return new;
end $$;

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
  perform set_config('apoiarcred.crm_token_id',t.id::text,true);
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

commit;
