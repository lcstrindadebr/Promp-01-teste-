-- Partner permissions are enforced on job writes, including REST and API service-role writes.
create table apoiarcred_private.user_profiles(
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('admin','partner')),name text not null,email text not null,
 active boolean not null default true,created_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table apoiarcred_private.partner_permissions(
 user_id uuid not null references apoiarcred_private.user_profiles(user_id) on delete cascade,
 service text not null check(service in ('digimais_saldo_parcela','tjba_margem')),
 enabled boolean not null default false,allow_individual boolean not null default false,
 daily_limit integer not null default 0 check(daily_limit between 0 and 100000),allow_campaign boolean not null default false,
 primary key(user_id,service)
);
create table apoiarcred_private.partner_daily_usage(
 user_id uuid not null references apoiarcred_private.user_profiles(user_id) on delete cascade,
 service text not null,day date not null,used integer not null default 0 check(used>=0),primary key(user_id,service,day)
);
alter table apoiarcred_private.user_profiles enable row level security;
alter table apoiarcred_private.partner_permissions enable row level security;
alter table apoiarcred_private.partner_daily_usage enable row level security;
revoke all on apoiarcred_private.user_profiles,apoiarcred_private.partner_permissions,apoiarcred_private.partner_daily_usage from public,anon,authenticated;
grant all on apoiarcred_private.user_profiles,apoiarcred_private.partner_permissions,apoiarcred_private.partner_daily_usage to service_role;
create policy profiles_service on apoiarcred_private.user_profiles for all to service_role using(true) with check(true);
create policy permissions_service on apoiarcred_private.partner_permissions for all to service_role using(true) with check(true);
create policy usage_service on apoiarcred_private.partner_daily_usage for all to service_role using(true) with check(true);
-- Safe bootstrap: only the sole existing account becomes admin. Multi-user projects
-- must explicitly assign their first admin via the SQL editor; never trust user_metadata.
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
 select id,'admin',split_part(email,'@',1),email from auth.users where deleted_at is null
 and (select count(*) from auth.users where deleted_at is null)=1;

create function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid;
$$;
revoke all on function apoiarcred_private.access_for(uuid) from public,anon,authenticated;
grant execute on function apoiarcred_private.access_for(uuid) to service_role;
create function apoiarcred_private.my_access() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin if auth.uid() is null then raise insufficient_privilege;end if;return apoiarcred_private.access_for(auth.uid());end $$;
revoke all on function apoiarcred_private.my_access() from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.my_access() to authenticated;
create function public.my_access() returns jsonb language sql stable security invoker set search_path='' as $$select apoiarcred_private.my_access();$$;
revoke all on function public.my_access() from public,anon,authenticated,service_role;
grant execute on function public.my_access() to authenticated;
create function apoiarcred_private.is_admin(uid uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='admin' and active);$$;
revoke all on function apoiarcred_private.is_admin(uuid) from public,anon,authenticated;
grant execute on function apoiarcred_private.is_admin(uuid) to service_role;
create function apoiarcred_private.my_admin() returns boolean language sql stable security definer set search_path='' as $$select apoiarcred_private.is_admin(auth.uid());$$;
revoke all on function apoiarcred_private.my_admin() from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.my_admin() to authenticated;
create function public.am_i_admin() returns boolean language sql stable security invoker set search_path='' as $$select apoiarcred_private.my_admin();$$;
revoke all on function public.am_i_admin() from public,anon,authenticated,service_role;
grant execute on function public.am_i_admin() to authenticated;
drop policy if exists monitor_read on public.vps_monitoramento;
create policy monitor_read on public.vps_monitoramento for select to authenticated using((select public.am_i_admin()));

create function apoiarcred_private.check_partner_access(uid uuid,service_id text,mode text,consume boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles;rule apoiarcred_private.partner_permissions;today date=(now() at time zone 'America/Sao_Paulo')::date;n integer;
begin
 select * into profile from apoiarcred_private.user_profiles where user_id=uid for share;
 if not found or not profile.active then raise insufficient_privilege using message='Conta sem acesso ativo. Solicite liberação ao administrador.';end if;
 if profile.role='admin' then return;end if;
 select * into rule from apoiarcred_private.partner_permissions where user_id=uid and service=service_id for share;
 if not found or not rule.enabled then raise insufficient_privilege using message='Tipo de higienização não autorizado para este parceiro.';end if;
 if mode='campanha' then
  if not rule.allow_campaign then raise insufficient_privilege using message='Campanhas não estão habilitadas para este tipo de higienização.';end if;
 elsif mode='individual' then
  if not rule.allow_individual or rule.daily_limit=0 then raise insufficient_privilege using message='Consultas individuais não estão habilitadas para este tipo de higienização.';end if;
  if consume then
   insert into apoiarcred_private.partner_daily_usage(user_id,service,day,used) values(uid,service_id,today,0) on conflict do nothing;
   update apoiarcred_private.partner_daily_usage set used=used+1 where user_id=uid and service=service_id and day=today and used<rule.daily_limit;
   get diagnostics n=row_count;
   if n=0 then raise sqlstate 'PT429' using message='Limite diário de consultas individuais atingido para este tipo. Renova à meia-noite no horário de Brasília.';end if;
  end if;
 else raise insufficient_privilege;end if;
end $$;
revoke all on function apoiarcred_private.check_partner_access(uuid,text,text,boolean) from public,anon,authenticated,service_role;
create function apoiarcred_private.guard_partner_lot() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if new.user_id<>old.user_id or new.servico<>old.servico or new.tipo<>old.tipo then raise insufficient_privilege;end if;
  if not (old.paused and not new.paused) then return new;end if;
 end if;
 perform apoiarcred_private.check_partner_access(new.user_id,new.servico,new.tipo,false);return new;end $$;
revoke all on function apoiarcred_private.guard_partner_lot() from public,anon,authenticated,service_role;
create trigger guard_partner_lot before insert or update on public.consulta_lotes for each row execute function apoiarcred_private.guard_partner_lot();
create trigger guard_partner_lot before insert or update on public.tjba_lotes for each row execute function apoiarcred_private.guard_partner_lot();
create function apoiarcred_private.guard_partner_job() returns trigger language plpgsql security definer set search_path='' as $$
declare lot record;
begin
 if tg_op='UPDATE' then
  if new.user_id<>old.user_id or new.lote_id<>old.lote_id or new.servico<>old.servico then raise insufficient_privilege;end if;
  if not (new.status='aguardando' and old.status in ('erro','revisao')) then return new;end if;
 end if;
 if tg_table_name='consulta_jobs' then select user_id,tipo,servico into lot from public.consulta_lotes where id=new.lote_id for share;
 else select user_id,tipo,servico into lot from public.tjba_lotes where id=new.lote_id for share;end if;
 if not found or lot.user_id<>new.user_id or lot.servico<>new.servico then raise insufficient_privilege;end if;
 perform apoiarcred_private.check_partner_access(new.user_id,lot.servico,lot.tipo,true);return new;
end $$;
revoke all on function apoiarcred_private.guard_partner_job() from public,anon,authenticated,service_role;
create trigger guard_partner_job before insert or update on public.consulta_jobs for each row execute function apoiarcred_private.guard_partner_job();
create trigger guard_partner_job before insert or update on public.tjba_jobs for each row execute function apoiarcred_private.guard_partner_job();

create function public.create_individual_consulta(p_item jsonb,p_servico text default 'digimais_saldo_parcela',p_convenio text default 'tjba') returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;jid uuid;begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 if p_servico='tjba_margem' then
  insert into public.tjba_lotes(nome,tipo,convenio) values('Consulta individual','individual',p_convenio) returning id into cid;
  insert into public.tjba_jobs(user_id,lote_id,nome,cpf,telefone) values(auth.uid(),cid,coalesce(nullif(btrim(p_item->>'nome'),''),'CPF '||(p_item->>'cpf')),p_item->>'cpf',coalesce(p_item->>'telefone','')) returning id into jid;
 elsif p_servico='digimais_saldo_parcela' then
  insert into public.consulta_lotes(nome,tipo) values('Consulta individual','individual') returning id into cid;
  insert into public.consulta_jobs(user_id,lote_id,nome,cpf,telefone) values(auth.uid(),cid,p_item->>'nome',p_item->>'cpf',p_item->>'telefone') returning id into jid;
 else raise exception 'Serviço inválido.';end if;return jid;
end $$;
revoke all on function public.create_individual_consulta(jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function public.create_individual_consulta(jsonb,text,text) to authenticated;

create function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg((to_jsonb(p)-'created_by')||jsonb_build_object('access',apoiarcred_private.access_for(p.user_id)) order by p.created_at desc),'[]') into result from apoiarcred_private.user_profiles p where role='partner';return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null then raise insufficient_privilege;end if;
 if p_action='create' and exists(select 1 from apoiarcred_private.user_profiles where user_id=uid) then raise exception 'Perfil já existe.';end if;
 if p_action='update' and not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='partner') then raise insufficient_privilege;end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' not in ('digimais_saldo_parcela','tjba_margem') or item->>'service' is null or (item->>'daily_limit')::int not between 0 and 100000 then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;
revoke all on function public.admin_partner_manage(uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_partner_manage(uuid,text,jsonb) to service_role;
-- API translates permission/quota errors while preserving request idempotency.
create or replace function public.api_execute(p_hash text,p_method text,p_route text,p_payload jsonb default '{}',p_key text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t apoiarcred_private.api_tokens;scope text;fingerprint text;cached apoiarcred_private.api_idempotency;result jsonb;
begin
 select * into t from apoiarcred_private.api_tokens where token_hash=p_hash for update;
 if not found or t.revoked_at is not null or (t.expires_at is not null and t.expires_at<=now()) then return apoiarcred_private.api_error(401,'invalid_token','Token inválido, expirado ou revogado.');end if;
 scope=case when p_method='GET' or p_route='/leads/buscar' then 'read' when p_route='/consultas' then 'consultas:create' else 'campanhas:write' end;
 if not scope=any(t.scopes) then return apoiarcred_private.api_error(403,'insufficient_scope','O token não possui esta permissão.');end if;
 if t.rate_window is null or t.rate_window<now()-interval '1 minute' then t.rate_count=0;t.rate_window=now();end if;
 if t.rate_count>=120 then return apoiarcred_private.api_error(429,'rate_limit','Limite de 120 requisições por minuto.');end if;
 update apoiarcred_private.api_tokens set rate_count=t.rate_count+1,rate_window=t.rate_window,last_used_at=now() where id=t.id;
 if p_method not in ('GET','POST') or jsonb_typeof(p_payload) is distinct from 'object' then return apoiarcred_private.api_error(400,'invalid_request','Requisição inválida.');end if;
 if p_method='POST' and p_route<>'/leads/buscar' and (p_key is null or length(p_key) not between 1 and 128) then return apoiarcred_private.api_error(400,'idempotency_required','Envie Idempotency-Key de 1 a 128 caracteres.');end if;
 delete from apoiarcred_private.api_idempotency where token_id=t.id and created_at<now()-interval '24 hours';
 if p_method='POST' and p_route<>'/leads/buscar' then
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
revoke all on function public.api_execute(text,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.api_execute(text,text,text,jsonb,text) to service_role;
notify pgrst,'reload schema';
