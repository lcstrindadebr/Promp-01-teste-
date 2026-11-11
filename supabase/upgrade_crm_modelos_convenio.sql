begin;
update public.crm_catalogo_importacao set servicos=array_remove(servicos,'digimais_saldo') where uf='BA' and codigo='saeb';
create or replace function apoiarcred_private.crm_import_and_start(p_request_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); fingerprint text; previous public.crm_import_requests;
 count_clients integer; n integer=0; cid uuid; lots jsonb='[]'; mode text;
 agreement public.crm_catalogo_importacao; result jsonb; row jsonb; imported record; ref text; loan numeric; card numeric; eligibility text; available numeric;
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
 count_clients=apoiarcred_private.crm_import_catalog_clients(p_uf,p_convenio,p_servicos,p_rows);
 update public.crm_cadastros c set data_nascimento=x.data_nascimento::date
 from jsonb_to_recordset(p_rows) x(cpf text,data_nascimento text)
 where c.user_id=uid and c.cpf=x.cpf and nullif(x.data_nascimento,'') is not null;
 insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,fonte,confirmado_em)
 select uid,x.cpf,p_uf,p_convenio,btrim(x.numero_matricula),'importacao',now()
 from jsonb_to_recordset(p_rows) x(cpf text,numero_matricula text)
 where nullif(btrim(x.numero_matricula),'') is not null
 on conflict(user_id,cpf,uf,convenio,matricula) do nothing;

 for imported in select * from jsonb_to_recordset(p_rows) x(cpf text,margem_livre numeric,margem_emprestimo numeric,margem_cartao numeric,saque_amigoz_elegivel boolean,saque_amigoz_valor numeric) loop
  if imported.margem_livre is not null or imported.margem_emprestimo is not null or imported.margem_cartao is not null then
   if not agreement.servicos && array['amigoz_margem','consigx_margem'] then raise exception 'Margem indisponível neste convênio.';end if;
   ref:='margem_importada_'||p_convenio;
   select coalesce(imported.margem_emprestimo,imported.margem_livre,(resumo_consultas->ref->'dados'->>'margem_emprestimo')::numeric),
    coalesce(imported.margem_cartao,(resumo_consultas->ref->'dados'->>'margem_cartao')::numeric)
   into loan,card from public.crm_cadastros where user_id=uid and cpf=imported.cpf;
   perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,now(),
    jsonb_build_object('margem_emprestimo',loan,'margem_cartao',card),case when greatest(loan,card)>20 then 'margem' end);
   update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref,'origem'],'"importacao"')
    where user_id=uid and cpf=imported.cpf;
  end if;
  if imported.saque_amigoz_elegivel is not null or imported.saque_amigoz_valor is not null then
   if not 'amigoz_saque'=any(agreement.servicos) then raise exception 'Saque Amigoz indisponível neste convênio.';end if;
   ref:='amigoz_saque_'||p_convenio;
   select coalesce(case when imported.saque_amigoz_elegivel then 'Sim'
        when imported.saque_amigoz_elegivel=false then 'Não' end,
        case when resumo_consultas->ref->>'origem'='importacao' then resumo_consultas->ref->'dados'->0->>'elegivel' end),
    coalesce(imported.saque_amigoz_valor,case when imported.saque_amigoz_elegivel is distinct from false
        and resumo_consultas->ref->>'origem'='importacao' then (resumo_consultas->ref->'dados'->0->>'valor_saque_disponivel')::numeric end)
   into eligibility,available from public.crm_cadastros where user_id=uid and cpf=imported.cpf;
   if available<0 or (eligibility='Não' and available>0) then
    raise exception 'Dados de saque complementar Amigoz incompatíveis.';
   end if;
   perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,now(),
    jsonb_build_array(jsonb_build_object('elegivel',eligibility,'valor_saque_disponivel',available)),
    case when eligibility='Sim' and available>0 then 'saque' end);
   update public.crm_cadastros set resumo_consultas=jsonb_set(resumo_consultas,array[ref,'origem'],'"importacao"')
    where user_id=uid and cpf=imported.cpf;
  end if;
 end loop;

 if 'digimais_saldo'=any(p_servicos) then
  if exists(select 1 from jsonb_to_recordset(p_rows) x(nome text,telefone text) where coalesce(length(btrim(nome)),0)=0 or coalesce(telefone,'')!~'^[0-9]{10,13}$') then
   raise exception 'Digi+ exige nome e telefone com DDD em todas as linhas.';
  end if;
  cid=public.create_consulta_campaign('Importação · '||left(agreement.nome,100)||' · Digi+',p_rows);
  lots=lots||jsonb_build_array(jsonb_build_object('id',cid,'servico','digimais_saldo_parcela'));
  n=n+count_clients;
 end if;
 if 'consigx_margem'=any(p_servicos) then
  cid=public.create_consigx_campaign('Importação · '||left(agreement.nome,100)||' · ConsigX',p_rows,p_convenio);
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
  n=n+count_clients;
 end if;
 result=jsonb_build_object('clientes',count_clients,'consultas',n,'campanhas',lots);
 insert into public.crm_import_requests(user_id,request_id,fingerprint,response) values(uid,p_request_id,fingerprint,result);
 return result;
end $$;

do $$
begin
 if to_regprocedure('apoiarcred_private.api_route_oportunidades(uuid,text,text,jsonb)') is null then
  alter function apoiarcred_private.api_route(uuid,text,text,jsonb) rename to api_route_oportunidades;
 end if;
end $$;
create or replace function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare data jsonb; previous_sub text;
begin
 if method='GET' and route='/clientes/convenios' then
  if p ? 'uf' and coalesce(p->>'uf','') !~ '^[A-Za-z]{2}$' then
   return apoiarcred_private.api_error(422,'invalid_filter','Informe uma UF de duas letras.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
   'uf',c.uf,'id',c.codigo,'nome',c.nome,'servicos',c.servicos,
   'campos_obrigatorios',array['cpf'],
   'campos_opcionais',array['nome','telefone','numero_matricula','data_nascimento']
    || case when c.servicos && array['amigoz_margem','consigx_margem'] then array['margem_emprestimo','margem_cartao'] else '{}'::text[] end
    || case when 'amigoz_saque'=any(c.servicos) then array['saque_amigoz_elegivel','saque_amigoz_valor'] else '{}'::text[] end,
   'requisitos_servicos',case when 'digimais_saldo'=any(c.servicos) then '{"digimais_saldo":["cpf","nome","telefone"]}'::jsonb else '{}'::jsonb end
  ) order by c.uf,c.nome),'[]') into data
  from public.crm_catalogo_importacao c where not (p ? 'uf') or c.uf=upper(p->>'uf');
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if method='POST' and route='/clientes/importacoes' then
  if jsonb_typeof(p->'clientes') is distinct from 'array'
     or jsonb_typeof(coalesce(p->'servicos','[]')) is distinct from 'array'
     or coalesce(p->>'uf','') !~ '^[A-Za-z]{2}$' or coalesce(p->>'convenio','')='' then
   return apoiarcred_private.api_error(422,'invalid_import','Informe UF, convênio, clientes e uma lista opcional de serviços.');
  end if;
  if jsonb_array_length(p->'clientes') not between 1 and 10000 or exists (select 1 from jsonb_array_elements(p->'clientes') x where jsonb_typeof(x)<>'object') then
   return apoiarcred_private.api_error(422,'invalid_import','Envie entre 1 e 10.000 objetos de clientes.');
  end if;
  if exists (
   select 1 from jsonb_array_elements(p->'clientes') x
   where jsonb_typeof(x->'cpf') is distinct from 'string'
      or exists (select 1 from jsonb_each(x) f where jsonb_typeof(f.value)<>'null' and
       ((f.key in ('nome','telefone','numero_matricula','data_nascimento') and jsonb_typeof(f.value)<>'string')
        or (f.key in ('margem_livre','margem_emprestimo','margem_cartao','saque_amigoz_valor') and jsonb_typeof(f.value)<>'number')
        or (f.key='saque_amigoz_elegivel' and jsonb_typeof(f.value)<>'boolean')))
      or (x->>'data_nascimento' is not null and x->>'data_nascimento' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
      or length(x->>'numero_matricula')>256
  ) then
   return apoiarcred_private.api_error(422,'invalid_import','Confira os tipos dos campos. CPF, telefone e matrícula devem ser texto, e a data deve usar AAAA-MM-DD.');
  end if;
  select jsonb_agg(x||jsonb_build_object('cpf',regexp_replace(x->>'cpf','[. -]','','g')) order by ord) into data
  from jsonb_array_elements(p->'clientes') with ordinality as rows(x,ord);
  previous_sub:=current_setting('request.jwt.claim.sub',true);
  perform set_config('request.jwt.claim.sub',uid::text,true);
  begin
   data:=apoiarcred_private.crm_import_and_start(gen_random_uuid(),upper(p->>'uf'),p->>'convenio',
    array(select jsonb_array_elements_text(coalesce(p->'servicos','[]'))),data);
  exception when insufficient_privilege then
   perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
   return apoiarcred_private.api_error(403,'import_not_allowed','A conta não possui permissão para esta importação ou consulta.');
  when raise_exception or invalid_datetime_format or datetime_field_overflow then
   perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
   return apoiarcred_private.api_error(422,'invalid_import',sqlerrm);
  end;
  perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  return apoiarcred_private.api_response(201,jsonb_build_object('data',data));
 end if;
 return apoiarcred_private.api_route_oportunidades(uid,method,route,p);
end $$;
revoke all on function apoiarcred_private.api_route(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.api_route(uuid,text,text,jsonb) to service_role;
grant execute on function apoiarcred_private.crm_import_and_start(uuid,text,text,text[],jsonb) to service_role;
notify pgrst,'reload schema';
commit;
