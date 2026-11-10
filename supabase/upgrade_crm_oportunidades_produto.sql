begin;
drop index if exists public.crm_uma_oportunidade_automatica;
create unique index crm_oportunidade_automatica_por_produto
 on public.crm_oportunidades(user_id,cpf,produto) where automatica;

create or replace function apoiarcred_private.crm_consolidar(p_uid uuid,p_cpf text,p_fonte text,p_data timestamptz,p_dados jsonb,p_produto text)
returns void language plpgsql security definer set search_path='' as $$
declare produto_alvo text := p_produto;
begin
 update public.crm_cadastros
 set resumo_consultas=jsonb_set(resumo_consultas,array[p_fonte],jsonb_build_object('data',p_data,'dados',p_dados))
 where user_id=p_uid and cpf=p_cpf
 and coalesce((resumo_consultas->p_fonte->>'data')::timestamptz,'-infinity')<=p_data;
 if not found then return; end if;

 if left(p_fonte,14)='amigoz_margem_' then
  if jsonb_typeof(p_dados)='array' and exists(
   select 1 from jsonb_array_elements(p_dados) x
   where case when jsonb_typeof(x->'margem_atual')='number' then (x->>'margem_atual')::numeric>20 else false end
  ) then produto_alvo:='margem'; end if;
 elsif p_fonte='digimais' and not (
  case when jsonb_typeof(p_dados->'saldo')='number' then (p_dados->>'saldo')::numeric>0 else false end
 ) then
  produto_alvo:=null;
 end if;

 -- Remove this source from legacy mixed cards and from signals no longer eligible.
 update public.crm_oportunidades set sinais_consulta=sinais_consulta-p_fonte
 where user_id=p_uid and cpf=p_cpf and automatica and sinais_consulta ? p_fonte
 and produto is distinct from produto_alvo;
 if produto_alvo is null then return; end if;

 update public.crm_oportunidades
 set sinais_consulta=jsonb_set(sinais_consulta,array[p_fonte],p_dados)
 where user_id=p_uid and cpf=p_cpf and automatica and produto=produto_alvo;
 if found then return; end if;
 update public.crm_oportunidades
 set automatica=true,sinais_consulta=jsonb_set(sinais_consulta,array[p_fonte],p_dados)
 where id=(select id from public.crm_oportunidades
  where user_id=p_uid and cpf=p_cpf and produto=produto_alvo and etapa not in ('ganho','perdido')
  order by created_at desc,id desc limit 1);
 if found then return; end if;
 insert into public.crm_oportunidades(user_id,cpf,nome,produto,automatica,sinais_consulta)
 select user_id,cpf,left(nome,160),produto_alvo,true,jsonb_build_object(p_fonte,p_dados)
 from public.crm_cadastros where user_id=p_uid and cpf=p_cpf
 on conflict do nothing;
end $$;

create function apoiarcred_private.crm_consolidar_margem_consigx()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status in ('concluida','nao_encontrado') then
  perform apoiarcred_private.crm_consolidar(new.user_id,new.cpf,'consigx_margem_'||new.convenio,
   coalesce(new.consultado_em,new.created_at),
   jsonb_build_object('margem_emprestimo',new.emprestimo_disponivel,'margem_cartao',new.cartao_disponivel),
   case when new.status='concluida' and new.emprestimo_disponivel>20 then 'margem' end);
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.crm_consolidar_margem_consigx() from public,anon,authenticated;
create trigger zz_crm_oportunidade_consigx after insert or update of status,consultado_em,emprestimo_disponivel on public.tjba_jobs
for each row execute function apoiarcred_private.crm_consolidar_margem_consigx();

-- Split previously consolidated sources without changing stages or consultation history.
do $$
declare j record;
begin
 for j in select c.user_id,c.cpf,x.key,x.value from public.crm_cadastros c cross join lateral jsonb_each(c.resumo_consultas) x
 loop
  perform apoiarcred_private.crm_consolidar(j.user_id,j.cpf,j.key,(j.value->>'data')::timestamptz,j.value->'dados',
   case when j.key='digimais' and j.value->'dados'->>'status'='concluida' then 'recompra'
    when left(j.key,13)='amigoz_saque_' and exists(
      select 1 from jsonb_array_elements(case when jsonb_typeof(j.value->'dados')='array' then j.value->'dados' else '[]'::jsonb end) x
      where lower(x->>'elegivel')='sim' and x->>'erro_informado' is distinct from 'true'
      and case when jsonb_typeof(x->'valor_saque_disponivel')='number' then (x->>'valor_saque_disponivel')::numeric>0 else false end
    ) then 'saque' end);
 end loop;
 for j in select distinct on (user_id,cpf,convenio) * from public.tjba_jobs
  where status in ('concluida','nao_encontrado')
  order by user_id,cpf,convenio,coalesce(consultado_em,created_at) desc,id desc
 loop
  perform apoiarcred_private.crm_consolidar(j.user_id,j.cpf,'consigx_margem_'||j.convenio,
   coalesce(j.consultado_em,j.created_at),
   jsonb_build_object('margem_emprestimo',j.emprestimo_disponivel,'margem_cartao',j.cartao_disponivel),
   case when j.status='concluida' and j.emprestimo_disponivel>20 then 'margem' end);
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
