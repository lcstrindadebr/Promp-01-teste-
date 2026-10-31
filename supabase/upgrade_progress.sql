alter table public.consulta_jobs add column if not exists progress integer not null default 0 check(progress between 0 and 100);
alter table public.consulta_jobs add column if not exists stage text not null default 'Aguardando na fila';
alter table public.consulta_jobs drop constraint consulta_jobs_status_check;
alter table public.consulta_jobs add constraint consulta_jobs_status_check check(status in ('aguardando','processando','concluida','nao_localizado','nao_cliente','erro','revisao'));
