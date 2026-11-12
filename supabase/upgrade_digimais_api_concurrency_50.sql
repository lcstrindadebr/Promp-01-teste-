begin;
set local lock_timeout = '5s';

alter table apoiarcred_private.digimais_preferences
 drop constraint digimais_preferences_max_concurrency_check,
 add constraint digimais_preferences_max_concurrency_check check (max_concurrency between 1 and 50);

alter table public.consulta_jobs
 drop constraint consulta_jobs_api_slot_check,
 add constraint consulta_jobs_api_slot_check check (api_slot between 1 and 50);

CREATE OR REPLACE FUNCTION apoiarcred_private.manage_digimais_pilot(p_mode text, p_paused boolean, p_max integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); result jsonb;
begin
 if not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_mode is not null then
  if p_mode not in ('robot','api') or p_paused is null or p_max is null or p_max not between 1 and 50 then raise exception 'Configuração inválida';end if;
  if p_mode='api' and not exists(select 1 from apoiarcred_private.digimais_api_config) then raise exception 'API ainda não configurada na VPS/banco';end if;
  insert into apoiarcred_private.digimais_preferences(user_id,mode,paused,max_concurrency) values(uid,p_mode,p_paused,p_max)
  on conflict(user_id) do update set mode=excluded.mode,paused=excluded.paused,max_concurrency=excluded.max_concurrency;
  -- Switch only waiting campaign jobs owned by this administrator.
  update public.consulta_jobs j
  set execution_mode=p_mode, api_slot=null, robot_slot=null
  from public.consulta_lotes l
  where j.lote_id=l.id and l.tipo='campanha'
    and j.user_id=uid and l.user_id=uid
    and j.status='aguardando' and j.execution_mode<>p_mode and j.api_handoff is null;
 end if;
 select jsonb_build_object('mode',mode,'paused',paused,'max_concurrency',max_concurrency) into result from apoiarcred_private.digimais_preferences where user_id=uid;
 return coalesce(result,'{"mode":"robot","paused":false,"max_concurrency":12}'::jsonb);
end $function$;

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
 and apoiarcred_private.is_admin(j.user_id)
 and (select count(*) from public.consulta_jobs r where r.user_id=j.user_id and r.execution_mode='api' and r.status='processando')<p.max_concurrency
 order by j.queue_order for update of j skip locked for share of l skip locked limit 1) returning *;
end $function$;

notify pgrst, 'reload schema';
commit;
