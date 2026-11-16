CREATE OR REPLACE FUNCTION apoiarcred_private.api_route(uid uuid, method text, route text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare parts text[]=string_to_array(trim(both '/' from route),'/');
 data jsonb; response jsonb; card_id uuid; client_id uuid; cpf_value text; phone_value text; matches uuid[]; code text;
 stage_id uuid; previous_id uuid; total integer; page integer; size integer;
begin
 perform set_config('apoiarcred.crm_origem','api',true);
 if route='/crm/etapas' and method='GET' then
  perform set_config('request.jwt.claim.sub',uid::text,true);
  select coalesce(jsonb_agg(to_jsonb(e)-'user_id' order by e.posicao,e.id),'[]') into data from public.crm_listar_etapas() e;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if (route='/crm/etapas' and method='POST') or (route ~ '^/crm/etapas/[0-9a-fA-F-]{36}$' and method='PATCH') then
  perform set_config('request.jwt.claim.sub',uid::text,true);
  data=public.crm_salvar_etapa(nullif(parts[3],'')::uuid,p);
  if data is null then return apoiarcred_private.api_error(404,'not_found','Etapa não encontrada.');end if;
  return apoiarcred_private.api_response(case when method='POST' then 201 else 200 end,jsonb_build_object('data',data));
 end if;
 if route ~ '^/oportunidades/[0-9a-fA-F-]{36}/etapa$' and method='POST' then
  card_id=parts[2]::uuid;
  if p ? 'etapa_id' or p ? 'etapa_original_id' then
   stage_id=(p->>'etapa_id')::uuid;previous_id=(p->>'etapa_original_id')::uuid;
  else
   select id into stage_id from public.crm_etapas where user_id=uid and codigo=p->>'etapa' and not arquivada;
   select id into previous_id from public.crm_etapas where user_id=uid and codigo=p->>'etapa_original';
  end if;
  perform set_config('request.jwt.claim.sub',uid::text,true);
  data=public.crm_mover_etapa(card_id,stage_id,previous_id);
  if data is null then return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.');end if;
  if data ? 'conflito' then
   return apoiarcred_private.api_response(409,jsonb_build_object('error',jsonb_build_object('code','stage_changed',
    'message','A etapa mudou. Consulte a oportunidade novamente.','details',data-'conflito')));
  end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if (route='/clientes/buscar' and method='POST') or (route ~ '^/clientes/[0-9a-fA-F-]{36}$' and method='GET') then
  if method='POST' then
   if (nullif(btrim(p->>'cpf'),'') is null) = (nullif(btrim(p->>'telefone'),'') is null) then
    return apoiarcred_private.api_error(422,'invalid_search','Informe CPF ou telefone, um por busca.');
   end if;
   if nullif(btrim(p->>'cpf'),'') is not null then
    cpf_value=regexp_replace(p->>'cpf','[^0-9]','','g');
    if cpf_value!~'^[0-9]{11}$' then return apoiarcred_private.api_error(422,'invalid_cpf','Informe CPF com 11 dígitos.');end if;
   else
    phone_value=regexp_replace(regexp_replace(p->>'telefone','[^0-9]','','g'),'^55([0-9]{10,11})$','\1');
    if phone_value!~'^[0-9]{10,11}$' then
     return apoiarcred_private.api_error(422,'invalid_phone','Informe telefone com DDD.');
    end if;
    select array_agg(m.cliente_id) into matches from (
     select c.cliente_id from public.crm_cadastros c
     where c.user_id=uid
      and regexp_replace(regexp_replace(c.telefone,'[^0-9]','','g'),'^55([0-9]{10,11})$','\1')=phone_value
     limit 2
    ) m;
    if cardinality(matches)>1 then
     return apoiarcred_private.api_error(409,'ambiguous_phone','Há mais de um cliente com esse telefone. Busque pelo CPF.');
    end if;
    client_id=matches[1];
   end if;
  else client_id=parts[2]::uuid;end if;
  data=apoiarcred_private.crm_cliente_perfil(uid,cpf_value,client_id);
  if data is null then return apoiarcred_private.api_error(404,'not_found','Cliente não encontrado.');end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;
 if method='GET' and (route ~ '^/clientes/[0-9a-fA-F-]{36}/consultas$' or route ~ '^/oportunidades/[0-9a-fA-F-]{36}/movimentacoes$') then
  page=coalesce((p->>'page')::integer,1);size=coalesce((p->>'page_size')::integer,50);
  if page not between 1 and 1000000 or size not between 1 and 100 then return apoiarcred_private.api_error(422,'invalid_filter','Paginação inválida.');end if;
  if parts[1]='clientes' then
   select cpf into cpf_value from public.crm_cadastros where user_id=uid and cliente_id=parts[2]::uuid;
   if not found then return apoiarcred_private.api_error(404,'not_found','Cliente não encontrado.');end if;
   select count(*) into total from public.crm_consultas where user_id=uid and cpf=cpf_value;
   select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') into data from (
    select id,servico,convenio,status,created_at,consultado_em,matricula,saldo_liquidacao,valor_parcela,emprestimo_disponivel,cartao_disponivel
    from public.crm_consultas where user_id=uid and cpf=cpf_value order by created_at desc,id desc offset (page-1)*size limit size
   ) x;
  else
   card_id=parts[2]::uuid;
   if not exists(select 1 from public.crm_oportunidades where user_id=uid and id=card_id) then return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.');end if;
   select count(*) into total from public.crm_movimentacoes where user_id=uid and oportunidade_id=card_id;
   select coalesce(jsonb_agg(to_jsonb(x)-'user_id' order by x.alterado_em desc,x.id desc),'[]') into data from (
    select * from public.crm_movimentacoes where user_id=uid and oportunidade_id=card_id order by alterado_em desc,id desc offset (page-1)*size limit size
   ) x;
  end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 if method='GET' and route='/oportunidades' and p ? 'etapa_id' then
  select codigo into code from public.crm_etapas where user_id=uid and id=(p->>'etapa_id')::uuid and not arquivada;
  if not found then return apoiarcred_private.api_error(422,'invalid_stage','Etapa indisponível.');end if;
  p=p||jsonb_build_object('etapa',code);
 end if;
 response=apoiarcred_private.api_route_antes_etapas(uid,method,route,p);
 if method='GET' and route ~ '^/oportunidades/[0-9a-fA-F-]{36}$' and p->>'include'='cliente'
  and response->>'status'='200' then
  client_id=(response#>>'{body,data,cliente_id}')::uuid;
  data=apoiarcred_private.crm_cliente_perfil(uid,null,client_id);
  response=jsonb_set(response,'{body,data,cliente}',coalesce(data,'null'::jsonb));
 end if;
 return response;
exception when invalid_parameter_value then
 return apoiarcred_private.api_error(422,'validation_error',sqlerrm);
end $function$;
