create table public.consulta_lotes (
id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
nome text not null, created_at timestamptz not null default now());
create index consulta_lotes_owner on public.consulta_lotes(user_id,created_at desc);
create table public.consulta_jobs (
id uuid primary key default gen_random_uuid(), lote_id uuid not null references public.consulta_lotes(id) on delete cascade,
user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
nome text not null check(length(nome) between 1 and 160),
cpf text not null check(cpf ~ '^[0-9]{11}$'), telefone text not null check(telefone ~ '^[0-9]{10,13}$'),
status text not null default 'aguardando' check(status in ('aguardando','processando','concluida','nao_localizado','erro','revisao')),
saldo_liquidacao numeric(14,2), total_parcelas integer, message text,
created_at timestamptz not null default now(), consultado_em timestamptz,
locked_at timestamptz, attempts integer not null default 0);
create index consulta_jobs_owner on public.consulta_jobs(user_id,created_at desc);
create index consulta_jobs_lote on public.consulta_jobs(lote_id);
create index consulta_jobs_queue on public.consulta_jobs(created_at) where status='aguardando';
alter table public.consulta_lotes enable row level security;
alter table public.consulta_jobs enable row level security;
revoke all on public.consulta_lotes,public.consulta_jobs from anon,authenticated;
grant select,insert on public.consulta_lotes to authenticated;
grant select on public.consulta_jobs to authenticated;
grant insert (lote_id,user_id,nome,cpf,telefone) on public.consulta_jobs to authenticated;
grant all on public.consulta_lotes,public.consulta_jobs to service_role;
create policy lotes_read on public.consulta_lotes for select to authenticated using(user_id=(select auth.uid()));
create policy lotes_insert on public.consulta_lotes for insert to authenticated with check(user_id=(select auth.uid()));
create policy jobs_read on public.consulta_jobs for select to authenticated using(user_id=(select auth.uid()));
create policy jobs_insert on public.consulta_jobs for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.consulta_lotes l where l.id=lote_id and l.user_id=(select auth.uid())));
create function public.claim_consulta_job() returns setof public.consulta_jobs language sql security invoker set search_path='' as $$
update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1
where id=(select id from public.consulta_jobs where status='aguardando' order by created_at for update skip locked limit 1) returning *;
$$;
revoke all on function public.claim_consulta_job() from public,anon,authenticated;
grant execute on function public.claim_consulta_job() to service_role;
