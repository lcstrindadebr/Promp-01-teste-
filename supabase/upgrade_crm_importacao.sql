begin;

create table if not exists public.crm_classificacoes (
  user_id uuid not null,
  cpf text not null,
  uf text not null,
  convenio text not null,
  usar_digimais boolean not null,
  importado_em timestamptz not null default now(),
  primary key (user_id, cpf, uf, convenio),
  foreign key (user_id, cpf) references public.crm_cadastros(user_id, cpf) on delete cascade
);

alter table public.crm_classificacoes enable row level security;
revoke all on public.crm_classificacoes from public, anon, authenticated;
grant select on public.crm_classificacoes to authenticated;
drop policy if exists crm_classificacao_leitura on public.crm_classificacoes;
create policy crm_classificacao_leitura on public.crm_classificacoes
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function apoiarcred_private.crm_import_clients(
  p_uf text, p_convenio text, p_usar_digimais boolean, p_rows jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
  owner_id uuid := auth.uid();
  account_access jsonb;
  state_code text := upper(btrim(p_uf));
  agreement text := lower(regexp_replace(btrim(p_convenio), '[[:space:]]+', ' ', 'g'));
begin
  account_access := apoiarcred_private.access_for(owner_id);
  if owner_id is null or not coalesce((account_access->>'active')::boolean, false)
      or coalesce((account_access->>'trial_expired')::boolean, false) then
    raise exception 'Importação indisponível para esta conta.' using errcode='42501';
  end if;
  if state_code is null or state_code not in
      ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')
      or agreement is null or length(agreement) not between 1 and 120 or p_usar_digimais is null then
    raise exception 'Informe estado, convênio e a preferência de uso do Digi+.';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Envie uma lista de clientes.';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 10000 then
    raise exception 'Envie entre 1 e 10.000 clientes por arquivo.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_rows) as r(cpf text, nome text, telefone text)
    where cpf is null or cpf !~ '^[0-9]{11}$' or cpf='00000000000'
       or length(btrim(nome)) > 160 or coalesce(telefone,'') !~ '^([0-9]{10,13})?$'
  ) then raise exception 'A lista contém CPF, nome ou telefone inválido.'; end if;
  if exists (select 1 from jsonb_to_recordset(p_rows) as r(cpf text) group by cpf having count(*)>1) then
    raise exception 'A lista contém CPFs repetidos.';
  end if;

  insert into public.crm_cadastros as c
    (user_id, cpf, nome, telefone, nome_atualizado_em, telefone_atualizado_em, ultima_atividade)
  select owner_id, r.cpf, nullif(btrim(r.nome),''), nullif(r.telefone,''),
         case when nullif(btrim(r.nome),'') is not null then now() end,
         case when nullif(r.telefone,'') is not null then now() end, now()
  from jsonb_to_recordset(p_rows) as r(cpf text, nome text, telefone text)
  order by r.cpf
  on conflict (user_id, cpf) do update set
    nome=coalesce(excluded.nome,c.nome),
    telefone=coalesce(excluded.telefone,c.telefone),
    nome_atualizado_em=coalesce(excluded.nome_atualizado_em,c.nome_atualizado_em),
    telefone_atualizado_em=coalesce(excluded.telefone_atualizado_em,c.telefone_atualizado_em),
    ultima_atividade=greatest(c.ultima_atividade,excluded.ultima_atividade);

  insert into public.crm_classificacoes (user_id, cpf, uf, convenio, usar_digimais)
  select owner_id, r.cpf, state_code, agreement, p_usar_digimais
  from jsonb_to_recordset(p_rows) as r(cpf text)
  order by r.cpf
  on conflict (user_id, cpf, uf, convenio) do update set
    usar_digimais=excluded.usar_digimais, importado_em=excluded.importado_em;
  return jsonb_array_length(p_rows);
end $$;
revoke all on function apoiarcred_private.crm_import_clients(text,text,boolean,jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_import_clients(text,text,boolean,jsonb) to authenticated;

create or replace function public.crm_import_clients(
  p_uf text, p_convenio text, p_usar_digimais boolean, p_rows jsonb
) returns integer language sql security invoker set search_path='' as $$
  select apoiarcred_private.crm_import_clients(p_uf,p_convenio,p_usar_digimais,p_rows);
$$;
revoke all on function public.crm_import_clients(text,text,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.crm_import_clients(text,text,boolean,jsonb) to authenticated;

create or replace view public.crm_classificacao_filtros with (security_invoker=true) as
select user_id,cpf,uf,convenio from public.crm_vinculos
union all
select user_id,cpf,uf,convenio from public.crm_classificacoes;
revoke all on public.crm_classificacao_filtros from public,anon,authenticated;
grant select on public.crm_classificacao_filtros to authenticated;

create or replace function public.crm_filter_clients(p_query text default '',p_uf text default '',p_convenio text default '',p_servico text default '',p_after text default '',p_limit integer default 26)
returns setof public.crm_cadastros language sql stable security invoker set search_path='' as $$
 select c.* from public.crm_cadastros c
 where c.cpf>p_after
 and (p_query='' or position(lower(p_query) in lower(coalesce(c.nome,'')))>0 or
  (regexp_replace(p_query,'[^0-9]','','g')<>'' and position(regexp_replace(p_query,'[^0-9]','','g') in c.cpf)>0))
 and ((p_uf='' and p_convenio='') or exists(select 1 from public.crm_classificacao_filtros v where v.user_id=c.user_id and v.cpf=c.cpf and (p_uf='' or v.uf=p_uf) and (p_convenio='' or v.convenio=p_convenio)))
 and (p_servico='' or exists(select 1 from public.crm_consultas q where q.user_id=c.user_id and q.cpf=c.cpf and q.servico=p_servico and (p_convenio='' or q.convenio=p_convenio or (q.convenio is null and q.servico='digimais_saldo_parcela'))))
 order by c.cpf limit greatest(1,least(coalesce(p_limit,26),500));
$$;
create or replace function public.crm_filter_options() returns table(uf text,convenio text)
language sql stable security invoker set search_path='' as $$ select distinct v.uf,v.convenio from public.crm_classificacao_filtros v order by v.uf,v.convenio $$;
revoke all on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() from public,anon;
grant execute on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() to authenticated;
notify pgrst,'reload schema';
commit;
