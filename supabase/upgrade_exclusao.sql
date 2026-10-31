-- Owner-scoped deletion. Foreign keys cascade jobs and saved simulations.
grant delete on public.consulta_jobs,public.consulta_lotes to authenticated;
drop policy if exists jobs_delete on public.consulta_jobs;
create policy jobs_delete on public.consulta_jobs for delete to authenticated using(user_id=(select auth.uid()));
drop policy if exists lotes_delete on public.consulta_lotes;
create policy lotes_delete on public.consulta_lotes for delete to authenticated using(user_id=(select auth.uid()));
notify pgrst,'reload schema';
