-- Accept a fourth robot while preserving existing reservations and credentials.
alter table apoiarcred_private.tjba_robot_credentials
 drop constraint tjba_robot_credentials_slot_check,
 add constraint tjba_robot_credentials_slot_check check(slot between 1 and 4);
alter table public.tjba_jobs
 drop constraint tjba_jobs_robot_slot_check,
 add constraint tjba_jobs_robot_slot_check check(robot_slot between 1 and 4);
alter table public.consulta_jobs
 drop constraint consulta_jobs_robot_slot_check,
 add constraint consulta_jobs_robot_slot_check check(robot_slot between 1 and 4);

create or replace function apoiarcred_private.manage_tjba_robot_credentials(
 p_slot integer default null,p_username text default null,p_password text default null,p_enabled boolean default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); previous apoiarcred_private.tjba_robot_credentials;
begin
 if not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_slot is not null then
  if p_slot not between 1 and 4 or p_enabled is null or coalesce(length(btrim(p_username)),0) not between 1 and 160 or length(coalesce(p_password,''))>512 then
   raise exception 'Informe um robô, usuário e senha válidos.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text||':tjba-robot:'||p_slot,0));
  select * into previous from apoiarcred_private.tjba_robot_credentials where user_id=uid and slot=p_slot;
  if coalesce(p_password,'')='' and (previous.secret_id is null or previous.username<>btrim(p_username)) then
   raise exception 'Informe a senha para esse usuário.';
  end if;
  if previous.secret_id is null then
   previous.secret_id=vault.create_secret(p_password,'apoiarcred-tjba-robot-'||uid||'-'||p_slot);
  elsif coalesce(p_password,'')<>'' then
   perform vault.update_secret(previous.secret_id,p_password);
  end if;
  insert into apoiarcred_private.tjba_robot_credentials(user_id,slot,username,secret_id,enabled,updated_at)
  values(uid,p_slot,btrim(p_username),previous.secret_id,p_enabled,clock_timestamp())
  on conflict(user_id,slot) do update set username=excluded.username,enabled=excluded.enabled,updated_at=excluded.updated_at;
 end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('slot',r.slot,'username',r.username,'enabled',r.enabled) order by r.slot),'[]')
         from apoiarcred_private.tjba_robot_credentials r where r.user_id=uid);
end $$;

create or replace function public.manage_consigx_access(
 p_slot integer default null,
 p_username text default null,
 p_password text default null,
 p_enabled boolean default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 admin boolean;
 robot_access jsonb := '[]'::jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 admin := public.am_i_admin();
 if p_slot is not null then
  if p_slot not between 0 and 4 or p_enabled is null then
   raise exception 'Selecione um acesso válido.';
  end if;
  if p_slot=0 then
   perform public.save_tjba_credentials(p_username,p_password,p_enabled);
  else
   if not admin then raise insufficient_privilege;end if;
   robot_access := public.manage_tjba_robot_credentials(p_slot,p_username,p_password,p_enabled);
  end if;
 end if;
 if admin and (p_slot is null or p_slot=0) then
  robot_access := public.manage_tjba_robot_credentials();
 end if;
 return jsonb_build_object('shared',public.tjba_credentials_status(),'robots',robot_access);
end $$;

create or replace function apoiarcred_private.claim_consigx_for_robot(p_slot integer)
returns setof public.tjba_jobs language plpgsql security definer set search_path='' as $$
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

create or replace function public.claim_consulta_job_for_robot(p_slot integer) returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is null or p_slot not between 1 and 4 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando'))
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1) returning *;
end $$;
notify pgrst,'reload schema';
