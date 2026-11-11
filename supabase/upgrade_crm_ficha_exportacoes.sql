begin;
alter table public.crm_oportunidades add column responsavel text check(length(responsavel)<=120);
grant update(responsavel) on public.crm_oportunidades to authenticated;
create or replace view public.crm_opportunity_cards with(security_invoker=true) as
 select o.id,o.user_id,o.cpf,o.nome,o.produto,o.convenio,o.etapa,o.proxima_acao,o.created_at,o.campos,
 q.saldo_liquidacao,q.emprestimo_disponivel,q.consultado_em as resultado_em,q.created_at as resultado_criado_em,q.servico as resultado_fonte,
 o.automatica,o.sinais_consulta,o.responsavel
 from public.crm_oportunidades o left join lateral (
 select c.saldo_liquidacao,c.emprestimo_disponivel,c.consultado_em,c.created_at,c.servico
 from public.crm_consultas c where c.user_id=o.user_id and c.cpf=o.cpf and
 ((o.produto='recompra' and c.servico='digimais_saldo_parcela' and c.saldo_liquidacao is not null)
 or (o.produto='margem' and o.convenio<>'' and c.convenio=o.convenio and c.servico='tjba_margem' and c.emprestimo_disponivel is not null))
 order by c.consultado_em desc nulls last,c.created_at desc,c.id desc limit 1
 ) q on true;

create table public.crm_exportacoes (
 id uuid primary key,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 oportunidade_referencia uuid not null references public.crm_oportunidades(id) on delete cascade,
 criada_em timestamptz not null default now(),
 total integer not null check(total>0),
 movidas integer not null check(movidas>=0 and movidas<=total),
 planilha jsonb not null check(jsonb_typeof(planilha)='array')
);
alter table public.crm_exportacoes enable row level security;
revoke all on public.crm_exportacoes from public,anon,authenticated;
grant select,insert(id,total,movidas,planilha,oportunidade_referencia) on public.crm_exportacoes to authenticated;
create policy crm_exportacoes_own_read on public.crm_exportacoes for select to authenticated using(user_id=(select auth.uid()));
create policy crm_exportacoes_own_insert on public.crm_exportacoes for insert to authenticated with check(user_id=(select auth.uid()) and exists(
 select 1 from public.crm_oportunidades o where o.id=oportunidade_referencia and o.user_id=(select auth.uid())
));
create index crm_exportacoes_referencia on public.crm_exportacoes(oportunidade_referencia);
create index crm_exportacoes_conta_data on public.crm_exportacoes(user_id,criada_em desc,id);

create function public.crm_registrar_exportacao(p_lote uuid,p_itens jsonb,p_planilha jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare moved integer; total integer; reference_id uuid;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_lote::text,0));
 select movidas into moved from public.crm_exportacoes where id=p_lote and user_id=auth.uid();
 if found then return moved;end if;
 total:=jsonb_array_length(p_itens);
 if total is null or total<1 or jsonb_array_length(p_planilha) is distinct from total+1 then
  raise exception 'A planilha deve corresponder ao lote exportado.';
 end if;
 select o.id into reference_id
 from jsonb_to_recordset(p_itens) item(id uuid)
 join public.crm_oportunidades o on o.id=item.id and o.user_id=auth.uid()
 order by o.id limit 1;
 if reference_id is null then raise exception 'Nenhuma oportunidade do lote está disponível.'; end if;
 moved:=public.crm_marcar_exportadas(p_itens);
 insert into public.crm_exportacoes(id,total,movidas,planilha,oportunidade_referencia)
 values(p_lote,total,moved,p_planilha,reference_id);
 return moved;
end $$;
revoke all on function public.crm_registrar_exportacao(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.crm_registrar_exportacao(uuid,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
