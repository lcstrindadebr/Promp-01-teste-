-- Admin-only, opt-in HTTP pilot. Existing jobs remain on robots.
create table apoiarcred_private.digimais_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 mode text not null default 'robot' check(mode in ('robot','api')),
 paused boolean not null default false,
 max_concurrency integer not null default 12 check(max_concurrency between 1 and 12)
);
alter table apoiarcred_private.digimais_preferences enable row level security;
revoke all on apoiarcred_private.digimais_preferences from public,anon,authenticated;
grant all on apoiarcred_private.digimais_preferences to service_role;
create table apoiarcred_private.digimais_api_config(id boolean primary key default true check(id),config jsonb not null);
alter table apoiarcred_private.digimais_api_config enable row level security;
revoke all on apoiarcred_private.digimais_api_config from public,anon,authenticated;
grant all on apoiarcred_private.digimais_api_config to service_role;
alter table public.consulta_jobs add column execution_mode text not null default 'robot' check(execution_mode in ('robot','api'));
alter table public.consulta_jobs add column api_slot integer check(api_slot between 1 and 12);
create index consulta_jobs_api_queue on public.consulta_jobs(execution_mode,queue_order) where status='aguardando';
create unique index consulta_jobs_api_running_slot on public.consulta_jobs(api_slot) where status='processando' and execution_mode='api';
create function apoiarcred_private.manage_digimais_pilot(p_mode text,p_paused boolean,p_max integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); result jsonb;
begin
 if not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_mode is not null then
  if p_mode not in ('robot','api') or p_paused is null or p_max is null or p_max not between 1 and 12 then raise exception 'Configuração inválida';end if;
  if p_mode='api' and not exists(select 1 from apoiarcred_private.digimais_api_config) then raise exception 'API ainda não configurada na VPS/banco';end if;
  insert into apoiarcred_private.digimais_preferences(user_id,mode,paused,max_concurrency) values(uid,p_mode,p_paused,p_max)
  on conflict(user_id) do update set mode=excluded.mode,paused=excluded.paused,max_concurrency=excluded.max_concurrency;
 end if;
 select jsonb_build_object('mode',mode,'paused',paused,'max_concurrency',max_concurrency) into result from apoiarcred_private.digimais_preferences where user_id=uid;
 return coalesce(result,'{"mode":"robot","paused":false,"max_concurrency":12}'::jsonb);
end $$;
revoke all on function apoiarcred_private.manage_digimais_pilot(text,boolean,integer) from public,anon,authenticated;
grant execute on function apoiarcred_private.manage_digimais_pilot(text,boolean,integer) to authenticated;
create function public.manage_digimais_pilot(p_mode text default null,p_paused boolean default null,p_max integer default null) returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.manage_digimais_pilot(p_mode,p_paused,p_max);$$;
revoke all on function public.manage_digimais_pilot(text,boolean,integer) from public,anon,authenticated;
grant execute on function public.manage_digimais_pilot(text,boolean,integer) to authenticated;
create function apoiarcred_private.assign_digimais_execution() returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.execution_mode='robot';new.api_slot=null;
 if apoiarcred_private.is_admin(new.user_id) then
  select coalesce((select mode from apoiarcred_private.digimais_preferences where user_id=new.user_id),'robot') into new.execution_mode;
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.assign_digimais_execution() from public,anon,authenticated;
create trigger assign_digimais_execution before insert on public.consulta_jobs for each row execute function apoiarcred_private.assign_digimais_execution();
create function public.get_digimais_api_config() returns jsonb language sql security invoker set search_path='' as $$select config from apoiarcred_private.digimais_api_config where id;$$;
revoke all on function public.get_digimais_api_config() from public,anon,authenticated;
grant execute on function public.get_digimais_api_config() to service_role;
create function public.claim_consulta_job_for_api(p_slot integer) returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
begin
 if p_slot is null or p_slot not between 1 and 12 then raise exception 'Executor API inválido';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 if not pg_try_advisory_xact_lock(763212,1) then return;end if;
 if exists(select 1 from public.consulta_jobs where execution_mode='api' and status='processando' and api_slot=p_slot) then return;end if;
 if (select count(*) from public.consulta_jobs where execution_mode='api' and status='processando')>=12 then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,api_slot=p_slot,robot_slot=null
 where id=(select j.id from public.consulta_jobs j join public.consulta_lotes l on l.id=j.lote_id
 join apoiarcred_private.digimais_preferences p on p.user_id=j.user_id
 where j.execution_mode='api' and j.status='aguardando' and not l.paused and not p.paused
 and apoiarcred_private.is_admin(j.user_id)
 and (select count(*) from public.consulta_jobs r where r.user_id=j.user_id and r.execution_mode='api' and r.status='processando')<p.max_concurrency
 order by j.queue_order for update of j skip locked limit 1) returning *;
end $$;
revoke all on function public.claim_consulta_job_for_api(integer) from public,anon,authenticated;
grant execute on function public.claim_consulta_job_for_api(integer) to service_role;

create or replace function public.claim_consulta_job_for_robot(p_slot integer) returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is null or p_slot not between 1 and 4 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando') and j.execution_mode='robot')
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and j.status='aguardando' and j.execution_mode='robot' order by j.queue_order for update skip locked limit 1) returning *;
end $$;

create or replace function public.claim_consulta_job() returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando') and j.execution_mode='robot')
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and j.status='aguardando' and j.execution_mode='robot' order by j.queue_order for update skip locked limit 1) returning *;
end $$;
notify pgrst,'reload schema';
