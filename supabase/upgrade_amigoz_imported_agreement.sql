create or replace function public.amigoz_simulation_context(p_cpf text,p_convenio text default '',p_job_id uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare uid uuid=auth.uid(); cpf_value text=regexp_replace(p_cpf,'\D','','g'); model public.amigoz_model_versions;
 j public.consulta_jobs; fact public.crm_dados_cliente; agreement text=nullif(p_convenio,''); agreements text[];
 margins jsonb; rules jsonb; source jsonb; known boolean; options jsonb;
begin
 if uid is null then raise insufficient_privilege;end if;
 if cpf_value is null or cpf_value !~ '^[0-9]{11}$' then raise exception 'CPF inválido';end if;
 select * into model from public.amigoz_model_versions order by id desc limit 1;
 if p_job_id is not null then
  select * into j from public.consulta_jobs where id=p_job_id and user_id=uid and cpf=cpf_value;
  if not found then raise exception 'Consulta não encontrada na sua conta';end if;
 else
  select * into j from public.consulta_jobs where user_id=uid and cpf=cpf_value
  order by coalesce(consultado_em,created_at) desc,id desc limit 1;
 end if;
 select * into fact from public.crm_dados_cliente where user_id=uid and cpf=cpf_value and tipo='saldo_parcela'
 order by registrado_em desc limit 1;
 known=j.id is not null or exists(select 1 from public.crm_cadastros where user_id=uid and cpf=cpf_value);
 if not known then raise exception 'Cliente não encontrado na sua conta';end if;
 source=jsonb_build_object('job_id',j.id,'data',coalesce(j.consultado_em,j.created_at),'status',j.status,
  'saldo',case when j.status in ('concluida','revisao') then j.saldo_liquidacao end,
  'parcela',case when j.status in ('concluida','revisao') then j.valor_parcela end);
 if p_job_id is null and fact.registrado_em>coalesce(j.consultado_em,j.created_at,'-infinity'::timestamptz) then
  source=jsonb_build_object('job_id',null,'data',fact.registrado_em,'status',fact.dados->>'status',
   'saldo',fact.dados->'saldo','parcela',fact.dados->'parcela');
 end if;
 select array_agg(distinct convenio) into agreements from (
  select convenio from public.crm_vinculos where user_id=uid and cpf=cpf_value
  union select convenio from public.crm_margens_vinculo where user_id=uid and cpf=cpf_value
  union select c.convenio from public.crm_classificacoes c
  join public.crm_catalogo_importacao a on a.uf=c.uf and a.codigo=c.convenio
  where c.user_id=uid and c.cpf=cpf_value
 ) links;
 if agreement is null then
  if coalesce(cardinality(agreements),0)=1 then agreement=agreements[1];
  end if;
 end if;
 select value into rules from jsonb_array_elements(model.config->'eligibilidade') where value->>'convenio'=agreement
  and (coalesce(cardinality(agreements),0)=0 or agreement=any(agreements));
 select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('key',md5(jsonb_build_array(m.convenio,m.matricula,m.instituicao,m.produto)::text),
  'elegivel',coalesce(rules->'produtos' ? m.produto and rules->'instituicoes' ? m.instituicao and m.valor>=0,false))
  order by m.observado_em desc,m.matricula,m.produto),'[]'::jsonb) into margins
 from public.crm_margens_vinculo m where m.user_id=uid and m.cpf=cpf_value and (agreement is null or m.convenio=agreement);
 select coalesce(jsonb_agg(jsonb_build_object('convenio',codigo,'nome',nome) order by nome,codigo),'[]'::jsonb) into options
 from public.crm_catalogo_importacao
 where codigo=agreement or codigo=any(agreements) or (coalesce(cardinality(agreements),0)=0 and codigo ~ '^amigoz_[0-9]+$');
 return jsonb_build_object('cpf',cpf_value,'convenio',agreement,'convenio_assumido',false,'convenios',options,'elegivel',rules is not null,
  'fonte',source,'margens',margins,'version_id',model.id,'config',model.config);
end $$;
