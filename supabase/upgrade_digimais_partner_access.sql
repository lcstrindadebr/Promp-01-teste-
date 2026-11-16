alter table apoiarcred_private.digimais_preferences add column if not exists api_enabled boolean not null default false;

create or replace function apoiarcred_private.can_use_digimais_api(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select apoiarcred_private.is_admin(p_user) or exists(
 select 1 from apoiarcred_private.user_profiles u
 join apoiarcred_private.digimais_preferences d on d.user_id=u.user_id
 join apoiarcred_private.partner_permissions p on p.user_id=u.user_id and p.service='digimais_saldo_parcela'
 where u.user_id=p_user and u.active and d.api_enabled and p.enabled
 and (u.trial_until is null or u.trial_until >= (now() at time zone 'America/Sao_Paulo')::date));
$$;
revoke all on function apoiarcred_private.can_use_digimais_api(uuid) from public,anon,authenticated;
grant execute on function apoiarcred_private.can_use_digimais_api(uuid) to service_role;

create or replace function apoiarcred_private.assign_digimais_execution()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.execution_mode='robot';new.api_slot=null;
 if apoiarcred_private.can_use_digimais_api(new.user_id) then
  select coalesce((select mode from apoiarcred_private.digimais_preferences where user_id=new.user_id),'robot') into new.execution_mode;
 end if;
 return new;
end $$;

CREATE OR REPLACE FUNCTION public.claim_consulta_job_for_api(p_slot integer)
 RETURNS SETOF consulta_jobs
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if p_slot is null or p_slot not between 1 and 50 then raise exception 'Executor API inválido';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 if not pg_try_advisory_xact_lock(763212,1) then return;end if;
 if exists(select 1 from public.consulta_jobs where execution_mode='api' and status='processando' and api_slot=p_slot) then return;end if;
 if (select count(*) from public.consulta_jobs where execution_mode='api' and status='processando')>=50 then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,api_slot=p_slot,robot_slot=null
 where id=(select j.id from public.consulta_jobs j join public.consulta_lotes l on l.id=j.lote_id
 join apoiarcred_private.digimais_preferences p on p.user_id=j.user_id
 where j.execution_mode='api' and j.status='aguardando' and not l.paused and not p.paused
 and apoiarcred_private.can_use_digimais_api(j.user_id)
 and (select count(*) from public.consulta_jobs r where r.user_id=j.user_id and r.execution_mode='api' and r.status='processando')<p.max_concurrency
 order by j.queue_order for update of j skip locked for share of l skip locked limit 1) returning *;
end $function$;

create or replace function apoiarcred_private.admin_digimais_access(p_user uuid,p_enabled boolean,p_max integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not apoiarcred_private.is_admin(auth.uid()) then raise insufficient_privilege;end if;
 if p_user is not null then
  if p_enabled is null or p_max is null or p_max not between 1 and 50 then raise exception 'Informe um limite entre 1 e 50';end if;
  perform pg_advisory_xact_lock(763212,1);
  perform 1 from apoiarcred_private.user_profiles where user_id=p_user and role='partner' for update;
  if not found then raise exception 'Parceiro não encontrado';end if;
  if p_enabled and not exists(select 1 from apoiarcred_private.digimais_api_config) then raise exception 'Configure a API Digi+ antes de liberar';end if;
  if p_enabled and not exists(select 1 from apoiarcred_private.partner_permissions where user_id=p_user and service='digimais_saldo_parcela' and enabled) then raise exception 'Libere o serviço Digi+ para este parceiro primeiro';end if;
  insert into apoiarcred_private.digimais_preferences(user_id,mode,paused,max_concurrency,api_enabled)
  values(p_user,case when p_enabled then 'api' else 'robot' end,false,p_max,p_enabled)
  on conflict(user_id) do update set mode=excluded.mode,paused=false,max_concurrency=excluded.max_concurrency,api_enabled=excluded.api_enabled;
  update public.consulta_jobs set execution_mode=case when p_enabled then 'api' else 'robot' end,api_slot=null,robot_slot=null
  where user_id=p_user and status='aguardando' and api_handoff is null;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('user_id',u.user_id,'name',u.name,'email',u.email,'active',u.active,
 'enabled',coalesce(d.api_enabled,false),'max_concurrency',coalesce(d.max_concurrency,1)) order by u.name),'[]'::jsonb)
 into result from apoiarcred_private.user_profiles u left join apoiarcred_private.digimais_preferences d on d.user_id=u.user_id where u.role='partner';
 return result;
end $$;
revoke all on function apoiarcred_private.admin_digimais_access(uuid,boolean,integer) from public,anon;
grant execute on function apoiarcred_private.admin_digimais_access(uuid,boolean,integer) to authenticated;
create or replace function public.admin_digimais_access(p_user uuid default null,p_enabled boolean default null,p_max integer default null)
returns jsonb language sql security invoker set search_path='' as $$
 select apoiarcred_private.admin_digimais_access(p_user,p_enabled,p_max);
$$;
revoke all on function public.admin_digimais_access(uuid,boolean,integer) from public,anon;
grant execute on function public.admin_digimais_access(uuid,boolean,integer) to authenticated;
notify pgrst,'reload schema';
