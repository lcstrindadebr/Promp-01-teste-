begin;

create table if not exists public.crm_oportunidades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cpf text not null check (cpf ~ '^[0-9]{11}$'),
  nome text check (length(nome) <= 160),
  produto text not null check (produto in ('margem','saque','recompra')),
  convenio text not null default '',
  etapa text not null default 'novo'
    check (etapa in ('novo','contato','simulacao','negociacao','ganho','perdido')),
  proxima_acao text check (length(proxima_acao) <= 500),
  created_at timestamptz not null default now()
);
alter table public.crm_oportunidades enable row level security;
revoke all on public.crm_oportunidades from public, anon, authenticated;
grant select, insert (cpf,nome,produto,convenio), update (etapa,proxima_acao)
  on public.crm_oportunidades to authenticated;
drop policy if exists crm_oportunidades_owner on public.crm_oportunidades;
create policy crm_oportunidades_owner on public.crm_oportunidades
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists crm_oportunidades_update on public.crm_oportunidades;
create policy crm_oportunidades_update on public.crm_oportunidades
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists crm_oportunidades_insert on public.crm_oportunidades;
create policy crm_oportunidades_insert on public.crm_oportunidades
  for insert to authenticated with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.crm_clientes c
      where c.user_id = crm_oportunidades.user_id
        and c.cpf = crm_oportunidades.cpf
    ) and (crm_oportunidades.convenio = '' or exists (
      select 1 from public.crm_vinculos c
      where c.user_id = crm_oportunidades.user_id
        and c.cpf = crm_oportunidades.cpf
        and c.convenio = crm_oportunidades.convenio
    ))
  );
create unique index if not exists crm_oportunidade_aberta
  on public.crm_oportunidades(user_id,cpf,produto,convenio)
  where etapa not in ('ganho','perdido');
create index if not exists crm_oportunidades_lista
  on public.crm_oportunidades(user_id,created_at desc,id desc);

commit;
