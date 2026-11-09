-- Track outcomes as workers finish. The campaign row serializes concurrent completions.
alter table public.consulta_jobs drop constraint consulta_jobs_status_check;
alter table public.consulta_jobs add constraint consulta_jobs_status_check check(status in
 ('aguardando','processando','concluida','nao_localizado','nao_cliente','erro','revisao','interrompida'));

alter table public.consulta_lotes add column failure_streak integer not null default 0,
 add column auto_paused boolean not null default false;
alter table public.tjba_lotes add column failure_streak integer not null default 0,
 add column auto_paused boolean not null default false;

create function apoiarcred_private.track_campaign_failures() returns trigger
language plpgsql security definer set search_path='' as $$
declare failed boolean := new.status in ('erro','revisao','interrompida');
begin
 if old.status<>'processando' or new.status in ('processando','aguardando') then return new;end if;
 if tg_table_name='consulta_jobs' then
  update public.consulta_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 else
  update public.tjba_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 end if;
 return new;
end $$;

create function apoiarcred_private.reset_campaign_failures() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.paused and not new.paused then
  new.failure_streak=0;
  new.auto_paused=false;
 end if;
 return new;
end $$;

revoke all on function apoiarcred_private.track_campaign_failures() from public,anon,authenticated;
revoke all on function apoiarcred_private.reset_campaign_failures() from public,anon,authenticated;
create trigger track_campaign_failures after update of status on public.consulta_jobs
 for each row execute function apoiarcred_private.track_campaign_failures();
create trigger track_campaign_failures after update of status on public.tjba_jobs
 for each row execute function apoiarcred_private.track_campaign_failures();
create trigger reset_campaign_failures before update of paused on public.consulta_lotes
 for each row execute function apoiarcred_private.reset_campaign_failures();
create trigger reset_campaign_failures before update of paused on public.tjba_lotes
 for each row execute function apoiarcred_private.reset_campaign_failures();


create or replace function apoiarcred_private.retry_consulta_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare owner_id uuid := auth.uid(); retried integer;
begin
 if owner_id is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if not exists(select 1 from public.consulta_lotes where id=p_campaign_id and user_id=owner_id and tipo='campanha') then
  raise insufficient_privilege using message='Campanha não disponível para esta conta.';
 end if;
 update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,
  saldo_liquidacao=null,total_parcelas=null,valor_parcela=null,resultado_saldo=null,resultado_parcela=null,consultado_em=null,locked_at=null
 where lote_id=p_campaign_id and user_id=owner_id and status in ('erro','revisao','interrompida');
 get diagnostics retried = row_count;
 return retried;
end $$;

create or replace function apoiarcred_private.guard_partner_job() returns trigger language plpgsql security definer set search_path='' as $$
declare lot record;
begin
 if tg_op='UPDATE' then
  if new.user_id<>old.user_id or new.lote_id<>old.lote_id or new.servico<>old.servico then raise insufficient_privilege;end if;
  if not (new.status='aguardando' and old.status in ('erro','revisao','interrompida')) then return new;end if;
 end if;
 if tg_table_name='consulta_jobs' then select user_id,tipo,servico into lot from public.consulta_lotes where id=new.lote_id for share;
 else select user_id,tipo,servico into lot from public.tjba_lotes where id=new.lote_id for share;end if;
 if not found or lot.user_id<>new.user_id or lot.servico<>new.servico then raise insufficient_privilege;end if;
 perform apoiarcred_private.check_partner_access(new.user_id,lot.servico,lot.tipo,true);return new;
end $$;

create or replace function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
<<vars>>
declare parts text[]=string_to_array(trim(both '/' from route),'/'); cid uuid; item_id uuid; c record;
 service text; convenio text; lots text; jobs text; item jsonb; idx integer=0; cpf text; nome text; phone text; ref text;
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

create or replace function apoiarcred_private.wh_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb;lot record;result jsonb;client boolean;partial_result boolean;service_id text;begin
 r=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;service_id=r->>'servico';
 if tg_op='UPDATE' and new.status=old.status and new.consultado_em is not distinct from old.consultado_em then return new;end if;
 if tg_table_name='consulta_jobs' then select id,user_id,nome,tipo into lot from public.consulta_lotes where id=(r->>'lote_id')::uuid;
 else select id,user_id,nome,tipo into lot from public.tjba_lotes where id=(r->>'lote_id')::uuid;end if;
 if not found then return null;end if;
 if not apoiarcred_private.can_integrate(lot.user_id) then return null;end if;
 if tg_op='UPDATE' and old.status='processando' and new.status in ('concluida','nao_cliente','nao_localizado','nao_encontrado','erro','revisao','interrompida') and new.consultado_em is not null then
  result=apoiarcred_private.wh_result(service_id,r);client=apoiarcred_private.wh_client(service_id,new.status,result);partial_result=client is true and new.status<>'concluida';
  perform apoiarcred_private.wh_enqueue(new.user_id,'consulta:'||tg_table_name||':'||new.id||':'||new.attempts||':'||new.consultado_em::text,'consulta.finalizada',
   jsonb_build_object('occurred_at',new.consultado_em,'campanha',case when lot.tipo='campanha' then jsonb_build_object('id',lot.id,'nome',lot.nome) else null end,
   'consulta',jsonb_build_object('id',new.id,'referencia_externa',r->'referencia_externa','servico',service_id,'convenio',r->'convenio','cpf',new.cpf,'nome',new.nome,'telefone',new.telefone,'status',new.status,'cliente_identificado',client,'resultado_parcial',partial_result,'mensagem',left(new.message,1000),'resultado',result)),
   service_id,lot.id,lot.tipo,new.status,client,partial_result);
 end if;
 if lot.tipo='campanha' and exists(select 1 from apoiarcred_private.webhooks w where w.user_id=lot.user_id and w.active and 'campanha.finalizada'=any(w.events) and w.scope<>'individual' and (w.service is null or w.service=service_id) and (w.scope='all' or w.campaign_id=lot.id)) then
  insert into apoiarcred_private.webhook_campaign_dirty(service,campaign_id,user_id) values(service_id,lot.id,lot.user_id)
  on conflict(service,campaign_id) do update set touched_at=clock_timestamp(),checked_at=null;
 end if;
 return null;
end $$;

create or replace function apoiarcred_private.wh_campaigns() returns void language plpgsql security definer set search_path='' as $$
declare dirty record;lot record;r jsonb;pending integer;total integer;last_result timestamptz;begin
 delete from apoiarcred_private.webhook_campaign_dirty where not apoiarcred_private.can_integrate(user_id);
 for dirty in select * from apoiarcred_private.webhook_campaign_dirty order by checked_at nulls first,touched_at limit 20 for update skip locked loop
  select * into lot from apoiarcred_private.api_campaign_rows where id=dirty.campaign_id and user_id=dirty.user_id and tipo='campanha';
  if not found then delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=dirty.campaign_id;continue;end if;
  select count(*),count(*) filter(where status in ('aguardando','processando')),max(consultado_em),
   jsonb_build_object('total',count(*),'clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is true),
    'nao_clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is false),'indeterminados',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is null),
    'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'),'interrompidas',count(*) filter(where status='interrompida'))
   into total,pending,last_result,r from apoiarcred_private.api_lead_rows where campanha_id=lot.id and user_id=lot.user_id;
  if total>0 and pending=0 and last_result is not null then
   perform apoiarcred_private.wh_enqueue(lot.user_id,'campanha:'||dirty.service||':'||lot.id||':'||encode(extensions.digest(r::text||last_result::text,'sha256'),'hex'),'campanha.finalizada',
    jsonb_build_object('occurred_at',clock_timestamp(),'campanha',jsonb_build_object('id',lot.id,'nome',lot.nome,'servico',lot.servico,'convenio',lot.convenio),'relatorio',r),lot.servico,lot.id,'campanha',null,null,false);
   delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=lot.id;
  else update apoiarcred_private.webhook_campaign_dirty set checked_at=clock_timestamp() where service=dirty.service and campaign_id=lot.id;end if;
 end loop;
end $$;

create or replace function apoiarcred_private.manage_webhooks(action text,input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
<<vars>>
declare uid uuid=auth.uid();hid uuid;w apoiarcred_private.webhooks;secret text;sid uuid;data jsonb;lot record;ev text[];st text[];scope text;service_id text;campaign_id uuid;delivery record;eid uuid;
begin
 if uid is null or not apoiarcred_private.can_integrate(uid) then raise insufficient_privilege;end if;
 if action='list' then
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'-'secret_id'-'manual_window'-'manual_count' order by x.created_at desc),'[]') into data from apoiarcred_private.webhooks x where user_id=uid;return data;
 end if;
 if action='history' then
  hid=nullif(input->>'hook_id','')::uuid;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into data from (
   select d.id,d.hook_id,h.name hook_name,e.id event_id,e.event,e.payload->'consulta'->>'cpf' cpf,e.payload->'campanha'->>'nome' campaign_name,
    d.state,d.attempts,d.total_attempts,d.last_http,d.last_error,d.next_at,d.created_at,d.delivered_at,
    (select coalesce(jsonb_agg(to_jsonb(a)-'claim_token'-'delivery_id' order by attempt desc),'[]') from apoiarcred_private.webhook_attempts a where a.delivery_id=d.id) attempts_log
   from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id join apoiarcred_private.webhook_events e on e.id=d.event_id
   where h.user_id=uid and (hid is null or h.id=hid) order by d.created_at desc limit 50
  ) x;return data;
 end if;
 if action in ('update','toggle','rotate','test') then
  hid=(input->>'id')::uuid;select * into w from apoiarcred_private.webhooks where id=hid and user_id=uid for update;
  if not found then raise insufficient_privilege;end if;
 end if;
 if action='toggle' then
  update apoiarcred_private.webhooks set active=(input->>'active')::boolean,updated_at=clock_timestamp() where id=hid;return '{"ok":true}';
 elsif action='rotate' then
  secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');perform vault.update_secret(w.secret_id,secret);return jsonb_build_object('secret',secret);
 elsif action in ('test','retry') then
  if action='retry' then
   select d.* into delivery from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id where d.id=(input->>'delivery_id')::uuid and h.user_id=uid for update of d;
   if not found then raise insufficient_privilege;end if;
   if delivery.state not in ('delivered','failed') then raise exception 'A entrega já está na fila ou em andamento.';end if;
   select * into w from apoiarcred_private.webhooks where id=delivery.hook_id for update;hid=w.id;
  end if;
  if not w.active then raise exception 'Ative o webhook para testar ou reenviar.';end if;
  if w.manual_window is null or w.manual_window<now()-interval '1 hour' then w.manual_count=0;w.manual_window=now();end if;
  if w.manual_count>=10 then raise exception 'Limite de 10 testes/reenvios manuais por hora neste webhook.';end if;
  update apoiarcred_private.webhooks set manual_window=w.manual_window,manual_count=w.manual_count+1 where id=hid;
  if action='retry' then
   update apoiarcred_private.webhook_deliveries set state='pending',attempts=0,next_at=clock_timestamp(),claim_token=null,locked_until=null,last_error=null where id=delivery.id;
   return jsonb_build_object('delivery_id',delivery.id);
  end if;
  eid=gen_random_uuid();insert into apoiarcred_private.webhook_events(id,event_key,user_id,event,payload) values(eid,'test:'||eid,uid,'webhook.teste',
   jsonb_build_object('event_id',eid,'event','webhook.teste','occurred_at',clock_timestamp(),'test',true,'campanha',null,'consulta',jsonb_build_object('id',gen_random_uuid(),'servico',coalesce(w.service,'digimais_saldo_parcela'),'cpf','00000000000','nome','Cliente fictício de teste','telefone','00000000000','status','concluida','cliente_identificado',true,'resultado_parcial',false,'resultado',case when w.service='tjba_margem' then jsonb_build_object('emprestimo_disponivel',100,'cartao_disponivel',50,'matricula','TESTE-FICTICIO','tipo_servidor',null,'situacao_atual',null) else jsonb_build_object('saldo_liquidacao',1000,'valor_parcela',100,'total_parcelas',96) end)));
  insert into apoiarcred_private.webhook_deliveries(hook_id,event_id) values(hid,eid) returning id into hid;return jsonb_build_object('delivery_id',hid);
 elsif action not in ('create','update') then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(input->>'name')),0) not between 1 and 100 or coalesce(length(input->>'url'),0) not between 9 and 2048 or input->>'url'!~'^https://[^/@#[:space:]]+(/[^#[:space:]]*)?$' then raise exception 'Informe nome e URL HTTPS pública válida, sem usuário, senha ou fragmento.';end if;
 scope=input->>'scope';service_id=nullif(input->>'service','');campaign_id=nullif(input->>'campaign_id','')::uuid;
 if scope is null or scope not in ('all','individual','campaign') or (service_id is not null and service_id not in ('digimais_saldo_parcela','tjba_margem')) then raise exception 'Origem ou serviço inválido.';end if;
 if scope='campaign' then
  select * into lot from apoiarcred_private.api_campaign_rows c where c.id=vars.campaign_id and c.user_id=uid and c.tipo='campanha';
  if not found then raise insufficient_privilege;end if;service_id=lot.servico;
 else campaign_id=null;end if;
 select array_agg(distinct x) into ev from jsonb_array_elements_text(input->'events') x;
 select array_agg(distinct x) into st from jsonb_array_elements_text(input->'statuses') x;
 if coalesce(cardinality(ev),0)=0 or not ev<@array['consulta.finalizada','campanha.finalizada'] or (scope='individual' and 'campanha.finalizada'=any(ev)) then raise exception 'Escolha eventos válidos.';end if;
 if coalesce(cardinality(st),0)=0 or not st<@array['concluida','erro','revisao','nao_cliente','nao_localizado','nao_encontrado','interrompida'] or coalesce(input->>'client_filter','') not in ('all','client','nonclient','unknown') then raise exception 'Filtros de resultado inválidos.';end if;
 if action='create' then
  perform pg_advisory_xact_lock(hashtextextended(uid::text,11));
  if (select count(*) from apoiarcred_private.webhooks where user_id=uid)>=20 then raise exception 'Limite de 20 webhooks por conta.';end if;
  hid=gen_random_uuid();secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');sid=vault.create_secret(secret,'apoiarcred-webhook-'||hid);
  insert into apoiarcred_private.webhooks(id,user_id,name,url,active,scope,service,campaign_id,events,statuses,client_filter,include_partial,secret_id)
  values(hid,uid,btrim(input->>'name'),input->>'url',coalesce((input->>'active')::boolean,true),scope,service_id,campaign_id,ev,st,input->>'client_filter',coalesce((input->>'include_partial')::boolean,true),sid);
 else
  update apoiarcred_private.webhooks set name=btrim(input->>'name'),url=input->>'url',active=coalesce((input->>'active')::boolean,true),scope=vars.scope,service=service_id,campaign_id=vars.campaign_id,events=ev,statuses=st,client_filter=input->>'client_filter',include_partial=coalesce((input->>'include_partial')::boolean,true),updated_at=clock_timestamp() where id=hid;
 end if;
 return jsonb_build_object('id',hid,'secret',secret);
end $$;
notify pgrst,'reload schema';
