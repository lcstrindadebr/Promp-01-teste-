begin;

-- Caller privileges and the original row policies protect both sources.
create or replace view public.crm_consultas with (security_invoker=true) as
select id, user_id, cpf, nome, telefone, servico, null::text as convenio,
       status, created_at, consultado_em, null::text as matricula,
       null::text as situacao_atual, null::numeric as emprestimo_disponivel,
       null::numeric as cartao_disponivel, saldo_liquidacao, valor_parcela
from public.consulta_jobs
union all
select id, user_id, cpf, nome, telefone, servico, convenio,
       status, created_at, consultado_em, matricula, situacao_atual,
       emprestimo_disponivel, cartao_disponivel, null::numeric, null::numeric
from public.tjba_jobs;

create or replace view public.crm_clientes with (security_invoker=true) as
select user_id, cpf,
       (array_agg(nome order by created_at desc, id desc)
          filter (where nome <> 'CPF ' || cpf and nome <> 'Cliente TJBA'
                  and btrim(nome) <> ''))[1] as nome,
       (array_agg(telefone order by created_at desc, id desc)
          filter (where btrim(telefone) <> ''))[1] as telefone,
       max(coalesce(consultado_em, created_at)) as ultima_atividade
from public.crm_consultas
group by user_id, cpf;

revoke all on public.crm_consultas, public.crm_clientes from public, anon, authenticated;
grant select on public.crm_consultas, public.crm_clientes to authenticated;
create index if not exists consulta_jobs_crm_cpf on public.consulta_jobs(user_id, cpf);
create index if not exists tjba_jobs_crm_cpf on public.tjba_jobs(user_id, cpf);

commit;
