-- One CPF per campaign/lot, including direct insert paths. Existing jobs are retained.
create unique index consulta_jobs_lote_cpf_unique on public.consulta_jobs(lote_id,cpf);

create table apoiarcred_private.queue_maintenance(id boolean primary key default true check(id),token uuid,paused_until timestamptz);
insert into apoiarcred_private.queue_maintenance(id) values(true);
alter table apoiarcred_private.queue_maintenance enable row level security;
revoke all on apoiarcred_private.queue_maintenance from public,anon,authenticated;
grant usage on schema apoiarcred_private to service_role;
grant select,update on apoiarcred_private.queue_maintenance to service_role;
create policy queue_maintenance_service on apoiarcred_private.queue_maintenance for all to service_role using(true) with check(true);
create function public.consulta_queue_maintenance(p_token uuid,p_release boolean default false) returns integer language plpgsql security invoker set search_path='' as $$
declare current_token uuid; until_time timestamptz; active integer;
begin
 select token,paused_until into current_token,until_time from apoiarcred_private.queue_maintenance where id for update;
 if current_token is not null and until_time>clock_timestamp() and current_token<>p_token then raise exception 'Outra manutenção da fila está ativa.';end if;
 if p_release then
  update apoiarcred_private.queue_maintenance set token=null,paused_until=null where id and token=p_token;return 0;
 end if;
 if p_token is null then raise exception 'Token de manutenção obrigatório.';end if;
 update apoiarcred_private.queue_maintenance set token=p_token,paused_until=clock_timestamp()+interval '30 minutes' where id;
 select (select count(*) from public.consulta_jobs where status='processando')+(select count(*) from public.tjba_jobs where status='processando') into active;
 return active;
end $$;
revoke all on function public.consulta_queue_maintenance(uuid,boolean) from public,anon,authenticated;
grant execute on function public.consulta_queue_maintenance(uuid,boolean) to service_role;
create or replace function public.claim_consulta_job() returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp() for share;
 if found then return;end if;
 -- Always hold the guard through reservation, even while unpaused.
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1 where id=(select id from public.consulta_jobs where status='aguardando' and servico='digimais_saldo_parcela' order by created_at,id for update skip locked limit 1) returning *;
end $$;
create or replace function public.claim_tjba_job() returns setof public.tjba_jobs language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1 where id=(select id from public.tjba_jobs where status='aguardando' order by created_at,id for update skip locked limit 1) returning *;
end $$;
