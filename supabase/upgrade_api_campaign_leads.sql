-- Full campaign lead listing and a dedicated status route.
create or replace function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
<<vars>>
declare parts text[]=string_to_array(trim(both '/' from route),'/'); cid uuid; item_id uuid; c record;
 service text; convenio text; lead_status text; lots text; jobs text; item jsonb; idx integer=0; cpf text; nome text; phone text; ref text;
 accepted jsonb='[]';duplicates jsonb='[]';rejected jsonb='[]';data jsonb;counts jsonb; total integer; n integer;
 page integer=greatest(1,coalesce((p->>'page')::integer,1));size integer=least(100,greatest(1,coalesce((p->>'page_size')::integer,50)));
begin
 if method='GET' and route='/servicos' then return apoiarcred_private.api_response(200,'{"data":[{"id":"digimais_saldo_parcela","campos_obrigatorios":["nome","cpf","telefone"]},{"id":"tjba_margem","campos_obrigatorios":["cpf"],"convenios":["tjba","dpeba","embasa","saeb","suprev"]}]}');end if;
 if method='GET' and route='/campanhas' then
  select count(*) into total from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean);
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean) order by created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 if method='POST' and route in ('/campanhas','/consultas') then
  service=coalesce(p->>'servico','digimais_saldo_parcela');convenio=coalesce(p->>'convenio','tjba');
  if service not in ('digimais_saldo_parcela','tjba_margem') or (service='tjba_margem' and convenio not in ('tjba','dpeba','embasa','saeb','suprev')) then return apoiarcred_private.api_error(422,'invalid_service','Serviço ou convênio inválido.');end if;
  nome=case when route='/consultas' then 'Consulta individual via API' else btrim(p->>'nome') end;
  if coalesce(length(nome),0) not between 1 and 160 then return apoiarcred_private.api_error(422,'invalid_name','Informe nome de campanha com até 160 caracteres.');end if;
  lots=case when service='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;
  jobs=case when service='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  -- Individual input validated before creating its lot; all changes atomic.
  if route='/consultas' then
   item=p;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');
   if cpf!~'^[0-9]{11}$' or (service='digimais_saldo_parcela' and (coalesce(length(btrim(item->>'nome')),0) not between 1 and 160 or phone!~'^[0-9]{10,13}$')) or length(coalesce(item->>'referencia_externa',''))>160 then return apoiarcred_private.api_error(422,'invalid_lead','CPF de 11 dígitos; Digi+ exige nome e telefone com DDD.');end if;
  end if;
  if service='tjba_margem' then
   insert into public.tjba_lotes(user_id,nome,tipo,convenio,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,convenio,route='/campanhas') returning id into cid;
  else
   insert into public.consulta_lotes(user_id,nome,tipo,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,route='/campanhas') returning id into cid;
  end if;
  if route='/consultas' then
   execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(btrim(item->>'nome'),''),'CPF '||cpf),cpf,phone,item->>'referencia_externa';
   return apoiarcred_private.api_response(202,jsonb_build_object('id',item_id,'campanha_id',cid,'status','aguardando'));
  end if;
  return apoiarcred_private.api_response(201,jsonb_build_object('id',cid,'nome',nome,'servico',service,'convenio',case when service='tjba_margem' then convenio else null end,'paused',true));
 end if;
 -- Full campaign reads take one snapshot and use the same owner and token checks.
 if method='GET' and parts[1]='campanhas' and parts[3]='leads' and
    ((cardinality(parts)=3 and p ? 'all') or (cardinality(parts)=5 and parts[4]='status')) then
  if cardinality(parts)=5 then
   if p<>'{}'::jsonb then
    return apoiarcred_private.api_error(422,'invalid_filter','Informe o status na rota, sem filtros adicionais.');
   end if;
   lead_status=parts[5];
  else
   if p->>'all' is distinct from 'true' or p ? 'page' or p ? 'page_size' then
    return apoiarcred_private.api_error(422,'invalid_filter','Use all=true sem page ou page_size.');
   end if;
   lead_status=p->>'status';
  end if;
  if lead_status is not null and lead_status not in
     ('aguardando','processando','concluida','nao_cliente','nao_localizado','nao_encontrado','erro','revisao','interrompida') then
   return apoiarcred_private.api_error(422,'invalid_status','Status de lead inválido.');
  end if;
  cid=parts[2]::uuid;
  if not exists(select 1 from apoiarcred_private.api_campaign_rows
                where id=cid and user_id=uid and tipo='campanha') then
   return apoiarcred_private.api_error(404,'not_found','Campanha não encontrada.');
  end if;
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id' order by x.queue_order,x.created_at desc,x.id),'[]'::jsonb)
  into data
  from apoiarcred_private.api_lead_rows x
  where x.user_id=uid and x.campanha_id=cid and (lead_status is null or x.status=lead_status);
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'total',jsonb_array_length(data)));
 end if;
 if parts[1]='campanhas' and cardinality(parts) between 2 and 3 then
  cid=parts[2]::uuid;
  select * into c from apoiarcred_private.api_campaign_rows where id=cid and user_id=uid and tipo='campanha';
  if not found then return apoiarcred_private.api_error(404,'not_found','Campanha não encontrada.');end if;
  lots=case when c.servico='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;jobs=case when c.servico='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  if method='GET' and cardinality(parts)=2 then
   select jsonb_build_object('total',count(*),'clientes',count(*) filter(where status='concluida'),'nao_clientes',count(*) filter(where status in ('nao_cliente','nao_localizado','nao_encontrado')),'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'),'interrompidas',count(*) filter(where status='interrompida'),'aguardando',count(*) filter(where status='aguardando'),'processando',count(*) filter(where status='processando')) into counts from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid;
   return apoiarcred_private.api_response(200,(to_jsonb(c)-'user_id')||jsonb_build_object('relatorio',counts));
  elsif method='POST' then
   execute format('select paused from public.%I where id=$1 and user_id=$2 for update',lots) into c.paused using cid,uid;
   if parts[3] in ('iniciar','pausar') then
    execute format('update public.%I set paused=$1 where id=$2 and user_id=$3',lots) using parts[3]='pausar',cid,uid;
    return apoiarcred_private.api_response(200,jsonb_build_object('id',cid,'paused',parts[3]='pausar'));
   elsif parts[3]='leads' then
    if not c.paused then return apoiarcred_private.api_error(409,'campaign_running','Pause a campanha antes de adicionar leads.');end if;
    if jsonb_typeof(p->'leads') is distinct from 'array' then return apoiarcred_private.api_error(422,'invalid_leads','Envie leads como uma lista.');end if;
    if jsonb_array_length(p->'leads')=0 then return apoiarcred_private.api_error(422,'invalid_leads','Envie pelo menos um lead.');end if;
    if jsonb_array_length(p->'leads')>1000 and not apoiarcred_private.is_admin(uid) then return apoiarcred_private.api_error(422,'invalid_leads','Envie de 1 a 1000 leads.');end if;
    for item in select value from jsonb_array_elements(p->'leads') loop
     idx=idx+1;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');nome=btrim(item->>'nome');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');ref=item->>'referencia_externa';
     if jsonb_typeof(item) is distinct from 'object' or cpf!~'^[0-9]{11}$' or coalesce(length(nome),0)>160 or length(coalesce(ref,''))>160 or (c.servico='digimais_saldo_parcela' and (coalesce(length(nome),0)=0 or phone!~'^[0-9]{10,13}$')) then
      rejected=rejected||jsonb_build_array(jsonb_build_object('linha',idx,'code','invalid_lead','message','Confira CPF, nome, telefone e referência.'));continue;
     end if;
     -- Parent row lock serializes API inserts with API pause/start; no historical duplicates are deleted.
     if exists(select 1 from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid and api_lead_rows.cpf=vars.cpf) then
      duplicates=duplicates||jsonb_build_array(jsonb_build_object('linha',idx,'cpf',cpf));continue;
     end if;
     execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(nome,''),'CPF '||cpf),cpf,phone,ref;
     accepted=accepted||jsonb_build_array(jsonb_build_object('linha',idx,'id',item_id,'cpf',cpf));
    end loop;
    return apoiarcred_private.api_response(200,jsonb_build_object('accepted',accepted,'duplicates',duplicates,'rejected',rejected));
   elsif parts[3]='repetir-revisoes' then
    if c.servico='tjba_margem' then
     update public.tjba_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,matricula=null,tipo_servidor=null,situacao_atual=null,emprestimo_disponivel=null,cartao_disponivel=null,tjba_status=null,resultado_tjba=null where lote_id=cid and user_id=uid and status in ('erro','revisao');
    else
     update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,saldo_liquidacao=null,total_parcelas=null,valor_parcela=null,resultado_saldo=null,resultado_parcela=null where lote_id=cid and user_id=uid and status in ('erro','revisao','interrompida');
    end if;
    get diagnostics n=row_count;return apoiarcred_private.api_response(202,jsonb_build_object('reenfileirados',n,'paused',c.paused));
   end if;
  end if;
 end if;
 if (method='GET' and parts[1] in ('leads','consultas') and cardinality(parts)=2) then
  select to_jsonb(x)-'user_id' into data from apoiarcred_private.api_lead_rows x where id=parts[2]::uuid and user_id=uid;
  if data is null then return apoiarcred_private.api_error(404,'not_found','Registro não encontrado.');end if;
  return apoiarcred_private.api_response(200,data);
 end if;
 if (method='POST' and route='/leads/buscar') or (method='GET' and parts[1]='campanhas' and parts[3]='leads' and cardinality(parts)=3) then
  cpf=case when method='POST' then regexp_replace(coalesce(p->>'cpf',''),'[^0-9]','','g') else null end;
  if method='POST' and cpf!~'^[0-9]{11}$' then return apoiarcred_private.api_error(422,'invalid_cpf','Informe CPF com 11 dígitos.');end if;
  cid=case when method='GET' then parts[2]::uuid else nullif(p->>'campanha_id','')::uuid end;
  select count(*) into total from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status');
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status') order by case when method='GET' then queue_order end,created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 return apoiarcred_private.api_error(404,'route_not_found','Rota não encontrada.');
end $$;
