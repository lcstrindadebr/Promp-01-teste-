-- Robô Digi+ pedindo trabalho (claim_consulta_job_for_robot): para achar a campanha com fila, a função
-- conferia todas as consultas de cada campanha, inclusive as já encerradas (40 ms por pedido com a fila
-- vazia, 95% do tempo do banco em 19–22/11). Este índice guarda só as consultas pendentes do robô, então
-- fica minúsculo e o pedido cai para menos de 1 ms. Não muda o comportamento.
create index if not exists consulta_jobs_robo_pendentes on public.consulta_jobs(lote_id)
 where status in ('aguardando','processando') and execution_mode='robot';
