alter table public.consulta_jobs
 drop constraint if exists consulta_jobs_status_check,
 add constraint consulta_jobs_status_check
 check(status in ('aguardando','processando','concluida','nao_localizado','nao_cliente','erro','revisao','interrompida','ja_vendeu'));
