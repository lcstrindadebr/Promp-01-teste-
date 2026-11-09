begin;

create table if not exists public.crm_cadastros (
  user_id uuid not null references auth.users(id) on delete cascade,
  cpf text not null check (cpf ~ '^[0-9]{11}$'),
  nome text,
  nome_atualizado_em timestamptz,
  telefone text,
  telefone_atualizado_em timestamptz,
  ultima_atividade timestamptz not null,
  primary key (user_id, cpf)
);

create table if not exists public.crm_vinculos (
  user_id uuid not null,
  cpf text not null,
  uf text not null,
  convenio text not null,
  matricula text not null check (btrim(matricula) <> ''),
  situacao_atual text,
  fonte text not null,
  confirmado_em timestamptz not null,
  primary key (user_id, cpf, uf, convenio, matricula),
  foreign key (user_id, cpf) references public.crm_cadastros(user_id, cpf) on delete cascade
);

alter table public.crm_cadastros enable row level security;
alter table public.crm_vinculos enable row level security;
revoke all on public.crm_cadastros, public.crm_vinculos from public, anon, authenticated;
grant select on public.crm_cadastros, public.crm_vinculos to authenticated;
drop policy if exists crm_cadastro_leitura on public.crm_cadastros;
create policy crm_cadastro_leitura on public.crm_cadastros for select
  to authenticated using (user_id = (select auth.uid()));
drop policy if exists crm_vinculo_leitura on public.crm_vinculos;
create policy crm_vinculo_leitura on public.crm_vinculos for select
  to authenticated using (user_id = (select auth.uid()));

insert into public.crm_cadastros(user_id, cpf, nome, nome_atualizado_em, telefone,
                                 telefone_atualizado_em, ultima_atividade)
select user_id, cpf,
       (array_agg(nome order by created_at desc,id desc)
          filter (where nome <> 'CPF ' || cpf and nome <> 'Cliente TJBA' and btrim(nome) <> ''))[1],
       max(created_at) filter (where nome <> 'CPF ' || cpf and nome <> 'Cliente TJBA' and btrim(nome) <> ''),
       (array_agg(telefone order by created_at desc,id desc) filter (where btrim(telefone) <> ''))[1],
       max(created_at) filter (where btrim(telefone) <> ''),
       max(coalesce(consultado_em,created_at))
from public.crm_consultas
group by user_id, cpf
on conflict (user_id, cpf) do nothing;

insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,situacao_atual,fonte,confirmado_em)
select distinct on (user_id,cpf,convenio,btrim(matricula))
       user_id,cpf,'BA',convenio,btrim(matricula),nullif(btrim(situacao_atual),''),'consigx',
       coalesce(consultado_em,created_at)
from public.tjba_jobs
where status='concluida' and btrim(matricula) <> ''
order by user_id,cpf,convenio,btrim(matricula),coalesce(consultado_em,created_at) desc,id desc
on conflict (user_id,cpf,uf,convenio,matricula) do nothing;

-- The trigger uses only the owner and fields of an existing, authorized job.
create or replace function apoiarcred_private.crm_sync_job()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  nome_real text := nullif(btrim(new.nome),'');
  telefone_real text := nullif(btrim(new.telefone),'');
  atividade timestamptz := coalesce(new.consultado_em,new.created_at);
begin
  if nome_real in ('CPF ' || new.cpf, 'Cliente TJBA') then nome_real := null; end if;

  insert into public.crm_cadastros as atual
    (user_id,cpf,nome,nome_atualizado_em,telefone,telefone_atualizado_em,ultima_atividade)
  values (new.user_id,new.cpf,nome_real,case when nome_real is not null then new.created_at end,
          telefone_real,case when telefone_real is not null then new.created_at end,atividade)
  on conflict (user_id,cpf) do update set
    nome = case when excluded.nome_atualizado_em >= coalesce(atual.nome_atualizado_em,'-infinity')
                then excluded.nome else atual.nome end,
    nome_atualizado_em = greatest(atual.nome_atualizado_em,excluded.nome_atualizado_em),
    telefone = case when excluded.telefone_atualizado_em >= coalesce(atual.telefone_atualizado_em,'-infinity')
                    then excluded.telefone else atual.telefone end,
    telefone_atualizado_em = greatest(atual.telefone_atualizado_em,excluded.telefone_atualizado_em),
    ultima_atividade = greatest(atual.ultima_atividade,excluded.ultima_atividade);

  if tg_table_name = 'tjba_jobs' then
    if new.status = 'concluida' and btrim(new.matricula) <> '' then
      insert into public.crm_vinculos as atual
        (user_id,cpf,uf,convenio,matricula,situacao_atual,fonte,confirmado_em)
      values (new.user_id,new.cpf,'BA',new.convenio,btrim(new.matricula),
              nullif(btrim(new.situacao_atual),''),'consigx',atividade)
      on conflict (user_id,cpf,uf,convenio,matricula) do update set
        situacao_atual = coalesce(excluded.situacao_atual,atual.situacao_atual),
        confirmado_em = excluded.confirmado_em
      where excluded.confirmado_em >= atual.confirmado_em;
    end if;
  end if;
  return new;
end $$;
revoke all on function apoiarcred_private.crm_sync_job() from public, anon, authenticated;

drop trigger if exists crm_sync_consulta on public.consulta_jobs;
create trigger crm_sync_consulta after insert or update of nome,telefone,consultado_em
on public.consulta_jobs for each row execute function apoiarcred_private.crm_sync_job();
drop trigger if exists crm_sync_tjba on public.tjba_jobs;
create trigger crm_sync_tjba after insert or update of nome,telefone,consultado_em,matricula,situacao_atual,status
on public.tjba_jobs for each row execute function apoiarcred_private.crm_sync_job();

create or replace view public.crm_clientes with (security_invoker=true) as
select user_id,cpf,nome,telefone,ultima_atividade from public.crm_cadastros;

commit;
