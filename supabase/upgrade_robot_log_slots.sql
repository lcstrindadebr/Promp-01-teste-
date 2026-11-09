-- Attribute Digi+ reservations to a robot, as already done for ConsigX.
alter table public.consulta_jobs add column if not exists robot_slot integer check(robot_slot between 1 and 3);

create or replace function public.claim_consulta_job_for_robot(p_slot integer) returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is null or p_slot not between 1 and 3 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando'))
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1) returning *;
end $$;
revoke all on function public.claim_consulta_job_for_robot(integer) from public,anon,authenticated,service_role;
grant execute on function public.claim_consulta_job_for_robot(integer) to service_role;
notify pgrst,'reload schema';
