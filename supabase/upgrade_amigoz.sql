-- Estimativa autorizada: CET, 96 pagamentos mensais; primeiro em um mês.
create table if not exists public.amigoz_comissoes (
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 taxa numeric(5,2) not null check(taxa in (3,3.25,3.5,3.75,3.98,4.5,4.8)),
 percentual numeric(7,4) check(percentual between 0 and 100),
 primary key(user_id,taxa)
);
alter table public.amigoz_comissoes enable row level security;
revoke all on public.amigoz_comissoes from anon,authenticated;
grant select,insert,update on public.amigoz_comissoes to authenticated;
drop policy if exists own_commissions on public.amigoz_comissoes;
create policy own_commissions on public.amigoz_comissoes for all to authenticated
 using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create table if not exists public.amigoz_simulacoes (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 job_id uuid not null references public.consulta_jobs(id) on delete cascade,
 created_at timestamptz not null default now(),
 resultado jsonb not null
);
create index if not exists amigoz_simulacoes_owner_job on public.amigoz_simulacoes(user_id,job_id,created_at desc);
create index if not exists amigoz_simulacoes_job on public.amigoz_simulacoes(job_id);
alter table public.amigoz_simulacoes enable row level security;
revoke all on public.amigoz_simulacoes from anon,authenticated;
grant select,insert on public.amigoz_simulacoes to authenticated;
drop policy if exists own_simulations on public.amigoz_simulacoes;
create policy own_simulations on public.amigoz_simulacoes for all to authenticated
 using ((select auth.uid())=user_id)
 with check ((select auth.uid())=user_id and exists(select 1 from public.consulta_jobs j where j.id=job_id and j.user_id=(select auth.uid())));
create or replace function public.simular_amigoz(p_job_id uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare j public.consulta_jobs; t record; pct numeric; liquido numeric; troco numeric; resultados jsonb='[]'; saida jsonb;
begin
 if auth.uid() is null then raise exception 'Entre na sua conta.'; end if;
 select * into j from public.consulta_jobs where id=p_job_id and user_id=auth.uid();
 if not found then raise exception 'Consulta não encontrada.'; end if;
 if j.status in ('aguardando','processando','nao_cliente','nao_localizado') or coalesce(j.saldo_liquidacao,0)<=0 or coalesce(j.valor_parcela,0)<=0 then
 raise exception 'Aguarde saldo e parcela positivos da mesma consulta.'; end if;
 for t in select * from (values (3.00,3.63),(3.25,3.88),(3.50,4.13),(3.75,4.38),(3.98,4.61),(4.50,5.13),(4.80,5.43)) as taxas(taxa,cet) loop
 select percentual into pct from public.amigoz_comissoes where user_id=auth.uid() and taxa=t.taxa;
 liquido=round(j.valor_parcela*(1-power(1+t.cet/100,-96))/(t.cet/100),2);
 troco=liquido-j.saldo_liquidacao;
 resultados=resultados||jsonb_build_array(jsonb_build_object('taxa',t.taxa,'cet',t.cet,'limite',null,'liberado',liquido,'quitacao',j.saldo_liquidacao,'troco',case when troco>=0 then troco else null end,'insuficiente',troco<0,'percentual',pct,'comissao',case when troco>=0 and pct is not null then round((j.saldo_liquidacao+troco)*pct/100,2) else null end));
 end loop;
 saida=jsonb_build_object('job_id',j.id,'saldo',j.saldo_liquidacao,'parcela',j.valor_parcela,'prazo',96,'primeiro_vencimento_meses',1,'metodo','estimativa_cet_mensal_v1','versao_condicoes','2026-10-31','data_simulacao',now(),'tabelas',resultados,'limite_pre_aprovado',null,'custos_individuais',null);
 insert into public.amigoz_simulacoes(job_id,resultado) values(j.id,saida);
 return saida;
end $$;
revoke all on function public.simular_amigoz(uuid) from public,anon;
grant execute on function public.simular_amigoz(uuid) to authenticated;
notify pgrst,'reload schema';
