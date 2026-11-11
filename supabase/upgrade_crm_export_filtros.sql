begin;
create function public.crm_export_opportunities(p_uf text,p_convenio text,p_tipos text[],p_etapa text,p_after uuid default null)
returns setof public.crm_opportunity_cards language sql stable security invoker set search_path='' as $$
 select o.* from public.crm_opportunity_cards o
 where o.user_id=auth.uid()
 and o.etapa in ('novo','contato','simulacao','negociacao')
 and (p_etapa='' or o.etapa=p_etapa)
 and o.produto=any(p_tipos)
 and (p_after is null or o.id>p_after)
 and ((p_uf='' and p_convenio='') or exists(
  select 1 from public.crm_classificacao_filtros v
  where v.user_id=o.user_id and v.cpf=o.cpf
   and (p_uf='' or v.uf=p_uf) and (p_convenio='' or v.convenio=p_convenio)
   and (o.convenio='' or v.convenio=o.convenio)
   and (not exists(select 1 from jsonb_object_keys(o.sinais_consulta) k where k<>'digimais')
        or exists(select 1 from jsonb_object_keys(o.sinais_consulta) k
           where regexp_replace(k,'^(amigoz_(margem|saque)|consigx_margem)_','')=v.convenio))
 ))
 order by o.id limit 500
$$;
revoke all on function public.crm_export_opportunities(text,text,text[],text,uuid) from public,anon;
grant execute on function public.crm_export_opportunities(text,text,text[],text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
