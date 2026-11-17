-- Observabilidade (Fase 4): saúde da fila para a equipe ApoiarCred.
-- Por serviço: na fila (só campanhas não pausadas e consultas individuais), consultando, há quanto
-- tempo a mais antiga espera, concluídas e falhas na última hora e a última conclusão.
-- "Parada" = há consultas esperando e nenhuma terminou nos últimos 15 minutos.
-- Cada contagem usa um índice próprio, para poder ser chamada a cada 30 s sem pesar no banco.

create index if not exists consulta_jobs_consultado_em on public.consulta_jobs(consultado_em) where consultado_em is not null;
create index if not exists tjba_jobs_consultado_em on public.tjba_jobs(consultado_em) where consultado_em is not null;

create function public.admin_queue_health()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; hour_ago timestamptz=now()-interval '1 hour'; maintenance timestamptz;
begin
 if not apoiarcred_private.is_admin(auth.uid()) then raise insufficient_privilege;end if;
 select paused_until into maintenance from apoiarcred_private.queue_maintenance where id;
 with digi as (
  select 'digimais_saldo_parcela'::text servico,
   (select count(*) from public.consulta_jobs j join public.consulta_lotes l on l.id=j.lote_id
     where j.status='aguardando' and not l.paused) na_fila,
   (select count(*) from public.consulta_jobs where status='processando') consultando,
   (select min(j.created_at) from public.consulta_jobs j join public.consulta_lotes l on l.id=j.lote_id
     where j.status='aguardando' and not l.paused) mais_antiga,
   (select count(*) from public.consulta_jobs where consultado_em>hour_ago) concluidas_hora,
   (select count(*) from public.consulta_jobs where consultado_em>hour_ago and status in ('erro','revisao','interrompida')) falhas_hora,
   (select max(consultado_em) from public.consulta_jobs where consultado_em is not null) ultima_conclusao
 ), tjba as (
  select 'tjba_margem'::text,
   (select count(*) from public.tjba_jobs j join public.tjba_lotes l on l.id=j.lote_id
     where j.status='aguardando' and not l.paused),
   (select count(*) from public.tjba_jobs where status='processando'),
   (select min(j.created_at) from public.tjba_jobs j join public.tjba_lotes l on l.id=j.lote_id
     where j.status='aguardando' and not l.paused),
   (select count(*) from public.tjba_jobs where consultado_em>hour_ago),
   (select count(*) from public.tjba_jobs where consultado_em>hour_ago and status in ('erro','revisao')),
   (select max(consultado_em) from public.tjba_jobs where consultado_em is not null)
 ), rows as (select * from digi union all select * from tjba)
 select jsonb_build_object('gerado_em',now(),
  'manutencao_ate',case when maintenance>now() then maintenance end,
  'servicos',jsonb_agg(jsonb_build_object('servico',servico,'na_fila',na_fila,'consultando',consultando,
    'espera_minutos',case when mais_antiga is not null then floor(extract(epoch from now()-mais_antiga)/60)::int end,
    'concluidas_hora',concluidas_hora,'falhas_hora',falhas_hora,'ultima_conclusao',ultima_conclusao,
    'parada',na_fila>0 and (ultima_conclusao is null or ultima_conclusao<now()-interval '15 minutes')
     and (maintenance is null or maintenance<=now())) order by servico))
 into result from rows;
 return result;
end $$;
revoke all on function public.admin_queue_health() from public,anon;
grant execute on function public.admin_queue_health() to authenticated;
