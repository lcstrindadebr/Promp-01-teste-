-- Admin jobs require an enabled credential for the requesting robot.
-- Partner accounts have a single credential and can run on robot 1.
create or replace function apoiarcred_private.tjba_robot_login(p_uid uuid,p_slot integer)
returns table(username text,secret_id uuid,enabled boolean,updated_at timestamptz)
language sql stable set search_path='' as $$
 select r.username,r.secret_id,r.enabled,r.updated_at
 from apoiarcred_private.tjba_robot_credentials r
 join apoiarcred_private.user_profiles p on p.user_id=r.user_id
 where r.user_id=p_uid and r.slot=p_slot and r.enabled and p.role='admin' and p.active
 union all
 select c.username,c.secret_id,c.enabled,c.updated_at
 from apoiarcred_private.tjba_credentials c
 join apoiarcred_private.user_profiles p on p.user_id=c.user_id
 where c.user_id=p_uid and coalesce(p_slot,1)=1 and c.enabled and p.role='partner' and p.active;
$$;

create or replace function apoiarcred_private.claim_consigx_for_robot(p_slot integer)
returns setof public.tjba_jobs language plpgsql security definer set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is not null and p_slot not between 1 and 3 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 -- Serialize reservations, while actual portal work runs in parallel across logins.
 if not pg_try_advisory_xact_lock(763211,1) then return;end if;
 select l.id into selected_lot
 from public.tjba_lotes l
 join lateral apoiarcred_private.tjba_robot_login(l.user_id,p_slot) login on login.enabled
 where not l.paused
 and exists(select 1 from public.tjba_jobs j where j.lote_id=l.id and j.status='aguardando')
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
 where id=(select j.id from public.tjba_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1)
 returning *;
end $$;

notify pgrst,'reload schema';
