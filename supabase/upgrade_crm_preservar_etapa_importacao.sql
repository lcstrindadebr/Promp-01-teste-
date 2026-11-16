begin;
CREATE OR REPLACE FUNCTION apoiarcred_private.crm_import_and_start(p_request_id uuid, p_uf text, p_convenio text, p_servicos text[], p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); fingerprint text; previous public.crm_import_requests;
 existing_cpfs text[]; count_clients integer; n integer=0; cid uuid; lots jsonb='[]'; mode text;
 agreement public.crm_catalogo_importacao; result jsonb; row jsonb; imported record; ref text; loan numeric; card numeric; eligibility text; available numeric; observed timestamptz; core_rows jsonb; errors jsonb; margin record; accepted integer:=0; ignored integer:=0;
begin
 if uid is null or p_request_id is null then raise insufficient_privilege;end if;
 -- Serialize retries of one confirmation; an ambiguous HTTP response is safe to retry.
 perform pg_advisory_xact_lock(hashtextextended(uid::text||p_request_id::text,0));
 fingerprint=md5(jsonb_build_object('uf',p_uf,'convenio',p_convenio,'servicos',p_servicos,'rows',p_rows)::text);
 select * into previous from public.crm_import_requests where user_id=uid and request_id=p_request_id;
 if found then
  if previous.fingerprint<>fingerprint then raise exception 'Esta confirmação já foi usada com outros dados. Reabra a importação.';end if;
  return previous.response;
 end if;
 select * into agreement from public.crm_catalogo_importacao where uf=p_uf and codigo=p_convenio;
 if not found then raise exception 'Convênio inválido para esta UF.'; end if;
 errors:=apoiarcred_private.crm_import_errors(p_uf,p_convenio,p_servicos,p_rows);
 if jsonb_array_length(errors)>0 then raise exception '%',errors->0->>'mensagem';end if;
 select jsonb_agg(x order by x->>'cpf') into core_rows from (
  select distinct on (x->>'cpf') x from jsonb_array_elements(p_rows) with ordinality r(x,ord)
  order by x->>'cpf',ord desc
 ) r;
 perform pg_advisory_xact_lock(hashtextextended('crm-import:'||uid::text,0));
 select coalesce(array_agg(c.cpf),array[]::text[]) into existing_cpfs
 from public.crm_cadastros c join jsonb_to_recordset(core_rows) x(cpf text) on x.cpf=c.cpf
 where c.user_id=uid;
 count_clients=apoiarcred_private.crm_import_catalog_clients(p_uf,p_convenio,p_servicos,core_rows);
 update public.crm_cadastros c set data_nascimento=x.data_nascimento::date
 from jsonb_to_recordset(core_rows) x(cpf text,data_nascimento text)
 where c.user_id=uid and c.cpf=x.cpf and nullif(x.data_nascimento,'') is not null;
 insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,fonte,confirmado_em)
 select uid,x.cpf,p_uf,p_convenio,btrim(x.numero_matricula),'importacao',now()
 from jsonb_to_recordset(p_rows) x(cpf text,numero_matricula text)
 where nullif(btrim(x.numero_matricula),'') is not null
 on conflict(user_id,cpf,uf,convenio,matricula) do nothing;

 for imported in select * from jsonb_to_recordset(p_rows) x(cpf text,margem_livre numeric,margem_emprestimo numeric,margem_cartao numeric,saque_amigoz_elegivel boolean,saque_amigoz_valor numeric,numero_matricula text,instituicao text,data_dados timestamptz,margem_beneficio numeric,margem_consignado numeric) loop
  observed:=coalesce(imported.data_dados,now());

  for margin in select * from (values
   ('emprestimo',coalesce(imported.margem_emprestimo,imported.margem_livre)),
   ('cartao',imported.margem_cartao),('beneficio',imported.margem_beneficio),('consignado',imported.margem_consignado)
  ) m(produto,valor) where valor is not null loop
   if apoiarcred_private.crm_store_margin(uid,imported.cpf,p_convenio,coalesce(imported.numero_matricula,''),
       coalesce(nullif(imported.instituicao,''),'informada'),margin.produto,margin.valor,observed,'importacao') then
    accepted:=accepted+1;
   else ignored:=ignored+1; end if;
  end loop;
  if imported.margem_livre is not null or imported.margem_emprestimo is not null or imported.margem_cartao is not null
   or imported.margem_beneficio is not null or imported.margem_consignado is not null then
   -- Keep the summary used by existing clients; individual values remain in crm_margens_vinculo.
   select max(valor) filter(where produto='emprestimo'),max(valor) filter(where produto<>'emprestimo')
   into loan,card from public.crm_margens_vinculo where user_id=uid and cpf=imported.cpf and convenio=p_convenio;
   ref:='margem_importada_'||p_convenio;
   if imported.cpf=any(existing_cpfs) then
    update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref],
     jsonb_build_object('data',now(),'dados',jsonb_build_object('margem_emprestimo',loan,'margem_cartao',card)))
    where user_id=uid and cpf=imported.cpf
     and coalesce((resumo_consultas->ref->>'data')::timestamptz,'-infinity')<=now();
   else
    perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,now(),
    jsonb_build_object('margem_emprestimo',loan,'margem_cartao',card),case when greatest(loan,card)>20 then 'margem' end);
   end if;
   update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref,'origem'],'"importacao"')
    where user_id=uid and cpf=imported.cpf;
  end if;
  if imported.saque_amigoz_elegivel is not null or imported.saque_amigoz_valor is not null then
   if not 'amigoz_saque'=any(agreement.servicos) then raise exception 'Saque Amigoz indisponível neste convênio.';end if;
   ref:='amigoz_saque_'||p_convenio;
   if exists(select 1 from public.crm_dados_cliente where user_id=uid and cpf=imported.cpf
     and referencia=ref and registrado_em>observed) then ignored:=ignored+1;continue;end if;
   select coalesce(case when imported.saque_amigoz_elegivel then 'Sim'
        when imported.saque_amigoz_elegivel=false then 'Não' end,
        case when resumo_consultas->ref->>'origem'='importacao' then resumo_consultas->ref->'dados'->0->>'elegivel' end),
    coalesce(imported.saque_amigoz_valor,case when imported.saque_amigoz_elegivel is distinct from false
        and resumo_consultas->ref->>'origem'='importacao' then (resumo_consultas->ref->'dados'->0->>'valor_saque_disponivel')::numeric end)
   into eligibility,available from public.crm_cadastros where user_id=uid and cpf=imported.cpf;
   if available<0 or (eligibility='Não' and available>0) then
    raise exception 'Dados de saque complementar Amigoz incompatíveis.';
   end if;
   if imported.cpf=any(existing_cpfs) then
    update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref],
     jsonb_build_object('data',observed,'dados',jsonb_build_array(jsonb_build_object('elegivel',eligibility,'valor_saque_disponivel',available))))
    where user_id=uid and cpf=imported.cpf
     and coalesce((resumo_consultas->ref->>'data')::timestamptz,'-infinity')<=observed;
   else
    perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,observed,
    jsonb_build_array(jsonb_build_object('elegivel',eligibility,'valor_saque_disponivel',available)),
    case when eligibility='Sim' and available>0 then 'saque' end);
   end if;
   update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref,'origem'],'"importacao"')
    where user_id=uid and cpf=imported.cpf;
  end if;
 end loop;

 if 'digimais_saldo'=any(p_servicos) then
  if exists(select 1 from jsonb_to_recordset(p_rows) x(nome text,telefone text) where coalesce(length(btrim(nome)),0)=0 or coalesce(telefone,'')!~'^[0-9]{10,13}$') then
   raise exception 'Digi+ exige nome e telefone com DDD em todas as linhas.';
  end if;
  cid=public.create_consulta_campaign('Importação · '||left(agreement.nome,100)||' · Digi+',core_rows);
  lots=lots||jsonb_build_array(jsonb_build_object('id',cid,'servico','digimais_saldo_parcela'));
  n=n+count_clients;
 end if;
 if 'consigx_margem'=any(p_servicos) then
  cid=public.create_consigx_campaign('Importação · '||left(agreement.nome,100)||' · ConsigX',core_rows,p_convenio);
  lots=lots||jsonb_build_array(jsonb_build_object('id',cid,'servico','tjba_margem'));
  n=n+count_clients;
 end if;
 if p_servicos && array['amigoz_saque','amigoz_margem'] then
  mode=case when array['amigoz_saque','amigoz_margem'] <@ p_servicos then 'ambos' when 'amigoz_margem'=any(p_servicos) then 'margem' else 'saque' end;
  if exists(select 1 from jsonb_array_elements(p_rows) x where length(coalesce(x->>'numero_matricula',''))>256) then raise exception 'Matrícula deve ter até 256 caracteres.';end if;
  -- Same shared quota and access contract as the Amigoz individual API.
  for row in select value from jsonb_array_elements(p_rows) loop
   perform public.authorize_amigoz(uid,true);
   insert into public.amigoz_jobs(user_id,cpf,nome,telefone,convenio,uf,modo,numero_matricula,import_id)
   values(uid,row->>'cpf',row->>'nome',row->>'telefone',p_convenio,p_uf,mode,nullif(btrim(row->>'numero_matricula'),''),p_request_id);
  end loop;
  n=n+jsonb_array_length(p_rows);
 end if;
 result=jsonb_build_object('id',p_request_id,'uf',p_uf,'convenio',p_convenio,'responsavel',uid,'status','concluida','registros',jsonb_array_length(p_rows),'margens_atualizadas',accepted,'dados_antigos_ignorados',ignored,'clientes',count_clients,'clientes_novos',count_clients-cardinality(existing_cpfs),'clientes_atualizados',cardinality(existing_cpfs),'consultas',n,'campanhas',lots);
 insert into public.crm_import_requests(user_id,request_id,fingerprint,response) values(uid,p_request_id,fingerprint,result);
 return result;
end $function$;
create or replace view public.crm_opportunity_cards with (security_invoker=true) as
 SELECT o.id,
    o.user_id,
    o.cpf,
    o.nome,
    o.produto,
    o.convenio,
    o.etapa,
    o.proxima_acao,
    o.created_at,
    o.campos,
    q.saldo_liquidacao,
    q.emprestimo_disponivel,
    q.consultado_em AS resultado_em,
    q.created_at AS resultado_criado_em,
    q.servico AS resultado_fonte,
    o.automatica,
    o.sinais_consulta,
    o.responsavel,
    o.etapa_id,
    cl.cliente_id,
    e.nome AS etapa_nome,
    (e.destino_exportacao or e.codigo='exportada' or exists (
      select 1 from public.crm_movimentacoes m join public.crm_etapas destino
        on destino.user_id=m.user_id and destino.id=m.etapa_id
      where m.user_id=o.user_id and m.oportunidade_id=o.id
        and (destino.destino_exportacao or destino.codigo='exportada')
    )) AS cliente_exportado
   FROM crm_oportunidades o
     LEFT JOIN LATERAL ( SELECT c.saldo_liquidacao,
            c.emprestimo_disponivel,
            c.consultado_em,
            c.created_at,
            c.servico
           FROM crm_consultas c
          WHERE c.user_id = o.user_id AND c.cpf = o.cpf AND (o.produto = 'recompra'::text AND c.servico = 'digimais_saldo_parcela'::text AND c.saldo_liquidacao IS NOT NULL OR o.produto = 'margem'::text AND o.convenio <> ''::text AND c.convenio = o.convenio AND c.servico = 'tjba_margem'::text AND c.emprestimo_disponivel IS NOT NULL)
          ORDER BY c.consultado_em DESC NULLS LAST, c.created_at DESC, c.id DESC
         LIMIT 1) q ON true
     LEFT JOIN crm_cadastros cl ON cl.user_id = o.user_id AND cl.cpf = o.cpf
     JOIN crm_etapas e ON e.user_id = o.user_id AND e.id = o.etapa_id;
notify pgrst,'reload schema';
commit;
