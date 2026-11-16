-- Multi-tenant · etapa 6a: tela da equipe ApoiarCred gravando direto na empresa.
-- • A tela de Parceiros (admin_partner_manage) cria e altera empresas: teto, cota, teste e situação.
--   O mesmo formato de antes, para o painel e a API da VPS não mudarem.
-- • partner_permissions deixa de ser lido ou escrito (a limpeza da etapa 6b remove a tabela).
-- • Juntar parceiros: mover o responsável de uma empresa para outra, levando os dados dele.
-- Aplicar depois de upgrade_tenants_resources.sql.

-- 1. Teto da empresa a partir do que a tela envia.
create function apoiarcred_private.platform_set_grants(p_tenant uuid,p_rules jsonb,p_amigoz boolean,p_integrations boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from apoiarcred_private.tenant_grants where tenant_id=p_tenant
  and permission_key in (select key from apoiarcred_private.permissions where service in ('digimais_saldo_parcela','tjba_margem'));
 insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select p_tenant,p.key from apoiarcred_private.permissions p
 join jsonb_array_elements(coalesce(p_rules,'[]')) r on r->>'service'=p.service
 where coalesce((r->>'enabled')::boolean,false)
  and case p.mode when 'individual' then coalesce((r->>'allow_individual')::boolean,false) else coalesce((r->>'allow_campaign')::boolean,false) end;
 if p_amigoz is not null then
  delete from apoiarcred_private.tenant_grants where tenant_id=p_tenant and permission_key like 'consulta.amigoz.%';
  if p_amigoz then insert into apoiarcred_private.tenant_grants select p_tenant,key from apoiarcred_private.permissions where service='amigoz';end if;
 end if;
 if p_integrations is not null then
  delete from apoiarcred_private.tenant_grants where tenant_id=p_tenant and permission_key='integracoes';
  if p_integrations then insert into apoiarcred_private.tenant_grants values(p_tenant,'integracoes');end if;
 end if;
end $$;

-- 2. Empresa criada a partir do perfil (equipe ApoiarCred: todas as permissões, sem cota).
create or replace function apoiarcred_private.provision_tenant(p_user uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles; company uuid; admin_role uuid;
begin
 select tenant_id into company from apoiarcred_private.tenant_members where user_id=p_user;
 if company is not null then return company;end if;
 select * into profile from apoiarcred_private.user_profiles where user_id=p_user;
 if not found then return null;end if;
 insert into apoiarcred_private.tenants(name,legacy_owner_id,active,trial_until,daily_limit)
 values(coalesce(nullif(btrim(profile.name),''),profile.email,'Empresa'),p_user,profile.active,profile.trial_until,
  case when profile.role<>'admin' and profile.shared_quota then profile.shared_daily_limit end) returning id into company;
 perform apoiarcred_private.seed_tenant_roles(company);
 select id into admin_role from apoiarcred_private.tenant_roles where tenant_id=company and code='administrador';
 insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id,name,email) values(company,p_user,admin_role,profile.name,profile.email);
 insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select company,p.key from apoiarcred_private.permissions p
 where profile.role='admin' or (p.service is null and p.key<>'integracoes')
  or (p.key='integracoes' and coalesce(profile.allow_integrations,false))
  or (p.service='amigoz' and coalesce(profile.allow_amigoz,false));
 if profile.role='admin' then insert into apoiarcred_private.platform_admins(user_id) values(p_user) on conflict do nothing;end if;
 return company;
end $$;

-- O perfil só cria a empresa; depois disso a empresa é a fonte da verdade.
drop trigger legacy_tenant on apoiarcred_private.partner_permissions;
drop trigger legacy_tenant on apoiarcred_private.user_profiles;
create or replace function apoiarcred_private.legacy_tenant_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then perform apoiarcred_private.provision_tenant(new.user_id);end if;
 if tg_op='INSERT' or new.role is distinct from old.role then
  if new.role='admin' then insert into apoiarcred_private.platform_admins(user_id) values(new.user_id) on conflict do nothing;
  else delete from apoiarcred_private.platform_admins where user_id=new.user_id;end if;
 end if;
 return null;
end $$;
create trigger legacy_tenant after insert or update of role on apoiarcred_private.user_profiles
 for each row execute function apoiarcred_private.legacy_tenant_trigger();
drop function apoiarcred_private.sync_legacy_tenant(uuid);

-- Equipe ApoiarCred: só a tabela própria.
create or replace function apoiarcred_private.is_admin(uid uuid)
returns boolean language sql stable security definer set search_path='' as
$$ select exists(select 1 from apoiarcred_private.platform_admins a where a.user_id=uid) $$;

-- 3. Tela de Parceiros = empresas.
create function apoiarcred_private.platform_company_json(p_tenant uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',o.user_id,'tenant_id',t.id,'name',t.name,
  'email',coalesce(o.email,p.email,u.email),'active',t.active,'created_at',t.created_at,
  'allow_integrations',exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=t.id and g.permission_key='integracoes'),
  'allow_amigoz',exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=t.id and g.permission_key='consulta.amigoz.individual'),
  'shared_quota',true,'shared_daily_limit',t.daily_limit,'trial_until',t.trial_until,
  'members',(select count(*) from apoiarcred_private.tenant_members m where m.tenant_id=t.id and m.active),
  'access',apoiarcred_private.access_for(o.user_id))
 from apoiarcred_private.tenants t
 -- Responsável: quem criou a empresa, ou o administrador mais antigo se ele saiu.
 cross join lateral (select m.user_id,m.email from apoiarcred_private.tenant_members m
  join apoiarcred_private.tenant_roles r on r.id=m.role_id
  where m.tenant_id=t.id order by m.user_id=t.legacy_owner_id desc,r.code='administrador' desc,m.created_at limit 1) o
 left join apoiarcred_private.user_profiles p on p.user_id=o.user_id
 left join auth.users u on u.id=o.user_id
 where t.id=p_tenant;
$$;
revoke all on function apoiarcred_private.platform_company_json(uuid) from public,anon,authenticated;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid; item jsonb; rules jsonb; result jsonb; quota integer; trial date; company uuid;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(apoiarcred_private.platform_company_json(t.id) order by t.created_at desc),'[]') into result
  from apoiarcred_private.tenants t
  where exists(select 1 from apoiarcred_private.tenant_members m where m.tenant_id=t.id)
   and not exists(select 1 from apoiarcred_private.tenant_members m join apoiarcred_private.platform_admins a on a.user_id=m.user_id where m.tenant_id=t.id);
  return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null or apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_action='create' and (exists(select 1 from apoiarcred_private.user_profiles where user_id=uid)
  or exists(select 1 from apoiarcred_private.tenant_members where user_id=uid)) then raise exception 'Perfil já existe.';end if;
 if p_action='update' then
  company=apoiarcred_private.user_tenant(uid);
  if company is null then raise insufficient_privilege;end if;
 end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' is null or item->>'service' not in ('digimais_saldo_parcela','tjba_margem') then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_input ? 'allow_integrations' and jsonb_typeof(p_input->'allow_integrations') is distinct from 'boolean' then raise exception 'Permissão de integrações inválida.';end if;
 if p_input ? 'allow_amigoz' and jsonb_typeof(p_input->'allow_amigoz') is distinct from 'boolean' then raise exception 'Permissão Amigoz inválida.';end if;
 if p_input ? 'shared_daily_limit' then
  if jsonb_typeof(p_input->'shared_daily_limit') not in ('number','null') then raise exception 'Cota diária inválida.';end if;
  quota=(p_input->>'shared_daily_limit')::integer;
  if quota not between 1 and 100000 then raise exception 'Cota diária inválida.';end if;
 end if;
 if p_input ? 'trial_until' then trial=(p_input->>'trial_until')::date;end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,shared_quota,shared_daily_limit,trial_until,created_by)
  values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),true,quota,trial,p_actor);
  company=apoiarcred_private.user_tenant(uid);
 end if;
 perform 1 from apoiarcred_private.tenants where id=company for update;
 update apoiarcred_private.tenants set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),
  daily_limit=case when p_input ? 'shared_daily_limit' then quota else daily_limit end,
  trial_until=case when p_input ? 'trial_until' then trial else trial_until end
 where id=company;
 update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),updated_at=now() where user_id=uid;
 perform apoiarcred_private.platform_set_grants(company,rules,(p_input->>'allow_amigoz')::boolean,(p_input->>'allow_integrations')::boolean);
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(company,p_actor,uid,'empresa.'||case p_action when 'create' then 'criada' else 'alterada' end,p_input-'email');
 return apoiarcred_private.access_for(uid);
end $$;
revoke all on function public.admin_partner_manage(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_partner_manage(uuid,text,jsonb) to service_role;

-- 4. Juntar parceiros: o responsável de uma empresa passa para outra com os dados dele.
-- Etapas do funil seguem pelo código (as personalizadas vão para a etapa inicial do destino);
-- acessos ConsigX, preferências Digi+, webhooks e configuração dos cartões ficam na empresa de origem.
create function public.admin_move_member(p_user uuid,p_target_user uuid,p_role text default 'gestor')
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid(); source uuid; target uuid; new_role uuid; seed_user uuid; item text; s text; t text; moved integer=0; n integer;
begin
 if not apoiarcred_private.is_admin(actor) then raise insufficient_privilege;end if;
 source=apoiarcred_private.user_tenant(p_user);target=apoiarcred_private.user_tenant(p_target_user);
 if source is null or target is null or apoiarcred_private.is_admin(p_user) or apoiarcred_private.is_admin(p_target_user) then
  raise exception using errcode='22023',message='Escolha um parceiro e uma empresa de destino.';end if;
 if source=target then raise exception using errcode='22023',message='O parceiro já está nessa empresa.';end if;
 select id into new_role from apoiarcred_private.tenant_roles where tenant_id=target and code=p_role;
 if new_role is null then raise exception using errcode='22023',message='Papel inválido.';end if;
 if exists(select 1 from apoiarcred_private.tenant_members where tenant_id=source and user_id<>p_user and active) then
  raise exception using errcode='22023',message='A empresa de origem tem outros usuários ativos. Mova ou desative esses usuários antes.';end if;
 perform pg_advisory_xact_lock(hashtextextended('move:'||least(source,target)::text||greatest(source,target)::text,0));
 if exists(select 1 from public.consulta_jobs where user_id=p_user and status='processando')
  or exists(select 1 from public.tjba_jobs where user_id=p_user and status='processando') then
  raise exception using errcode='55006',message='Há consultas deste parceiro em andamento. Pause as campanhas e tente de novo em alguns minutos.';end if;

 -- Funil do destino pronto para receber os cartões.
 select user_id into seed_user from apoiarcred_private.tenant_members where tenant_id=target order by created_at limit 1;
 perform apoiarcred_private.crm_semear_etapas(seed_user);

 foreach item in array array[
  'public.amigoz_coefficient_simulations','public.amigoz_comissoes','public.amigoz_comissoes_tabela',
  'public.amigoz_jobs','public.amigoz_simulacoes','public.consulta_jobs','public.consulta_lotes',
  'public.consulta_tjba_historico','public.crm_cadastros','public.crm_campanhas_reuso',
  'public.crm_classificacoes','public.crm_dados_cliente','public.crm_exportacoes',
  'public.crm_import_requests','public.crm_margens_vinculo','public.crm_movimentacoes','public.crm_oportunidades',
  'public.crm_vinculos','public.painel_exclusoes','public.tjba_jobs','public.tjba_lotes',
  'apoiarcred_private.api_tokens','apoiarcred_private.webhook_events','apoiarcred_private.webhook_campaign_dirty'] loop
  s=split_part(item,'.',1);t=split_part(item,'.',2);
  -- Sem gatilhos: mudar a empresa não é uma nova consulta, movimentação ou evento de webhook.
  execute format('alter table %I.%I disable trigger user',s,t);
  if item='public.crm_oportunidades' then
   update public.crm_oportunidades o set tenant_id=target,
    etapa_id=coalesce(same.id,first.id),etapa=coalesce(same.codigo,first.codigo)
   from public.crm_etapas old
   left join public.crm_etapas same on same.tenant_id=target and same.codigo=old.codigo and not same.arquivada
   cross join lateral (select e.id,e.codigo from public.crm_etapas e where e.tenant_id=target and e.inicial limit 1) first
   where o.user_id=p_user and old.id=o.etapa_id;
  else
   execute format('update %I.%I set tenant_id=$1 where user_id=$2',s,t) using target,p_user;
  end if;
  get diagnostics n=row_count;moved=moved+n;
  execute format('alter table %I.%I enable trigger user',s,t);
 end loop;

 delete from apoiarcred_private.member_overrides where tenant_id=source and user_id=p_user;
 update apoiarcred_private.tenant_members set tenant_id=target,role_id=new_role where user_id=p_user;
 update apoiarcred_private.tenants set active=false where id=source
  and not exists(select 1 from apoiarcred_private.tenant_members m where m.tenant_id=source);
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(target,actor,p_user,'usuario.movido',jsonb_build_object('origem',source,'registros',moved,'papel',p_role));
 return jsonb_build_object('tenant_id',target,'registros',moved);
end $$;
revoke all on function public.admin_move_member(uuid,uuid,text) from public,anon;
grant execute on function public.admin_move_member(uuid,uuid,text) to authenticated;
