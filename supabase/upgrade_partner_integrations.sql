-- Integration access is an explicit administrator-managed account capability.
alter table apoiarcred_private.user_profiles add column if not exists allow_integrations boolean not null default false;
create or replace function apoiarcred_private.can_integrate(uid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from apoiarcred_private.user_profiles p where p.user_id=uid and p.active and (p.role='admin' or p.allow_integrations));
$$;
revoke all on function apoiarcred_private.can_integrate(uuid) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.can_integrate(uuid) to service_role;
create or replace function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'allow_integrations',coalesce(p.active and (p.role='admin' or p.allow_integrations),false),
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid;
$$;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg((to_jsonb(p)-'created_by')||jsonb_build_object('access',apoiarcred_private.access_for(p.user_id)) order by p.created_at desc),'[]') into result from apoiarcred_private.user_profiles p where role='partner';return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null then raise insufficient_privilege;end if;
 if p_action='create' and exists(select 1 from apoiarcred_private.user_profiles where user_id=uid) then raise exception 'Perfil já existe.';end if;
 if p_action='update' and not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='partner') then raise insufficient_privilege;end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' not in ('digimais_saldo_parcela','tjba_margem') or item->>'service' is null or (item->>'daily_limit')::int not between 0 and 100000 then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_input ? 'allow_integrations' and jsonb_typeof(p_input->'allow_integrations') is distinct from 'boolean' then raise exception 'Permissão de integrações inválida.';end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,allow_integrations,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),coalesce((p_input->>'allow_integrations')::boolean,false),p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),allow_integrations=coalesce((p_input->>'allow_integrations')::boolean,allow_integrations),updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;

create or replace function apoiarcred_private.manage_api_tokens(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); secret text; scopes text[]; expires timestamptz; result jsonb; tid uuid;
begin
 if uid is null or not apoiarcred_private.can_integrate(uid) then raise insufficient_privilege using message='Integrações não estão liberadas para esta conta.';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'prefix',t.prefix,'scopes',t.scopes,'created_at',t.created_at,'expires_at',t.expires_at,'revoked_at',t.revoked_at,'last_used_at',t.last_used_at) order by t.created_at desc),'[]') into result from apoiarcred_private.api_tokens t where t.user_id=uid;return result;
 elsif p_action='revoke' then
  update apoiarcred_private.api_tokens set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=(p_input->>'id')::uuid and user_id=uid;
  if not found then raise insufficient_privilege;end if;return '{"revoked":true}';
 elsif p_action<>'create' then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 80 then raise exception 'Informe nome de até 80 caracteres.';end if;
 select coalesce(array_agg(distinct x),'{}') into scopes from jsonb_array_elements_text(p_input->'scopes') x;
 if cardinality(scopes)=0 or not scopes<@array['read','consultas:create','campanhas:write'] then raise exception 'Permissões inválidas.';end if;
 expires=nullif(p_input->>'expires_at','')::timestamptz;
 if expires is not null and (expires<=now() or expires>now()+interval '366 days') then raise exception 'Validade deve estar entre agora e um ano.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if (select count(*) from apoiarcred_private.api_tokens where user_id=uid and revoked_at is null and (expires_at is null or expires_at>now()))>=20 then raise exception 'Limite de 20 tokens ativos. Revogue um token antes.';end if;
 secret='apc_'||encode(extensions.gen_random_bytes(32),'hex');
 insert into apoiarcred_private.api_tokens(user_id,name,token_hash,prefix,scopes,expires_at)
 values(uid,btrim(p_input->>'name'),encode(extensions.digest(secret,'sha256'),'hex'),left(secret,12),scopes,expires) returning id into tid;
 return jsonb_build_object('id',tid,'token',secret,'expires_at',expires);
end $$;

create or replace function public.api_execute(p_hash text,p_method text,p_route text,p_payload jsonb default '{}',p_key text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t apoiarcred_private.api_tokens;scope text;fingerprint text;cached apoiarcred_private.api_idempotency;result jsonb;
begin
 select * into t from apoiarcred_private.api_tokens where token_hash=p_hash for update;
 if not found or t.revoked_at is not null or (t.expires_at is not null and t.expires_at<=now()) then return apoiarcred_private.api_error(401,'invalid_token','Token inválido, expirado ou revogado.');end if;
 if not apoiarcred_private.can_integrate(t.user_id) then return apoiarcred_private.api_error(403,'integrations_disabled','Integrações não estão liberadas para esta conta.');end if;
 scope=case when p_method='GET' or p_route='/leads/buscar' then 'read' when p_route='/consultas' then 'consultas:create' else 'campanhas:write' end;
 if not scope=any(t.scopes) then return apoiarcred_private.api_error(403,'insufficient_scope','O token não possui esta permissão.');end if;
 if t.rate_window is null or t.rate_window<now()-interval '1 minute' then t.rate_count=0;t.rate_window=now();end if;
 if t.rate_count>=120 then return apoiarcred_private.api_error(429,'rate_limit','Limite de 120 requisições por minuto.');end if;
 update apoiarcred_private.api_tokens set rate_count=t.rate_count+1,rate_window=t.rate_window,last_used_at=now() where id=t.id;
 if p_method not in ('GET','POST') or jsonb_typeof(p_payload) is distinct from 'object' then return apoiarcred_private.api_error(400,'invalid_request','Requisição inválida.');end if;
 if p_method='POST' and p_route<>'/leads/buscar' and (p_key is null or length(p_key) not between 1 and 128) then return apoiarcred_private.api_error(400,'idempotency_required','Envie Idempotency-Key de 1 a 128 caracteres.');end if;
 delete from apoiarcred_private.api_idempotency where token_id=t.id and created_at<now()-interval '24 hours';
 if p_method='POST' and p_route<>'/leads/buscar' then
  fingerprint=encode(extensions.digest(p_method||p_route||p_payload::text,'sha256'),'hex');
  select * into cached from apoiarcred_private.api_idempotency where token_id=t.id and key=p_key;
  if found then
   if cached.fingerprint<>fingerprint then return apoiarcred_private.api_error(409,'idempotency_conflict','Chave já usada com outra rota ou payload.');end if;
   return cached.response||'{"replayed":true}';
  end if;
 end if;
 begin
  result=apoiarcred_private.api_route(t.user_id,p_method,p_route,p_payload);
 exception when insufficient_privilege then
  result=apoiarcred_private.api_error(403,'partner_permission',sqlerrm);
 when sqlstate 'PT429' then
  result=apoiarcred_private.api_error(429,'daily_limit',sqlerrm);
 when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value or check_violation or not_null_violation then
  result=apoiarcred_private.api_error(422,'validation_error','Dados inválidos. Confira UUIDs, paginação e campos obrigatórios.');
 end;
 if fingerprint is not null and (result->>'status')::integer<300 then insert into apoiarcred_private.api_idempotency(token_id,key,fingerprint,response) values(t.id,p_key,fingerprint,result);end if;
 return result;
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

create or replace function apoiarcred_private.wh_enqueue(uid uuid,event_key text,event_name text,body jsonb,service_id text,lot_id uuid,lot_type text,status text,client boolean,partial_result boolean) returns uuid
language plpgsql security definer set search_path='' as $$
<<vars>>
declare eid uuid=gen_random_uuid();h record;inserted_id uuid;begin
 if not apoiarcred_private.can_integrate(uid) then return null;end if;
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

create or replace function apoiarcred_private.wh_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb;lot record;result jsonb;client boolean;partial_result boolean;service_id text;begin
 r=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;service_id=r->>'servico';
 if tg_op='UPDATE' and new.status=old.status and new.consultado_em is not distinct from old.consultado_em then return new;end if;
 if tg_table_name='consulta_jobs' then select id,user_id,nome,tipo into lot from public.consulta_lotes where id=(r->>'lote_id')::uuid;
 else select id,user_id,nome,tipo into lot from public.tjba_lotes where id=(r->>'lote_id')::uuid;end if;
 if not found then return null;end if;
 if not apoiarcred_private.can_integrate(lot.user_id) then return null;end if;
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

create or replace function apoiarcred_private.wh_campaigns() returns void language plpgsql security definer set search_path='' as $$
declare dirty record;lot record;r jsonb;pending integer;total integer;last_result timestamptz;begin
 delete from apoiarcred_private.webhook_campaign_dirty where not apoiarcred_private.can_integrate(user_id);
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

create or replace function apoiarcred_private.wh_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare d record;result jsonb='[]';token uuid;begin
 perform apoiarcred_private.wh_campaigns();
 update apoiarcred_private.webhook_deliveries set state='failed',last_error='Confirmação da entrega não recebida após o limite de tentativas.' where state='delivering' and locked_until<now() and attempts>=8;
 for d in select q.id from apoiarcred_private.webhook_deliveries q join apoiarcred_private.webhooks w on w.id=q.hook_id
 join apoiarcred_private.user_profiles p on p.user_id=w.user_id and p.active and (p.role='admin' or p.allow_integrations)
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
notify pgrst,'reload schema';
