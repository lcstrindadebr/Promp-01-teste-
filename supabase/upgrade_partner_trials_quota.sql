-- Shared daily quota for configured partners and trials ending in Brasília time.
alter table apoiarcred_private.user_profiles
 add column if not exists shared_quota boolean not null default false,
 add column if not exists shared_daily_limit integer check(shared_daily_limit between 1 and 100000),
 add column if not exists trial_until date;

create or replace function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'allow_integrations',coalesce(p.active and (p.role='admin' or p.allow_integrations),false),
 'trial_until',p.trial_until,
 'trial_expired',coalesce(p.trial_until<(now() at time zone 'America/Sao_Paulo')::date,false),
 'trial_days_left',case when p.trial_until is not null then greatest(0,p.trial_until-(now() at time zone 'America/Sao_Paulo')::date+1) end,
 'shared_quota',coalesce(p.shared_quota,false),'daily_limit',p.shared_daily_limit,
 'remaining',case when p.shared_daily_limit is not null then greatest(0,p.shared_daily_limit-coalesce(shared.used,0)) end,
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid
 left join apoiarcred_private.partner_daily_usage shared on shared.user_id=uid and shared.service='shared'
  and shared.day=(now() at time zone 'America/Sao_Paulo')::date;
$$;

create or replace function apoiarcred_private.check_partner_access(uid uuid,service_id text,mode text,consume boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles;rule apoiarcred_private.partner_permissions;today date=(now() at time zone 'America/Sao_Paulo')::date;n integer;
begin
 select * into profile from apoiarcred_private.user_profiles where user_id=uid for share;
 if not found or not profile.active then raise insufficient_privilege using message='Conta sem acesso ativo. Solicite liberação ao administrador.';end if;
 if profile.role='admin' then return;end if;
 if profile.trial_until<today then
  raise insufficient_privilege using message='Seu período de teste terminou. Solicite a renovação ao administrador.';
 end if;
 select * into rule from apoiarcred_private.partner_permissions where user_id=uid and service=service_id for share;
 if not found or not rule.enabled then raise insufficient_privilege using message='Tipo de higienização não autorizado para este parceiro.';end if;
 if mode='campanha' then
  if not rule.allow_campaign then raise insufficient_privilege using message='Campanhas não estão habilitadas para este tipo de higienização.';end if;
 elsif mode='individual' then
  if not rule.allow_individual or (not profile.shared_quota and rule.daily_limit=0) then raise insufficient_privilege using message='Consultas individuais não estão habilitadas para este tipo de higienização.';end if;
  if consume and not profile.shared_quota then
   insert into apoiarcred_private.partner_daily_usage(user_id,service,day,used) values(uid,service_id,today,0) on conflict do nothing;
   update apoiarcred_private.partner_daily_usage set used=used+1 where user_id=uid and service=service_id and day=today and used<rule.daily_limit;
   get diagnostics n=row_count;
   if n=0 then raise sqlstate 'PT429' using message='Limite diário de consultas individuais atingido para este tipo. Renova à meia-noite no horário de Brasília.';end if;
  end if;
 else raise insufficient_privilege;end if;
 if consume and profile.shared_quota then
  insert into apoiarcred_private.partner_daily_usage(user_id,service,day,used)
  values(uid,'shared',today,0) on conflict do nothing;
  update apoiarcred_private.partner_daily_usage set used=used+1
   where user_id=uid and service='shared' and day=today
     and (profile.shared_daily_limit is null or used<profile.shared_daily_limit);
  if not found then raise sqlstate 'PT429' using message='Limite diário compartilhado entre campanhas e consultas individuais atingido. Renova à meia-noite no horário de Brasília.';end if;
 end if;
end $$;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;quota integer;trial date;
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
 if p_input ? 'shared_daily_limit' then
  if jsonb_typeof(p_input->'shared_daily_limit') not in ('number','null') then raise exception 'Cota diária inválida.';end if;
  quota=(p_input->>'shared_daily_limit')::integer;
  if quota not between 1 and 100000 then raise exception 'Cota diária inválida.';end if;
 end if;
 if p_input ? 'trial_until' then trial=(p_input->>'trial_until')::date;end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,allow_integrations,shared_quota,shared_daily_limit,trial_until,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),coalesce((p_input->>'allow_integrations')::boolean,false),p_input ? 'shared_daily_limit',quota,trial,p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),allow_integrations=coalesce((p_input->>'allow_integrations')::boolean,allow_integrations),shared_quota=shared_quota or p_input ? 'shared_daily_limit',
   shared_daily_limit=case when p_input ? 'shared_daily_limit' then quota else shared_daily_limit end,
   trial_until=case when p_input ? 'trial_until' then trial else trial_until end,
   updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;

create or replace function public.create_consulta_campaign(p_nome text,p_items jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare campaign_id uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe um nome de campanha com até 160 caracteres.'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.'; end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>10000 then raise exception 'Envie até 10.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados na campanha.'; end if;
 insert into public.consulta_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into campaign_id;
 insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone)
 select campaign_id,auth.uid(),x.item->>'nome',x.item->>'cpf',x.item->>'telefone' from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return campaign_id;
end $$;

create or replace function public.create_tjba_campaign(p_nome text,p_items jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>10000 then raise exception 'Envie até 10.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.nome),''),'CPF '||x.cpf),x.cpf,coalesce(x.telefone,'') from jsonb_to_recordset(p_items) x(nome text,cpf text,telefone text);
 return cid;
end $$;

create or replace function public.create_consigx_campaign(p_nome text,p_items jsonb,p_convenio text) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>10000 then raise exception 'Envie até 10.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo,convenio) values(btrim(p_nome),'campanha',p_convenio) returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.item->>'nome'),''),'CPF '||(x.item->>'cpf')),x.item->>'cpf',coalesce(x.item->>'telefone','') from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return cid;
end $$;
