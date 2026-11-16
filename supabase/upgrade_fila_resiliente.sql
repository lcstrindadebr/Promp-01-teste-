-- Fila resiliente (Fase 1).
-- 1. Consultas presas em "processando" voltam sozinhas para a fila depois de um prazo,
--    em vez de bloquear a vaga para sempre quando o worker cai ou é reiniciado.
--    Depois de 3 tentativas interrompidas a consulta vai para revisão, sem novo envio.
-- 2. Reserva em lote para a API Digi+: uma chamada reserva até uma consulta por vaga livre,
--    reaproveitando as regras de claim_consulta_job_for_api (cota, pausa, concorrência).
-- Aplicar depois de upgrade_painel_sync_pro.sql. Não altera tabelas nem funções existentes.

create or replace function apoiarcred_private.release_stale_jobs(p_older interval)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 cutoff timestamptz:=now()-greatest(p_older,interval '0 seconds');
 note text:='Interrompida sem resultado; devolvida automaticamente à fila.';
 stop_note text:='Interrompida 3 vezes sem resultado. Confira antes de tentar novamente.';
 digi_requeued integer; digi_review integer; tjba_requeued integer; tjba_review integer;
begin
 update public.consulta_jobs set status='revisao',stage='Consulta interrompida várias vezes',message=stop_note,
  locked_at=null,robot_slot=null,api_slot=null
 where status='processando' and (locked_at is null or locked_at<=cutoff) and attempts>=3;
 get diagnostics digi_review=row_count;

 update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=note,
  locked_at=null,consultado_em=null,robot_slot=null,api_slot=null,saldo_liquidacao=null,total_parcelas=null,
  valor_parcela=null,resultado_saldo=null,resultado_parcela=null
 where status='processando' and (locked_at is null or locked_at<=cutoff) and attempts<3;
 get diagnostics digi_requeued=row_count;

 update public.tjba_jobs set status='revisao',stage='Consulta interrompida várias vezes',message=stop_note,
  locked_at=null,robot_slot=null
 where status='processando' and (locked_at is null or locked_at<=cutoff) and attempts>=3;
 get diagnostics tjba_review=row_count;

 update public.tjba_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=note,
  locked_at=null,consultado_em=null,robot_slot=null,matricula=null,tipo_servidor=null,situacao_atual=null,
  emprestimo_disponivel=null,cartao_disponivel=null,tjba_status=null,resultado_tjba=null
 where status='processando' and (locked_at is null or locked_at<=cutoff) and attempts<3;
 get diagnostics tjba_requeued=row_count;

 return jsonb_build_object('consulta_jobs',jsonb_build_object('devolvidas',digi_requeued,'revisao',digi_review),
                           'tjba_jobs',jsonb_build_object('devolvidas',tjba_requeued,'revisao',tjba_review));
end $function$;

-- Chamada pelo worker da VPS: ao iniciar (p_older_seconds=0, libera o que ele próprio segurava
-- antes de cair) e pela rotina agendada (prazo padrão de 30 minutos; a consulta mais longa
-- observada levou 12 minutos).
create or replace function public.release_stale_jobs(p_older_seconds integer default 1800)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
 select apoiarcred_private.release_stale_jobs(make_interval(secs=>greatest(coalesce(p_older_seconds,1800),0)));
$function$;
revoke all on function apoiarcred_private.release_stale_jobs(interval) from public,anon,authenticated;
revoke all on function public.release_stale_jobs(integer) from public,anon,authenticated;
grant execute on function public.release_stale_jobs(integer) to service_role;

create or replace function public.claim_consulta_jobs_for_api(p_slots integer[])
returns setof public.consulta_jobs
language plpgsql
set search_path to ''
as $function$
declare slot integer; claimed public.consulta_jobs;
begin
 if p_slots is null or cardinality(p_slots)=0 then return;end if;
 if cardinality(p_slots)>100 then raise exception 'Envie até 100 executores por reserva';end if;
 for slot in select distinct s from unnest(p_slots) s order by 1 loop
  -- Vaga ainda ocupada: pular sem confundir com fila vazia.
  continue when exists(select 1 from public.consulta_jobs where execution_mode='api' and status='processando' and api_slot=slot);
  -- Mesmas regras e mesmo bloqueio da reserva individual; o bloqueio é reentrante na transação.
  select * into claimed from public.claim_consulta_job_for_api(slot) limit 1;
  exit when claimed.id is null;
  return next claimed;
  claimed:=null;
 end loop;
end $function$;
revoke all on function public.claim_consulta_jobs_for_api(integer[]) from public,anon,authenticated;
grant execute on function public.claim_consulta_jobs_for_api(integer[]) to service_role;

-- Rotina agendada no banco (Supabase oferece pg_cron): a cada 5 minutos devolve o que passou do prazo,
-- mesmo que o worker da VPS esteja fora do ar.
do $do$
begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') then
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname='apoiarcred-release-stale-jobs';
  perform cron.schedule('apoiarcred-release-stale-jobs','*/5 * * * *',
   $cron$select apoiarcred_private.release_stale_jobs(interval '30 minutes')$cron$);
 else
  raise notice 'pg_cron indisponível: a devolução automática dependerá do worker da VPS.';
 end if;
end $do$;
