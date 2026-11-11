begin;
create table public.crm_margens_vinculo (
 user_id uuid not null,cpf text not null,convenio text not null,matricula text not null default '',
 instituicao text not null,produto text not null check(produto in ('emprestimo','cartao','beneficio','consignado')),
 valor numeric not null,observado_em timestamptz not null,origem text not null check(origem in ('consulta','importacao')),
 primary key(user_id,cpf,convenio,matricula,instituicao,produto),
 foreign key(user_id,cpf) references public.crm_cadastros(user_id,cpf) on delete cascade
);
alter table public.crm_margens_vinculo enable row level security;
revoke all on public.crm_margens_vinculo from public,anon,authenticated;
grant select on public.crm_margens_vinculo to authenticated;
create policy crm_margens_leitura on public.crm_margens_vinculo for select to authenticated using(user_id=(select auth.uid()));

create function apoiarcred_private.crm_store_margin(
 uid uuid,cpf_value text,agreement text,registration text,institution text,product text,amount numeric,observed timestamptz,source text
) returns boolean language plpgsql security definer set search_path='' as $$
begin
 -- Lock the client to serialize updates from consultation and import.
 perform 1 from public.crm_cadastros where user_id=uid and cpf=cpf_value for update;
 if exists(select 1 from public.crm_margens_vinculo
  where user_id=uid and cpf=cpf_value and convenio=agreement and (matricula=registration or matricula='' or registration='') and produto=product
   and (instituicao=institution or institution='informada') and observado_em>observed) then return false;end if;
 insert into public.crm_margens_vinculo values(uid,cpf_value,agreement,registration,institution,product,amount,observed,source)
 on conflict(user_id,cpf,convenio,matricula,instituicao,produto)
 do update set valor=excluded.valor,observado_em=excluded.observado_em,origem=excluded.origem
 where crm_margens_vinculo.observado_em<=excluded.observado_em;
 return found;
end $$;
revoke all on function apoiarcred_private.crm_store_margin(uuid,text,text,text,text,text,numeric,timestamptz,text) from public,anon,authenticated;

create function apoiarcred_private.crm_import_errors(p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare errors jsonb:='[]'; row jsonb; idx bigint; field record; message text; fields text[]; services text[];
begin
 select servicos into services from public.crm_catalogo_importacao where uf=p_uf and codigo=p_convenio;
 if services is null or p_servicos is null or array_position(p_servicos,null) is not null or not p_servicos<@services then
  return '[{"linha":0,"mensagem":"Convênio ou consultas incompatíveis."}]';end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then return '[{"linha":0,"mensagem":"Envie uma lista de clientes."}]';end if;
 if jsonb_array_length(p_rows) not between 1 and 10000 then return '[{"linha":0,"mensagem":"Envie de 1 a 10.000 registros."}]';end if;
 for row,idx in select value,ordinality from jsonb_array_elements(p_rows) with ordinality loop
  message:=null;
  begin
   if jsonb_typeof(row)<>'object' then raise exception 'Registro deve ser um objeto.';end if;
   if jsonb_typeof(row->'cpf') is distinct from 'string' or coalesce(row->>'cpf','')!~'^[0-9]{11}$' or row->>'cpf'='00000000000' then raise exception 'CPF inválido.';end if;
   if length(row->>'nome')>160 or coalesce(row->>'telefone','')!~'^([0-9]{10,13})?$' then raise exception 'Nome ou telefone inválido.';end if;
   if 'digimais_saldo'=any(p_servicos) and (nullif(btrim(row->>'nome'),'') is null or nullif(row->>'telefone','') is null) then raise exception 'Digi+ exige nome e telefone com DDD.';end if;
   if length(row->>'numero_matricula')>256 or length(row->>'instituicao')>80 then raise exception 'Matrícula ou instituição excede o limite.';end if;
   if row->>'data_nascimento' is not null then
    if row->>'data_nascimento' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Nascimento deve usar AAAA-MM-DD.';end if;
    perform (row->>'data_nascimento')::date;
   end if;
   if row->>'data_dados' is not null then
    if row->>'data_dados' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}(T.*(Z|[+-][0-9]{2}:[0-9]{2}))?$'
      or (row->>'data_dados')::timestamptz>now() then raise exception 'Data dos dados inválida ou futura.';end if;
   end if;
   for field in select * from jsonb_each(row) where value<>'null'::jsonb loop
    if field.key in ('margem_livre','margem_emprestimo','margem_cartao','margem_beneficio','margem_consignado','saque_amigoz_valor') then
     if jsonb_typeof(field.value)<>'number' then raise exception 'O campo % deve ser numérico.',field.key;end if;
     if abs(field.value::text::numeric)>999999999999.99 then raise exception 'Valor fora do limite em %.',field.key;end if;
     if field.key like 'margem_%' and not services && array['amigoz_margem','consigx_margem'] then raise exception 'Margem indisponível neste convênio.';end if;
    elsif field.key in ('nome','telefone','numero_matricula','instituicao','data_dados','data_nascimento') and jsonb_typeof(field.value)<>'string' then
     raise exception 'O campo % deve ser texto.',field.key;
    end if;
   end loop;
   if row->'saque_amigoz_elegivel' is not null and row->'saque_amigoz_elegivel'<>'null'::jsonb
    and jsonb_typeof(row->'saque_amigoz_elegivel')<>'boolean' then raise exception 'Elegibilidade Amigoz deve ser booleana.';end if;
   if (row->>'saque_amigoz_valor')::numeric<0 or (row->>'saque_amigoz_elegivel'='false' and (row->>'saque_amigoz_valor')::numeric>0) then raise exception 'Saque Amigoz incompatível.';end if;
   if (row->>'saque_amigoz_valor' is not null or row->>'saque_amigoz_elegivel' is not null) and not 'amigoz_saque'=any(services) then raise exception 'Saque Amigoz indisponível neste convênio.';end if;
  exception when others then message:=sqlerrm;end;
  if message is not null then errors:=errors||jsonb_build_array(jsonb_build_object('linha',idx+1,'mensagem',message));end if;
 end loop;
 select errors||coalesce(jsonb_agg(jsonb_build_object('linha',ord+1,'mensagem','CPF, matrícula e instituição repetidos.')),'[]')
 into errors from (
  select ord,row_number() over(partition by x->>'cpf',coalesce(x->>'numero_matricula',''),coalesce(nullif(x->>'instituicao',''),'informada') order by ord) n
  from jsonb_array_elements(p_rows) with ordinality r(x,ord)
 ) d where n>1;
 return errors;
end $$;
revoke all on function apoiarcred_private.crm_import_errors(text,text,text[],jsonb) from public,anon,authenticated;

create or replace function apoiarcred_private.crm_import_and_start(p_request_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); fingerprint text; previous public.crm_import_requests;
 count_clients integer; n integer=0; cid uuid; lots jsonb='[]'; mode text;
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
   perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,now(),
    jsonb_build_object('margem_emprestimo',loan,'margem_cartao',card),case when greatest(loan,card)>20 then 'margem' end);
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
   perform apoiarcred_private.crm_consolidar(uid,imported.cpf,ref,observed,
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
 result=jsonb_build_object('id',p_request_id,'uf',p_uf,'convenio',p_convenio,'responsavel',uid,'status','concluida','registros',jsonb_array_length(p_rows),'margens_atualizadas',accepted,'dados_antigos_ignorados',ignored,'clientes',count_clients,'consultas',n,'campanhas',lots);
 insert into public.crm_import_requests(user_id,request_id,fingerprint,response) values(uid,p_request_id,fingerprint,result);
 return result;
end $$;

alter table public.crm_import_requests add column arquivo text;

create function public.crm_preview_import(p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; previous jsonb; counts jsonb; errors jsonb; uid uuid:=auth.uid();
begin
 if uid is null then raise insufficient_privilege;end if;
 errors:=apoiarcred_private.crm_import_errors(p_uf,p_convenio,p_servicos,p_rows);
 if errors<>'[]' then return jsonb_build_object('valido',false,'erros',errors);end if;
 select coalesce(jsonb_object_agg(id,sinais_consulta),'{}') into previous
 from public.crm_oportunidades where user_id=uid and cpf in(select x->>'cpf' from jsonb_array_elements(p_rows) x);
 begin
  result:=apoiarcred_private.crm_import_and_start(gen_random_uuid(),p_uf,p_convenio,p_servicos,p_rows);
  select coalesce(jsonb_agg(t),'[]') into counts from (
   select produto,count(*) filter(where not previous ? id::text) criadas,
    count(*) filter(where previous ? id::text and previous->id::text is distinct from sinais_consulta) atualizadas
   from public.crm_oportunidades
   where user_id=uid and automatica and cpf in(select x->>'cpf' from jsonb_array_elements(p_rows) x)
   group by produto
  ) t;
  result:=(result-'id'-'campanhas')||jsonb_build_object('oportunidades',counts,'valido',true);
  raise exception using errcode='ZP001',message='preview rollback';
 exception when sqlstate 'ZP001' then null;
 when raise_exception or insufficient_privilege then
  result:=jsonb_build_object('valido',false,'erros',jsonb_build_array(jsonb_build_object('linha',0,'mensagem',sqlerrm)));
 end;
 return result;
end $$;
revoke all on function public.crm_preview_import(text,text,text[],jsonb) from public,anon;
grant execute on function public.crm_preview_import(text,text,text[],jsonb) to authenticated,service_role;

create function public.crm_confirm_import(p_request_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb,p_arquivo text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=apoiarcred_private.crm_import_and_start(p_request_id,p_uf,p_convenio,p_servicos,p_rows);
 update public.crm_import_requests set arquivo=left(p_arquivo,255)
 where user_id=auth.uid() and request_id=p_request_id and arquivo is null;
 return result;
end $$;
revoke all on function public.crm_confirm_import(uuid,text,text,text[],jsonb,text) from public,anon;
grant execute on function public.crm_confirm_import(uuid,text,text,text[],jsonb,text) to authenticated,service_role;

create function public.crm_import_history(p_offset integer default 0,p_id uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(r order by created_at desc,id desc),'[]') from (
 select request_id as id,created_at,arquivo,response from public.crm_import_requests
 where user_id=auth.uid() and (p_id is null or request_id=p_id) order by created_at desc,request_id desc
 offset greatest(p_offset,0) limit 50
 ) r
$$;
revoke all on function public.crm_import_history(integer,uuid) from public,anon;
grant execute on function public.crm_import_history(integer,uuid) to authenticated,service_role;
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
   'campos_opcionais',array['nome','telefone','numero_matricula','data_nascimento','data_dados']
    || case when c.servicos && array['amigoz_margem','consigx_margem'] then array['margem_emprestimo','margem_cartao','margem_beneficio','margem_consignado','instituicao'] else '{}'::text[] end
    || case when 'amigoz_saque'=any(c.servicos) then array['saque_amigoz_elegivel','saque_amigoz_valor'] else '{}'::text[] end,
   'requisitos_servicos',case when 'digimais_saldo'=any(c.servicos) then '{"digimais_saldo":["cpf","nome","telefone"]}'::jsonb else '{}'::jsonb end
  ) order by c.uf,c.nome),'[]') into data
  from public.crm_catalogo_importacao c where not (p ? 'uf') or c.uf=upper(p->>'uf');
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if method='GET' and (route='/clientes/importacoes' or route ~ '^/clientes/importacoes/[0-9a-fA-F-]{36}$') then
  previous_sub:=current_setting('request.jwt.claim.sub',true);
  perform set_config('request.jwt.claim.sub',uid::text,true);
  data:=public.crm_import_history(coalesce((p->>'offset')::integer,0),nullif(split_part(route,'/',4),'')::uuid);
  perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  if route='/clientes/importacoes' then return apoiarcred_private.api_response(200,jsonb_build_object('data',data));end if;
  if data='[]' then return apoiarcred_private.api_error(404,'not_found','Importação não encontrada.');end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data->0));
 end if;
 if method='POST' and route in ('/clientes/importacoes','/clientes/importacoes/previa') then
  if jsonb_typeof(p->'clientes') is distinct from 'array'
     or jsonb_typeof(coalesce(p->'servicos','[]')) is distinct from 'array'
     or coalesce(p->>'uf','') !~ '^[A-Za-z]{2}$' or coalesce(p->>'convenio','')='' then
   return apoiarcred_private.api_error(422,'invalid_import','Informe UF, convênio, clientes e uma lista opcional de serviços.');
  end if;
  if jsonb_array_length(p->'clientes') not between 1 and 10000 or exists (select 1 from jsonb_array_elements(p->'clientes') x where jsonb_typeof(x)<>'object') then
   return apoiarcred_private.api_error(422,'invalid_import','Envie entre 1 e 10.000 objetos de clientes.');
  end if;
  select jsonb_agg(case when jsonb_typeof(x->'cpf')='string'
   then x||jsonb_build_object('cpf',regexp_replace(x->>'cpf','[. -]','','g')) else x end order by ord) into data
  from jsonb_array_elements(p->'clientes') with ordinality as rows(x,ord);
  previous_sub:=current_setting('request.jwt.claim.sub',true);
  perform set_config('request.jwt.claim.sub',uid::text,true);
  begin
   if route='/clientes/importacoes/previa' then
    data:=public.crm_preview_import(upper(p->>'uf'),p->>'convenio',
     array(select jsonb_array_elements_text(coalesce(p->'servicos','[]'))),data);
   else
    declare errors jsonb;
    begin
     errors:=apoiarcred_private.crm_import_errors(upper(p->>'uf'),p->>'convenio',
      array(select jsonb_array_elements_text(coalesce(p->'servicos','[]'))),data);
     if errors<>'[]' then
      perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
      return apoiarcred_private.api_response(422,jsonb_build_object('error',jsonb_build_object('code','invalid_import','message','Confira os registros enviados.','details',errors)));
     end if;
     data:=public.crm_confirm_import(gen_random_uuid(),upper(p->>'uf'),p->>'convenio',
      array(select jsonb_array_elements_text(coalesce(p->'servicos','[]'))),data,p->>'arquivo');
    end;
   end if;
  exception when insufficient_privilege then
   perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
   return apoiarcred_private.api_error(403,'import_not_allowed','A conta não possui permissão para esta importação ou consulta.');
  when raise_exception or invalid_datetime_format or datetime_field_overflow then
   perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
   return apoiarcred_private.api_error(422,'invalid_import',sqlerrm);
  end;
  perform set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  return apoiarcred_private.api_response(case when route='/clientes/importacoes/previa' then 200 else 201 end,jsonb_build_object('data',data));
 end if;
 return apoiarcred_private.api_route_oportunidades(uid,method,route,p);
end $$;

grant execute on function apoiarcred_private.crm_import_errors(text,text,text[],jsonb) to service_role;

create function apoiarcred_private.crm_sync_margin_snapshot()
returns trigger language plpgsql security definer set search_path='' as $$
declare item record;
begin
 if new.tipo<>'margem' or new.convenio is null or new.instituicao not in ('amigoz','consigx') then return new;end if;
 if jsonb_typeof(new.dados)='array' then
  for item in select coalesce(x->>'numeroMatricula',x->>'numero_matricula','') matricula,
   case x->>'idProduto' when '7' then 'beneficio' when '15' then 'consignado' else 'cartao' end produto,
   (x->>'margem_atual')::numeric valor from jsonb_array_elements(new.dados) x
   where jsonb_typeof(x->'margem_atual')='number'
  loop
   perform apoiarcred_private.crm_store_margin(new.user_id,new.cpf,new.convenio,item.matricula,new.instituicao,item.produto,item.valor,new.registrado_em,'consulta');
  end loop;
 elsif jsonb_typeof(new.dados)='object' then
  for item in select * from (values ('emprestimo',new.dados->'margem_emprestimo'),('cartao',new.dados->'margem_cartao')) m(produto,valor)
   where jsonb_typeof(valor)='number' loop
   perform apoiarcred_private.crm_store_margin(new.user_id,new.cpf,new.convenio,
    coalesce(new.dados->>'matricula',new.dados->>'numero_matricula',''),new.instituicao,item.produto,item.valor::text::numeric,new.registrado_em,'consulta');
  end loop;
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.crm_sync_margin_snapshot() from public,anon,authenticated;
create trigger crm_sync_margin_snapshot after insert or update on public.crm_dados_cliente
 for each row execute function apoiarcred_private.crm_sync_margin_snapshot();

insert into public.crm_margens_vinculo(user_id,cpf,convenio,matricula,instituicao,produto,valor,observado_em,origem)
select d.user_id,d.cpf,d.convenio,'',d.instituicao,m.produto,m.valor::text::numeric,d.registrado_em,d.origem
from public.crm_dados_cliente d cross join lateral
 (values ('emprestimo',d.dados->'margem_emprestimo'),('cartao',d.dados->'margem_cartao')) m(produto,valor)
where d.tipo='margem' and d.convenio is not null and jsonb_typeof(m.valor)='number'
on conflict do nothing;

notify pgrst,'reload schema';
commit;
