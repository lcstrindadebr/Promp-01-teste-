begin;
create table if not exists public.crm_card_settings (
 user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
 visible text[] not null default array['cpf','produto','convenio','proxima_acao'],
 fields jsonb not null default '[]'::jsonb,
 updated_at timestamptz not null default now()
);
alter table public.crm_card_settings enable row level security;
revoke all on public.crm_card_settings from public,anon,authenticated;
grant select,insert(visible,fields),update(visible,fields) on public.crm_card_settings to authenticated;
drop policy if exists crm_card_settings_owner on public.crm_card_settings;
create policy crm_card_settings_owner on public.crm_card_settings for all to authenticated
 using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
alter table public.crm_oportunidades add column if not exists campos jsonb not null default '{}'::jsonb;
grant update(campos) on public.crm_oportunidades to authenticated;
create or replace function apoiarcred_private.crm_validate_customization() returns trigger
language plpgsql set search_path='' as $$
declare f jsonb; k text; v jsonb; definitions jsonb; seen text[] := '{}';
begin
 if TG_TABLE_NAME='crm_card_settings' then
  if not (new.visible <@ array['cpf','produto','convenio','proxima_acao']) or jsonb_typeof(new.fields)<>'array' or jsonb_array_length(new.fields)>30 then raise exception 'Configuração inválida'; end if;
  for f in select value from jsonb_array_elements(new.fields) loop
   if coalesce(f->>'id','') !~ '^cf_[a-f0-9]{16}$' or f->>'id'=any(seen)
    or coalesce(f->>'label','') !~ '\S' or length(f->>'label')>60
    or lower(f->>'label') ~ '(saldo|margem|margens)'
    or coalesce(f->>'type','') not in ('text','number','date','boolean')
    or jsonb_typeof(f->'visible') is distinct from 'boolean' then raise exception 'Campo personalizado inválido; saldo e margem são protegidos'; end if;
   if TG_OP='UPDATE' and exists(select 1 from jsonb_array_elements(old.fields) x where x->>'id'=f->>'id' and x->>'type'<>f->>'type') then raise exception 'O tipo de um campo existente não pode mudar'; end if;
   seen:=array_append(seen,f->>'id');
  end loop;
  if TG_OP='UPDATE' and exists(select 1 from jsonb_array_elements(old.fields) x where not (x->>'id'=any(seen))) then raise exception 'Oculte campos existentes para preservar os dados'; end if;
  new.updated_at:=now();
 else
  if jsonb_typeof(new.campos)<>'object' or octet_length(new.campos::text)>64000 then raise exception 'Valores inválidos'; end if;
  select fields into definitions from public.crm_card_settings where user_id=new.user_id;
  for k,v in select * from jsonb_each(new.campos) loop
   select value into f from jsonb_array_elements(coalesce(definitions,'[]')) where value->>'id'=k;
   if f is null then raise exception 'Campo desconhecido'; end if;
   if v<>'null'::jsonb and (case f->>'type' when 'number' then jsonb_typeof(v)<>'number' when 'boolean' then jsonb_typeof(v)<>'boolean' else jsonb_typeof(v)<>'string' or length(v#>>'{}')>2000 end) then raise exception 'Tipo de valor inválido'; end if;
   if f->>'type'='date' and v<>'null'::jsonb then perform (v#>>'{}')::date; end if;
  end loop;
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.crm_validate_customization() from public,anon,authenticated;
drop trigger if exists crm_card_settings_validate on public.crm_card_settings;
create trigger crm_card_settings_validate before insert or update on public.crm_card_settings for each row execute function apoiarcred_private.crm_validate_customization();
drop trigger if exists crm_campos_validate on public.crm_oportunidades;
create trigger crm_campos_validate before insert or update of campos on public.crm_oportunidades for each row execute function apoiarcred_private.crm_validate_customization();

-- Filters evaluate UF and agreement on the same confirmed vínculo. No inferred classification.
create or replace function public.crm_filter_clients(p_query text default '',p_uf text default '',p_convenio text default '',p_servico text default '',p_after text default '',p_limit integer default 26)
returns setof public.crm_cadastros language sql stable security invoker set search_path='' as $$
 select c.* from public.crm_cadastros c
 where c.cpf>p_after
 and (p_query='' or position(lower(p_query) in lower(coalesce(c.nome,'')))>0 or
  (regexp_replace(p_query,'[^0-9]','','g')<>'' and position(regexp_replace(p_query,'[^0-9]','','g') in c.cpf)>0))
 and ((p_uf='' and p_convenio='') or exists(select 1 from public.crm_vinculos v where v.user_id=c.user_id and v.cpf=c.cpf and (p_uf='' or v.uf=p_uf) and (p_convenio='' or v.convenio=p_convenio)))
 and (p_servico='' or exists(select 1 from public.crm_consultas q where q.user_id=c.user_id and q.cpf=c.cpf and q.servico=p_servico and (p_convenio='' or q.convenio=p_convenio or (q.convenio is null and q.servico='digimais_saldo_parcela'))))
 order by c.cpf limit greatest(1,least(coalesce(p_limit,26),500));
$$;
create or replace function public.crm_filter_options() returns table(uf text,convenio text)
language sql stable security invoker set search_path='' as $$ select distinct v.uf,v.convenio from public.crm_vinculos v order by v.uf,v.convenio $$;
revoke all on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() from public,anon;
grant execute on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() to authenticated;
create or replace view public.crm_opportunity_cards with(security_invoker=true) as
 select o.*,q.saldo_liquidacao,q.emprestimo_disponivel,q.consultado_em as resultado_em,q.created_at as resultado_criado_em,q.servico as resultado_fonte
 from public.crm_oportunidades o left join lateral (
 select c.saldo_liquidacao,c.emprestimo_disponivel,c.consultado_em,c.created_at,c.servico
 from public.crm_consultas c where c.user_id=o.user_id and c.cpf=o.cpf and
 ((o.produto='recompra' and c.servico='digimais_saldo_parcela' and c.saldo_liquidacao is not null)
 or (o.produto='margem' and o.convenio<>'' and c.convenio=o.convenio and c.servico='tjba_margem' and c.emprestimo_disponivel is not null))
 order by c.consultado_em desc nulls last,c.created_at desc,c.id desc limit 1
 ) q on true;
revoke all on public.crm_opportunity_cards from public,anon,authenticated;
grant select on public.crm_opportunity_cards to authenticated;
notify pgrst,'reload schema';
commit;
