set local lock_timeout='3s';
create index if not exists consulta_jobs_requeue_running_idx on public.consulta_jobs(id) where status='processando';
