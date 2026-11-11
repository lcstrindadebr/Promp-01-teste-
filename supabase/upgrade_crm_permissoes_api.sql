begin;
create or replace function apoiarcred_private.manage_api_tokens(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); secret text; scopes text[]; expires timestamptz; result jsonb; tid uuid;
begin
 if uid is null or not apoiarcred_private.can_integrate(uid) then raise insufficient_privilege using message='Integrações não estão liberadas para esta conta.';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'prefix',t.prefix,'scopes',t.scopes,'created_at',t.created_at,'expires_at',t.expires_at,'revoked_at',t.revoked_at,'last_used_at',t.last_used_at) order by t.created_at desc),'[]') into result from apoiarcred_private.api_tokens t where t.user_id=uid;return result;
 elsif p_action='revoke' then
  update apoiarcred_private.api_tokens set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=(p_input->>'id')::uuid and user_id=uid;
  if not found then raise insufficient_privilege;end if;return '{"revoked":true}';
 elsif p_action<>'create' then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 80 then raise exception 'Informe nome de até 80 caracteres.';end if;
 select coalesce(array_agg(distinct x),'{}') into scopes from jsonb_array_elements_text(p_input->'scopes') x;
 if cardinality(scopes)=0 or not scopes<@array['read','consultas:create','campanhas:write','crm:read','crm:write'] then raise exception 'Permissões inválidas.';end if;
 expires=nullif(p_input->>'expires_at','')::timestamptz;
 if expires is not null and (expires<=now() or expires>now()+interval '366 days') then raise exception 'Validade deve estar entre agora e um ano.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if (select count(*) from apoiarcred_private.api_tokens where user_id=uid and revoked_at is null and (expires_at is null or expires_at>now()))>=20 then raise exception 'Limite de 20 tokens ativos. Revogue um token antes.';end if;
 secret='apc_'||encode(extensions.gen_random_bytes(32),'hex');
 insert into apoiarcred_private.api_tokens(user_id,name,token_hash,prefix,scopes,expires_at)
 values(uid,btrim(p_input->>'name'),encode(extensions.digest(secret,'sha256'),'hex'),left(secret,12),scopes,expires) returning id into tid;
 return jsonb_build_object('id',tid,'token',secret,'expires_at',expires);
end $$;

create or replace function public.api_execute(p_hash text,p_method text,p_route text,p_payload jsonb default '{}',p_key text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t apoiarcred_private.api_tokens;scope text;crm_scope text;fingerprint text;cached apoiarcred_private.api_idempotency;result jsonb;
begin
 select * into t from apoiarcred_private.api_tokens where token_hash=p_hash for update;
 if not found or t.revoked_at is not null or (t.expires_at is not null and t.expires_at<=now()) then return apoiarcred_private.api_error(401,'invalid_token','Token inválido, expirado ou revogado.');end if;
 if not apoiarcred_private.can_integrate(t.user_id) then return apoiarcred_private.api_error(403,'integrations_disabled','Integrações não estão liberadas para esta conta.');end if;
 scope=case when p_method='GET' or p_route in ('/leads/buscar','/clientes/buscar') then 'read' when p_route='/consultas' then 'consultas:create' else 'campanhas:write' end;
 if p_route ~ '^/(crm/etapas|oportunidades)(/|$)' or p_route='/clientes/buscar'
  or p_route ~ '^/clientes/[0-9a-fA-F-]{36}(/consultas)?$' then
  crm_scope=case when scope='read' then 'crm:read' else 'crm:write' end;
 end if;
 if not (scope=any(t.scopes) or coalesce(crm_scope=any(t.scopes),false)) then return apoiarcred_private.api_error(403,'insufficient_scope','O token não possui esta permissão.');end if;
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
