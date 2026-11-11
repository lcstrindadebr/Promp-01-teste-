-- Private optional credentials per administrator and robot.
create table if not exists apoiarcred_private.tjba_robot_credentials (
 user_id uuid not null references auth.users(id) on delete cascade,
 slot integer not null check(slot between 1 and 3),
 username text not null,
 secret_id uuid not null,
 enabled boolean not null default true,
 updated_at timestamptz not null default now(),
 primary key(user_id,slot)
);
alter table apoiarcred_private.tjba_robot_credentials enable row level security;
revoke all on apoiarcred_private.tjba_robot_credentials from public,anon,authenticated,service_role;
alter table public.tjba_jobs add column if not exists robot_slot integer check(robot_slot between 1 and 3);
create index if not exists tjba_jobs_running_owner on public.tjba_jobs(user_id) where status='processando';

create or replace function apoiarcred_private.tjba_robot_login(p_uid uuid,p_slot integer)
returns table(username text,secret_id uuid,enabled boolean,updated_at timestamptz)
language sql stable set search_path='' as $$
 select x.username,x.secret_id,x.enabled,x.updated_at
 from (
  select r.username,r.secret_id,r.enabled,r.updated_at,0 priority
  from apoiarcred_private.tjba_robot_credentials r
  where r.user_id=p_uid and r.slot=p_slot and r.enabled and apoiarcred_private.is_admin(p_uid)
  union all
  select c.username,c.secret_id,c.enabled,c.updated_at,1
  from apoiarcred_private.tjba_credentials c where c.user_id=p_uid
 ) x order by x.priority limit 1;
$$;
revoke all on function apoiarcred_private.tjba_robot_login(uuid,integer) from public,anon,authenticated,service_role;

create or replace function apoiarcred_private.manage_tjba_robot_credentials(
 p_slot integer default null,p_username text default null,p_password text default null,p_enabled boolean default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); previous apoiarcred_private.tjba_robot_credentials;
begin
 if not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_slot is not null then
  if p_slot not between 1 and 3 or p_enabled is null or coalesce(length(btrim(p_username)),0) not between 1 and 160 or length(coalesce(p_password,''))>512 then
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
revoke all on function apoiarcred_private.manage_tjba_robot_credentials(integer,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.manage_tjba_robot_credentials(integer,text,text,boolean) to authenticated;
create or replace function public.manage_tjba_robot_credentials(
 p_slot integer default null,p_username text default null,p_password text default null,p_enabled boolean default null
) returns jsonb language sql security invoker set search_path='' as $$
 select apoiarcred_private.manage_tjba_robot_credentials(p_slot,p_username,p_password,p_enabled);
$$;
revoke all on function public.manage_tjba_robot_credentials(integer,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.manage_tjba_robot_credentials(integer,text,text,boolean) to authenticated;

create or replace function apoiarcred_private.get_tjba_robot_credentials(p_user_id uuid,p_slot integer)
returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('username',c.username,'password',v.decrypted_secret,'enabled',c.enabled,'revision',c.updated_at)
 from apoiarcred_private.tjba_robot_login(p_user_id,p_slot) c join vault.decrypted_secrets v on v.id=c.secret_id;
$$;
revoke all on function apoiarcred_private.get_tjba_robot_credentials(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.get_tjba_robot_credentials(uuid,integer) to service_role;
create or replace function public.get_tjba_robot_credentials(p_user_id uuid,p_slot integer)
returns jsonb language sql security invoker set search_path='' as $$
 select apoiarcred_private.get_tjba_robot_credentials(p_user_id,p_slot);
$$;
revoke all on function public.get_tjba_robot_credentials(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.get_tjba_robot_credentials(uuid,integer) to service_role;

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
 left join lateral apoiarcred_private.tjba_robot_login(l.user_id,p_slot) login on true
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
revoke all on function apoiarcred_private.claim_consigx_for_robot(integer) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.claim_consigx_for_robot(integer) to service_role;

create or replace function public.claim_tjba_job_for_robot(p_slot integer) returns setof public.tjba_jobs
language sql security invoker set search_path='' as $$
 select * from apoiarcred_private.claim_consigx_for_robot(p_slot);
$$;
revoke all on function public.claim_tjba_job_for_robot(integer) from public,anon,authenticated,service_role;
grant execute on function public.claim_tjba_job_for_robot(integer) to service_role;

create or replace function public.claim_tjba_job() returns setof public.tjba_jobs
language sql security invoker set search_path='' as $$
 select * from apoiarcred_private.claim_consigx_for_robot(null);
$$;
notify pgrst,'reload schema';
