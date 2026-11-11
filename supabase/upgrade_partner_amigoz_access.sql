-- Individual Amigoz access is opt-in for each partner.
alter table apoiarcred_private.user_profiles add column if not exists allow_amigoz boolean not null default false;

create or replace function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'allow_amigoz',coalesce(p.active and (p.role='admin' or p.allow_amigoz),false),
 'allow_integrations',coalesce(p.active and (p.role='admin' or p.allow_integrations),false),
 'trial_until',p.trial_until,
 'trial_expired',coalesce(p.trial_until<(now() at time zone 'America/Sao_Paulo')::date,false),
 'trial_days_left',case when p.trial_until is not null then greatest(0,p.trial_until-(now() at time zone 'America/Sao_Paulo')::date+1) end,
 'shared_quota',coalesce(p.shared_quota,false),'daily_limit',p.shared_daily_limit,
 'remaining',case when p.shared_daily_limit is not null then greatest(0,p.shared_daily_limit-coalesce(shared.used,0)) end,
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid
 left join apoiarcred_private.partner_daily_usage shared on shared.user_id=uid and shared.service='shared'
  and shared.day=(now() at time zone 'America/Sao_Paulo')::date;
$$;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;quota integer;trial date;
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
 if p_input ? 'allow_integrations' and jsonb_typeof(p_input->'allow_integrations') is distinct from 'boolean' then raise exception 'Permissão de integrações inválida.';end if;
 if p_input ? 'allow_amigoz' and jsonb_typeof(p_input->'allow_amigoz') is distinct from 'boolean' then raise exception 'Permissão Amigoz inválida.';end if;
 if (p_input->>'allow_amigoz')::boolean and not (p_input ? 'shared_daily_limit' or exists(
  select 1 from apoiarcred_private.user_profiles where user_id=uid and shared_quota
 )) then raise exception 'Configure a cota compartilhada para liberar Amigoz.';end if;
 if p_input ? 'shared_daily_limit' then
  if jsonb_typeof(p_input->'shared_daily_limit') not in ('number','null') then raise exception 'Cota diária inválida.';end if;
  quota=(p_input->>'shared_daily_limit')::integer;
  if quota not between 1 and 100000 then raise exception 'Cota diária inválida.';end if;
 end if;
 if p_input ? 'trial_until' then trial=(p_input->>'trial_until')::date;end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,allow_integrations,allow_amigoz,shared_quota,shared_daily_limit,trial_until,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),coalesce((p_input->>'allow_integrations')::boolean,false),coalesce((p_input->>'allow_amigoz')::boolean,false),p_input ? 'shared_daily_limit',quota,trial,p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),allow_integrations=coalesce((p_input->>'allow_integrations')::boolean,allow_integrations),shared_quota=shared_quota or p_input ? 'shared_daily_limit',
   allow_amigoz=coalesce((p_input->>'allow_amigoz')::boolean,allow_amigoz),
   shared_daily_limit=case when p_input ? 'shared_daily_limit' then quota else shared_daily_limit end,
   trial_until=case when p_input ? 'trial_until' then trial else trial_until end,
   updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;

create or replace function public.authorize_amigoz(p_actor uuid,p_consume boolean)
returns boolean language plpgsql security invoker set search_path='' as $$
declare profile apoiarcred_private.user_profiles; today date=(now() at time zone 'America/Sao_Paulo')::date;
begin
 select * into profile from apoiarcred_private.user_profiles where user_id=p_actor for share;
 if not found or not profile.active then
  raise insufficient_privilege using message='Conta sem acesso ativo.';
 end if;
 if profile.role='admin' then return true;end if;
 if not profile.allow_amigoz or not profile.shared_quota then
  raise insufficient_privilege using message='Acesso Amigoz não liberado.';
 end if;
 if profile.trial_until<today then
  raise insufficient_privilege using message='Seu período de teste terminou.';
 end if;
 if p_consume then
  insert into apoiarcred_private.partner_daily_usage as quota(user_id,service,day,used)
   values(p_actor,'shared',today,1)
   on conflict(user_id,service,day) do update set used=quota.used+1
   where profile.shared_daily_limit is null or quota.used<profile.shared_daily_limit;
  if not found then raise sqlstate 'PT429' using message='Limite diário de consultas atingido.';end if;
 end if;
 return true;
end $$;
revoke all on function public.authorize_amigoz(uuid,boolean) from public,anon,authenticated;
grant execute on function public.authorize_amigoz(uuid,boolean) to service_role;
