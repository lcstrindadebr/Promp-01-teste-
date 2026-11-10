begin;
alter function apoiarcred_private.api_route(uuid,text,text,jsonb) rename to api_route_legacy;

create function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 stages text[]:=array['novo','exportada','contato','simulacao','negociacao','ganho','perdido'];
 open_stages text[]:=array['novo','contato','simulacao','negociacao'];
 products text[]:=array['margem','recompra','saque'];
 selected text[];
 stage text;
 opportunity_id uuid;
 data jsonb;
 total integer;
 page_no integer;
 page_size integer;
begin
 if route <> '/oportunidades' and route not like '/oportunidades/%' then
  return apoiarcred_private.api_route_legacy(uid,method,route,p);
 end if;

 if method='GET' and route='/oportunidades' then
  stage:=p->>'etapa';
  selected:=string_to_array(p->>'tipos',',');
  page_no:=coalesce((p->>'page')::integer,1);
  page_size:=coalesce((p->>'page_size')::integer,50);
  if (stage is not null and not stage=any(stages)) or (selected is not null and not selected<@products)
   or page_no not between 1 and 1000000 or page_size not between 1 and 100
   or coalesce(p->>'exportaveis','false') not in ('true','false') then
   return apoiarcred_private.api_error(422,'invalid_filter','Confira etapa, tipos, exportaveis e paginação.');
  end if;
  with filtered as materialized (
   select c.* from public.crm_opportunity_cards c
   where c.user_id=uid and (stage is null or c.etapa=stage)
    and (selected is null or c.produto=any(selected))
    and (coalesce(p->>'exportaveis','false')='false' or c.etapa=any(open_stages))
  )
  select (select count(*) from filtered),
   coalesce((select jsonb_agg(to_jsonb(x)-'user_id' order by x.created_at desc,x.id)
    from (select * from filtered order by created_at desc,id limit page_size offset (page_no-1)*page_size) x),'[]')
  into total,data;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page_no,'page_size',page_size,'total',total)));
 end if;

 if method='GET' and route ~ '^/oportunidades/[0-9a-fA-F-]{36}$' then
  opportunity_id:=split_part(route,'/',3)::uuid;
  select to_jsonb(c)-'user_id' into data from public.crm_opportunity_cards c where c.user_id=uid and c.id=opportunity_id;
  if not found then return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.'); end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;

 if method='POST' and route ~ '^/oportunidades/[0-9a-fA-F-]{36}/etapa$' then
  opportunity_id:=split_part(route,'/',3)::uuid;
  stage:=p->>'etapa';
  if stage is null or not stage=any(stages) or (p->>'etapa_original') is null or not (p->>'etapa_original')=any(stages) then
   return apoiarcred_private.api_error(422,'invalid_stage','Informe etapa e etapa_original válidas.');
  end if;
  update public.crm_oportunidades o set etapa=stage
  where o.user_id=uid and o.id=opportunity_id and o.etapa=p->>'etapa_original'
  returning jsonb_build_object('id',o.id,'etapa',o.etapa) into data;
  if not found then
   if exists(select 1 from public.crm_oportunidades o where o.user_id=uid and o.id=opportunity_id) then
    return apoiarcred_private.api_error(409,'stage_changed','A etapa mudou. Consulte a oportunidade novamente.');
   end if;
   return apoiarcred_private.api_error(404,'not_found','Oportunidade não encontrada.');
  end if;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data));
 end if;

 if method='POST' and route='/oportunidades/exportacao' then
  if jsonb_typeof(p->'itens') is distinct from 'array' then
   return apoiarcred_private.api_error(422,'invalid_items','Informe itens com id e etapa.');
  end if;
  if jsonb_array_length(p->'itens') not between 1 and 500 or exists(
   select 1 from jsonb_to_recordset(p->'itens') item(id uuid,etapa text)
   where item.id is null or item.etapa is null or not item.etapa=any(open_stages)
  ) then
   return apoiarcred_private.api_error(422,'invalid_items','Envie de 1 a 500 itens com id e etapa aberta.');
  end if;
  with moved as (
   update public.crm_oportunidades o set etapa='exportada'
   from jsonb_to_recordset(p->'itens') item(id uuid,etapa text)
   where o.user_id=uid and o.id=item.id and o.etapa=item.etapa and o.etapa=any(open_stages)
   returning o.id
  )
  select count(*),coalesce(jsonb_agg(id order by id),'[]') into total,data from moved;
  return apoiarcred_private.api_response(200,jsonb_build_object('movidas',total,'ids',data));
 end if;
 return apoiarcred_private.api_error(404,'route_not_found','Rota não encontrada.');
end $$;
revoke all on function apoiarcred_private.api_route(uuid,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.api_route(uuid,text,text,jsonb) to service_role;
notify pgrst,'reload schema';
commit;
