-- Existing data belongs to the only implemented service.
alter table public.consulta_lotes add column if not exists servico text not null default 'digimais_saldo_parcela' check(servico in ('digimais_saldo_parcela'));
alter table public.consulta_jobs add column if not exists servico text not null default 'digimais_saldo_parcela' check(servico in ('digimais_saldo_parcela'));
grant insert(servico) on public.consulta_jobs to authenticated;
-- Keep the legacy two-argument RPC compatible with installed clients.
create or replace function public.create_consulta_campaign(p_nome text,p_items jsonb,p_servico text)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
 if p_servico is distinct from 'digimais_saldo_parcela' then raise exception 'Este serviço de higienização ainda não está disponível.'; end if;
 return public.create_consulta_campaign(p_nome,p_items);
end $$;
revoke all on function public.create_consulta_campaign(text,jsonb,text) from public,anon;
grant execute on function public.create_consulta_campaign(text,jsonb,text) to authenticated;
create or replace function public.claim_consulta_job() returns setof public.consulta_jobs language sql security invoker set search_path='' as $$
update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1
where id=(select id from public.consulta_jobs where status='aguardando' and servico='digimais_saldo_parcela' order by created_at for update skip locked limit 1) returning *;
$$;
revoke all on function public.claim_consulta_job() from public,anon,authenticated;
grant execute on function public.claim_consulta_job() to service_role;
notify pgrst,'reload schema';
