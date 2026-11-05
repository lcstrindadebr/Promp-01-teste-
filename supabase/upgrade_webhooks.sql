-- Transactional outbox: result persistence never waits on an HTTP endpoint.
create table apoiarcred_private.webhooks(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 100),url text not null check(length(url)<=2048 and url~'^https://'),
 active boolean not null default true,scope text not null check(scope in ('all','individual','campaign')),
 service text check(service in ('digimais_saldo_parcela','tjba_margem')),campaign_id uuid,
 events text[] not null,statuses text[] not null,client_filter text not null check(client_filter in ('all','client','nonclient','unknown')),
 include_partial boolean not null default true,secret_id uuid not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 manual_window timestamptz,manual_count integer not null default 0
);
create index webhooks_owner on apoiarcred_private.webhooks(user_id);
create table apoiarcred_private.webhook_events(
 id uuid primary key,event_key text not null unique,user_id uuid not null references auth.users(id) on delete cascade,
 event text not null,payload jsonb not null,created_at timestamptz not null default now()
);
create index webhook_events_owner on apoiarcred_private.webhook_events(user_id,created_at desc);
create table apoiarcred_private.webhook_deliveries(
 id uuid primary key default gen_random_uuid(),hook_id uuid not null references apoiarcred_private.webhooks(id) on delete cascade,
 event_id uuid not null references apoiarcred_private.webhook_events(id) on delete cascade,
 state text not null default 'pending' check(state in ('pending','delivering','retry','delivered','failed')),
 attempts integer not null default 0,total_attempts integer not null default 0,next_at timestamptz not null default now(),
 locked_until timestamptz,claim_token uuid,last_http integer,last_error text,delivered_at timestamptz,created_at timestamptz not null default now(),unique(hook_id,event_id)
);
create index webhook_delivery_queue on apoiarcred_private.webhook_deliveries(next_at) where state in ('pending','retry','delivering');
create index webhook_delivery_hook on apoiarcred_private.webhook_deliveries(hook_id,created_at desc);
create table apoiarcred_private.webhook_attempts(
 delivery_id uuid not null references apoiarcred_private.webhook_deliveries(id) on delete cascade,attempt integer not null,
 claim_token uuid not null,started_at timestamptz not null default now(),finished_at timestamptz,http_status integer,error text,
 primary key(delivery_id,attempt)
);
create table apoiarcred_private.webhook_campaign_dirty(
 service text not null,campaign_id uuid not null,user_id uuid not null,touched_at timestamptz not null default now(),checked_at timestamptz,
 primary key(service,campaign_id)
);
alter table apoiarcred_private.webhooks enable row level security;
alter table apoiarcred_private.webhook_events enable row level security;
alter table apoiarcred_private.webhook_deliveries enable row level security;
alter table apoiarcred_private.webhook_attempts enable row level security;
alter table apoiarcred_private.webhook_campaign_dirty enable row level security;
revoke all on apoiarcred_private.webhooks,apoiarcred_private.webhook_events,apoiarcred_private.webhook_deliveries,apoiarcred_private.webhook_attempts,apoiarcred_private.webhook_campaign_dirty from public,anon,authenticated,service_role;

create function apoiarcred_private.wh_client(service text,status text,r jsonb) returns boolean language sql immutable set search_path='' as $$
 select case when status in ('nao_cliente','nao_localizado','nao_encontrado') then false
 when status='concluida' then true
 when service='digimais_saldo_parcela' and (r->>'saldo_liquidacao' is not null or r->>'valor_parcela' is not null) then true
 when service='tjba_margem' and (nullif(r->>'matricula','') is not null or r->>'emprestimo_disponivel' is not null or r->>'cartao_disponivel' is not null) then true
 else null end;
$$;
create function apoiarcred_private.wh_result(service text,r jsonb) returns jsonb language sql immutable set search_path='' as $$
 select case when service='digimais_saldo_parcela' then jsonb_build_object('saldo_liquidacao',r->'saldo_liquidacao','valor_parcela',r->'valor_parcela','total_parcelas',r->'total_parcelas')
 else jsonb_build_object('emprestimo_disponivel',r->'emprestimo_disponivel','cartao_disponivel',r->'cartao_disponivel','matricula',r->'matricula','tipo_servidor',r->'tipo_servidor','situacao_atual',r->'situacao_atual') end;
$$;
create function apoiarcred_private.wh_enqueue(uid uuid,event_key text,event_name text,body jsonb,service_id text,lot_id uuid,lot_type text,status text,client boolean,partial_result boolean) returns uuid
language plpgsql security definer set search_path='' as $$
<<vars>>
declare eid uuid=gen_random_uuid();h record;inserted_id uuid;begin
 for h in select * from apoiarcred_private.webhooks w where w.user_id=uid and w.active and event_name=any(w.events)
 and (w.service is null or w.service=service_id)
 and (w.scope='all' or w.scope='individual' and lot_type='individual' or w.scope='campaign' and w.campaign_id=lot_id)
 and (event_name='campanha.finalizada' or (status=any(w.statuses) and (w.include_partial or not partial_result)
 and (w.client_filter='all' or w.client_filter='client' and client is true or w.client_filter='nonclient' and client is false or w.client_filter='unknown' and client is null))) loop
  insert into apoiarcred_private.webhook_events(id,event_key,user_id,event,payload)
  values(eid,event_key,uid,event_name,body||jsonb_build_object('event_id',eid,'event',event_name))
  on conflict on constraint webhook_events_event_key_key do update set event_key=excluded.event_key returning id into inserted_id;
  eid=inserted_id;
  insert into apoiarcred_private.webhook_deliveries(hook_id,event_id) values(h.id,eid) on conflict do nothing;
 end loop;return eid;
end $$;

create function apoiarcred_private.wh_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb;lot record;result jsonb;client boolean;partial_result boolean;service_id text;begin
 r=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;service_id=r->>'servico';
 if tg_op='UPDATE' and new.status=old.status and new.consultado_em is not distinct from old.consultado_em then return new;end if;
 if tg_table_name='consulta_jobs' then select id,user_id,nome,tipo into lot from public.consulta_lotes where id=(r->>'lote_id')::uuid;
 else select id,user_id,nome,tipo into lot from public.tjba_lotes where id=(r->>'lote_id')::uuid;end if;
 if not found then return null;end if;
 if tg_op='UPDATE' and old.status='processando' and new.status in ('concluida','nao_cliente','nao_localizado','nao_encontrado','erro','revisao') and new.consultado_em is not null then
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
create trigger capture_webhook after insert or delete or update of status,consultado_em on public.consulta_jobs for each row execute function apoiarcred_private.wh_capture();
create trigger capture_webhook after insert or delete or update of status,consultado_em on public.tjba_jobs for each row execute function apoiarcred_private.wh_capture();

create function apoiarcred_private.wh_campaigns() returns void language plpgsql security definer set search_path='' as $$
declare dirty record;lot record;r jsonb;pending integer;total integer;last_result timestamptz;begin
 for dirty in select * from apoiarcred_private.webhook_campaign_dirty order by checked_at nulls first,touched_at limit 20 for update skip locked loop
  select * into lot from apoiarcred_private.api_campaign_rows where id=dirty.campaign_id and user_id=dirty.user_id and tipo='campanha';
  if not found then delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=dirty.campaign_id;continue;end if;
  select count(*),count(*) filter(where status in ('aguardando','processando')),max(consultado_em),
   jsonb_build_object('total',count(*),'clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is true),
    'nao_clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is false),'indeterminados',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is null),
    'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'))
   into total,pending,last_result,r from apoiarcred_private.api_lead_rows where campanha_id=lot.id and user_id=lot.user_id;
  if total>0 and pending=0 and last_result is not null then
   perform apoiarcred_private.wh_enqueue(lot.user_id,'campanha:'||dirty.service||':'||lot.id||':'||encode(extensions.digest(r::text||last_result::text,'sha256'),'hex'),'campanha.finalizada',
    jsonb_build_object('occurred_at',clock_timestamp(),'campanha',jsonb_build_object('id',lot.id,'nome',lot.nome,'servico',lot.servico,'convenio',lot.convenio),'relatorio',r),lot.servico,lot.id,'campanha',null,null,false);
   delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=lot.id;
  else update apoiarcred_private.webhook_campaign_dirty set checked_at=clock_timestamp() where service=dirty.service and campaign_id=lot.id;end if;
 end loop;
end $$;

create function apoiarcred_private.manage_webhooks(action text,input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
<<vars>>
declare uid uuid=auth.uid();hid uuid;w apoiarcred_private.webhooks;secret text;sid uuid;data jsonb;lot record;ev text[];st text[];scope text;service_id text;campaign_id uuid;delivery record;eid uuid;
begin
 if uid is null or not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and active) then raise insufficient_privilege;end if;
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
 if coalesce(cardinality(st),0)=0 or not st<@array['concluida','erro','revisao','nao_cliente','nao_localizado','nao_encontrado'] or coalesce(input->>'client_filter','') not in ('all','client','nonclient','unknown') then raise exception 'Filtros de resultado inválidos.';end if;
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

create function apoiarcred_private.wh_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare d record;result jsonb='[]';token uuid;begin
 perform apoiarcred_private.wh_campaigns();
 update apoiarcred_private.webhook_deliveries set state='failed',last_error='Confirmação da entrega não recebida após o limite de tentativas.' where state='delivering' and locked_until<now() and attempts>=8;
 for d in select q.id from apoiarcred_private.webhook_deliveries q join apoiarcred_private.webhooks w on w.id=q.hook_id
 join apoiarcred_private.user_profiles p on p.user_id=w.user_id and p.active
 where w.active and q.attempts<8 and q.next_at<=now() and (q.state in ('pending','retry') or q.state='delivering' and q.locked_until<now())
 order by q.next_at,q.created_at limit 2 for update of q skip locked loop
  update apoiarcred_private.webhook_attempts set finished_at=clock_timestamp(),error='Confirmação da tentativa anterior não recebida.' where delivery_id=d.id and finished_at is null;
  token=gen_random_uuid();
  update apoiarcred_private.webhook_deliveries set state='delivering',attempts=attempts+1,total_attempts=total_attempts+1,claim_token=token,locked_until=now()+interval '2 minutes' where id=d.id;
  insert into apoiarcred_private.webhook_attempts(delivery_id,attempt,claim_token) select id,total_attempts,token from apoiarcred_private.webhook_deliveries where id=d.id;
  select result||jsonb_build_array(jsonb_build_object('id',q.id,'claim_token',token,'event_id',e.id,'payload',e.payload,'url',w.url,'secret',s.decrypted_secret)) into result
  from apoiarcred_private.webhook_deliveries q join apoiarcred_private.webhooks w on w.id=q.hook_id join apoiarcred_private.webhook_events e on e.id=q.event_id left join vault.decrypted_secrets s on s.id=w.secret_id where q.id=d.id;
 end loop;return result;
end $$;
create function apoiarcred_private.wh_ack(p_id uuid,p_token uuid,p_success boolean,p_http integer,p_error text,p_retry boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare d apoiarcred_private.webhook_deliveries;delay integer;begin
 select * into d from apoiarcred_private.webhook_deliveries where id=p_id and claim_token=p_token and state='delivering' for update;
 if not found then return false;end if;
 delay=(array[30,120,600,1800,7200,21600,43200,43200])[least(d.attempts,8)];
 update apoiarcred_private.webhook_deliveries set state=case when p_success then 'delivered' when p_retry and d.attempts<8 then 'retry' else 'failed' end,
  last_http=p_http,last_error=left(p_error,500),next_at=clock_timestamp()+make_interval(secs=>delay),locked_until=null,
  delivered_at=case when p_success then clock_timestamp() else delivered_at end where id=d.id;
 update apoiarcred_private.webhook_attempts set finished_at=clock_timestamp(),http_status=p_http,error=left(p_error,500) where delivery_id=d.id and claim_token=p_token;return true;
end $$;
-- Private definer implementations; only narrow invoker entry points are exposed.
revoke all on function apoiarcred_private.wh_client(text,text,jsonb),apoiarcred_private.wh_result(text,jsonb),apoiarcred_private.wh_enqueue(uuid,text,text,jsonb,text,uuid,text,text,boolean,boolean),apoiarcred_private.wh_capture(),apoiarcred_private.wh_campaigns(),apoiarcred_private.manage_webhooks(text,jsonb),apoiarcred_private.wh_claim(),apoiarcred_private.wh_ack(uuid,uuid,boolean,integer,text,boolean) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.manage_webhooks(text,jsonb) to authenticated;
grant execute on function apoiarcred_private.wh_claim(),apoiarcred_private.wh_ack(uuid,uuid,boolean,integer,text,boolean) to service_role;
create function public.manage_webhooks(p_action text,p_input jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.manage_webhooks(p_action,p_input);$$;
create function public.claim_webhook_deliveries() returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.wh_claim();$$;
create function public.ack_webhook_delivery(p_id uuid,p_token uuid,p_success boolean,p_http integer,p_error text,p_retry boolean) returns boolean language sql security invoker set search_path='' as $$select apoiarcred_private.wh_ack(p_id,p_token,p_success,p_http,p_error,p_retry);$$;
revoke all on function public.manage_webhooks(text,jsonb),public.claim_webhook_deliveries(),public.ack_webhook_delivery(uuid,uuid,boolean,integer,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.manage_webhooks(text,jsonb) to authenticated;
grant execute on function public.claim_webhook_deliveries(),public.ack_webhook_delivery(uuid,uuid,boolean,integer,text,boolean) to service_role;
notify pgrst,'reload schema';

-- Removing an account also removes its signing secrets from Vault.
create function apoiarcred_private.wh_cleanup() returns trigger language plpgsql security definer set search_path='' as $$begin delete from vault.secrets where id=old.secret_id;return null;end $$;
revoke all on function apoiarcred_private.wh_cleanup() from public,anon,authenticated,service_role;
create trigger cleanup_webhook_secret after delete on apoiarcred_private.webhooks for each row execute function apoiarcred_private.wh_cleanup();
