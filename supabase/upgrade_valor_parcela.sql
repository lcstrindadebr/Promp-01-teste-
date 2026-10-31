alter table public.consulta_jobs
 add column if not exists valor_parcela numeric(14,2) check(valor_parcela >= 0),
 add column if not exists resultado_saldo jsonb,
 add column if not exists resultado_parcela jsonb;
notify pgrst, 'reload schema';
