-- Apply after tenant_foundation.sql as part of the coordinated tenant cutover.
create or replace function apoiarcred_private.check_partner_access(
 uid uuid, service_id text, mode text, consume boolean default false
) returns void language plpgsql security definer set search_path='' as $$
begin
 if consume then
  perform apoiarcred_private.tenant_consume(uid,service_id,mode,1);
 elsif not apoiarcred_private.tenant_can_service(uid,service_id,mode) then
  raise insufficient_privilege using message='Serviço não autorizado para este usuário e empresa.';
 end if;
end $$;

create or replace function public.authorize_amigoz(p_actor uuid,p_consume boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not apoiarcred_private.tenant_can_service(p_actor,'amigoz','individual') then
  raise insufficient_privilege using message='Amigoz não autorizado para este usuário e empresa.';
 end if;
 if p_consume then
  perform apoiarcred_private.tenant_consume(p_actor,'amigoz','individual',1);
 end if;
 return true;
end $$;
revoke all on function public.authorize_amigoz(uuid,boolean) from public,anon,authenticated;
grant execute on function public.authorize_amigoz(uuid,boolean) to service_role;

CREATE OR REPLACE FUNCTION public.claim_consulta_job()
 RETURNS SETOF consulta_jobs
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare selected_lot uuid;
begin
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and apoiarcred_private.tenant_can_service(j.user_id,'digimais_saldo_parcela',l.tipo) and j.status in ('aguardando','processando') and j.execution_mode='robot')
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and apoiarcred_private.tenant_can_service(j.user_id,'digimais_saldo_parcela',(select l.tipo from public.consulta_lotes l where l.id=selected_lot)) and j.status='aguardando' and j.execution_mode='robot' order by j.queue_order for update skip locked limit 1) returning *;
end $function$;

CREATE OR REPLACE FUNCTION public.claim_consulta_job_for_robot(p_slot integer)
 RETURNS SETOF consulta_jobs
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare selected_lot uuid;
begin
 if p_slot is null or p_slot not between 1 and 4 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and apoiarcred_private.tenant_can_service(j.user_id,'digimais_saldo_parcela',l.tipo) and j.status in ('aguardando','processando') and j.execution_mode='robot')
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and apoiarcred_private.tenant_can_service(j.user_id,'digimais_saldo_parcela',(select l.tipo from public.consulta_lotes l where l.id=selected_lot)) and j.status='aguardando' and j.execution_mode='robot' order by j.queue_order for update skip locked limit 1) returning *;
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
 and apoiarcred_private.tenant_can_service(j.user_id,'digimais_saldo_parcela',l.tipo)
 and apoiarcred_private.can_use_digimais_api(j.user_id)
 and (select count(*) from public.consulta_jobs r where r.user_id=j.user_id and r.execution_mode='api' and r.status='processando')<p.max_concurrency
 order by j.queue_order for update of j skip locked for share of l skip locked limit 1) returning *;
end $function$;

CREATE OR REPLACE FUNCTION apoiarcred_private.claim_consigx_for_robot(p_slot integer)
 RETURNS SETOF tjba_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare selected_lot uuid;
begin
 if p_slot is not null and p_slot not between 1 and 4 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 -- Serialize reservations, while actual portal work runs in parallel across logins.
 if not pg_try_advisory_xact_lock(763211,1) then return;end if;
 select l.id into selected_lot
 from public.tjba_lotes l
 join lateral apoiarcred_private.tjba_robot_login(l.user_id,p_slot) login on login.enabled
 where not l.paused
 and exists(select 1 from public.tjba_jobs j where j.lote_id=l.id and apoiarcred_private.tenant_can_service(j.user_id,'tjba_margem',l.tipo) and j.status='aguardando')
 and not exists(
  select 1 from public.tjba_jobs running
  left join lateral apoiarcred_private.tjba_robot_login(running.user_id,running.robot_slot) other on true
  where running.status='processando'
  and (lower(btrim(other.username))=lower(btrim(login.username))
       or (running.user_id=l.user_id and (login.username is null or other.username is null)))
 )
 order by l.created_at,l.id limit 1 for share of l;
 if selected_lot is null then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.tjba_jobs j where j.lote_id=selected_lot and apoiarcred_private.tenant_can_service(j.user_id,'tjba_margem',(select l.tipo from public.tjba_lotes l where l.id=selected_lot)) and j.status='aguardando' order by j.queue_order for update skip locked limit 1)
 returning *;
end $function$;

CREATE OR REPLACE FUNCTION apoiarcred_private.claim_consigx_parallel()
 RETURNS SETOF tjba_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare selected_lot uuid;
begin
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;

 -- Serialize the short reservation transaction so workers cannot claim the same login concurrently.
 if not pg_try_advisory_xact_lock(763211,1) then return;end if;
 select l.id into selected_lot
 from public.tjba_lotes l
 left join apoiarcred_private.tjba_credentials cred on cred.user_id=l.user_id
 where not l.paused
 and exists(select 1 from public.tjba_jobs j where j.lote_id=l.id and apoiarcred_private.tenant_can_service(j.user_id,'tjba_margem',l.tipo) and j.status='aguardando')
 and not exists(
  select 1 from public.tjba_jobs running
  left join apoiarcred_private.tjba_credentials other on other.user_id=running.user_id
  where running.status='processando'
  and (running.user_id=l.user_id or lower(btrim(other.username))=lower(btrim(cred.username)))
 )
 order by l.created_at,l.id limit 1 for share of l;

 if selected_lot is null then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1
 where id=(select j.id from public.tjba_jobs j where j.lote_id=selected_lot and apoiarcred_private.tenant_can_service(j.user_id,'tjba_margem',(select l.tipo from public.tjba_lotes l where l.id=selected_lot)) and j.status='aguardando' order by j.queue_order for update skip locked limit 1)
 returning *;
end $function$;
