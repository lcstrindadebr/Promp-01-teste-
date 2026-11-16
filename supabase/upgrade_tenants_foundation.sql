-- Multi-tenant · etapas 1 e 2: fundação.
-- Decisões: uma empresa por usuário; 4 papéis fixos + ajustes por usuário; operador vê só o que criou;
-- cota diária só por empresa; acessos ConsigX e modo Digi+ pertencem à empresa (etapa 5).
-- Cria empresas, papéis, catálogo de permissões, exceções, cotas e o tenant_id dos dados,
-- migra cada perfil atual para uma empresa própria e NÃO muda nenhum acesso existente:
-- RLS e funções continuam filtrando por user_id até a etapa 3.
-- Aplicar numa transação. Idempotente só na parte de dados; rodar uma vez.

-- 1. Catálogo de permissões (uma linha por chave; nova permissão = nova linha)
create table apoiarcred_private.permissions(
 key text primary key check(key ~ '^[a-z_]+(\.[a-z_]+)*$'),
 description text not null,
 service text check(service in ('digimais_saldo_parcela','tjba_margem','amigoz')),
 mode text check(mode in ('individual','campanha'))
);
insert into apoiarcred_private.permissions(key,description,service,mode) values
 ('consulta.digimais.individual','Consulta individual Digi+','digimais_saldo_parcela','individual'),
 ('consulta.digimais.campanha','Campanhas Digi+','digimais_saldo_parcela','campanha'),
 ('consulta.consigx.individual','Consulta individual ConsigX','tjba_margem','individual'),
 ('consulta.consigx.campanha','Campanhas ConsigX','tjba_margem','campanha'),
 ('consulta.amigoz.individual','Consulta individual Amigoz','amigoz','individual'),
 ('consulta.amigoz.campanha','Campanhas Amigoz','amigoz','campanha'),
 ('dados.ver_empresa','Ver consultas, campanhas e clientes de todos os colegas',null,null),
 ('clientes.importar','Importar bases de clientes',null,null),
 ('clientes.exportar','Exportar clientes, resultados e oportunidades',null,null),
 ('dados.excluir','Excluir consultas, campanhas e oportunidades',null,null),
 ('oportunidade.mover','Mover cartões no funil e editar oportunidades',null,null),
 ('funil.configurar','Criar e editar etapas e campos dos cartões',null,null),
 ('acesso.portais','Cadastrar acessos ConsigX e escolher API ou robô no Digi+',null,null),
 ('integracoes','Tokens da API e webhooks',null,null),
 ('usuarios.gerenciar','Convidar, editar e desativar usuários e ver a auditoria',null,null);

-- 2. Equipe ApoiarCred (fora das empresas)
create table apoiarcred_private.platform_admins(
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);

-- 3. Empresas, teto, papéis, membros e exceções
create table apoiarcred_private.tenants(
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 160),
 active boolean not null default true,
 daily_limit integer check(daily_limit between 0 and 1000000),
 trial_until date,
 legacy_owner_id uuid unique references auth.users(id),
 created_at timestamptz not null default now()
);
create table apoiarcred_private.tenant_grants(
 tenant_id uuid not null references apoiarcred_private.tenants(id) on delete cascade,
 permission_key text not null references apoiarcred_private.permissions(key),
 primary key(tenant_id,permission_key)
);
create table apoiarcred_private.tenant_roles(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references apoiarcred_private.tenants(id) on delete cascade,
 -- Só os 4 papéis padrão; personalização é feita por usuário em member_overrides.
 code text not null check(code in ('administrador','gestor','operador','leitura')),
 name text not null check(length(btrim(name)) between 1 and 80),
 builtin boolean not null default true check(builtin),
 unique(tenant_id,code), unique(tenant_id,id)
);
create table apoiarcred_private.role_permissions(
 role_id uuid not null references apoiarcred_private.tenant_roles(id) on delete cascade,
 permission_key text not null references apoiarcred_private.permissions(key),
 primary key(role_id,permission_key)
);
create table apoiarcred_private.tenant_members(
 tenant_id uuid not null references apoiarcred_private.tenants(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role_id uuid not null,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 primary key(tenant_id,user_id),
 unique(user_id), -- uma empresa por usuário por enquanto; remover para permitir várias
 foreign key(tenant_id,role_id) references apoiarcred_private.tenant_roles(tenant_id,id)
);
create table apoiarcred_private.member_overrides(
 tenant_id uuid not null,
 user_id uuid not null,
 permission_key text not null references apoiarcred_private.permissions(key),
 allow boolean not null,
 primary key(tenant_id,user_id,permission_key),
 foreign key(tenant_id,user_id) references apoiarcred_private.tenant_members(tenant_id,user_id) on delete cascade
);

-- 4. Cotas e auditoria
create table apoiarcred_private.tenant_daily_usage(
 tenant_id uuid not null references apoiarcred_private.tenants(id) on delete cascade,
 day date not null, used integer not null default 0 check(used>=0), primary key(tenant_id,day));
create table apoiarcred_private.tenant_audit(
 id bigint generated always as identity primary key,
 tenant_id uuid references apoiarcred_private.tenants(id) on delete set null,
 actor_id uuid references auth.users(id) on delete set null,
 target_id uuid references auth.users(id) on delete set null,
 action text not null, details jsonb not null default '{}',
 created_at timestamptz not null default now());
create index tenant_audit_company_date on apoiarcred_private.tenant_audit(tenant_id,created_at desc);

do $$
declare item text;
begin
 foreach item in array array['permissions','platform_admins','tenants','tenant_grants','tenant_roles',
  'role_permissions','tenant_members','member_overrides','tenant_daily_usage','tenant_audit'] loop
  execute format('alter table apoiarcred_private.%I enable row level security',item);
  execute format('revoke all on apoiarcred_private.%I from public,anon,authenticated',item);
  execute format('grant all on apoiarcred_private.%I to service_role',item);
 end loop;
end $$;

-- 5. Papéis padrão de cada empresa
create function apoiarcred_private.seed_tenant_roles(p_tenant uuid)
returns void language plpgsql security definer set search_path='' as $$
declare all_keys text[]; consult text[];
begin
 select array_agg(key) into all_keys from apoiarcred_private.permissions;
 select array_agg(key) into consult from apoiarcred_private.permissions where service is not null;
 insert into apoiarcred_private.tenant_roles(tenant_id,code,name,builtin) values
  (p_tenant,'administrador','Administrador',true),(p_tenant,'gestor','Gestor',true),
  (p_tenant,'operador','Operador',true),(p_tenant,'leitura','Leitura',true)
 on conflict(tenant_id,code) do nothing;
 insert into apoiarcred_private.role_permissions
 select r.id,k from apoiarcred_private.tenant_roles r,
  unnest(case r.code
   when 'administrador' then all_keys
   when 'gestor' then consult||array['dados.ver_empresa','clientes.importar','clientes.exportar','oportunidade.mover','funil.configurar']
   when 'operador' then consult||array['oportunidade.mover']
   when 'leitura' then array['dados.ver_empresa'] end) k
 where r.tenant_id=p_tenant and r.builtin
 on conflict do nothing;
end $$;

-- 6. Permissão efetiva = teto da empresa ∩ (papel, com exceções do usuário por cima)
create function apoiarcred_private.today_sp() returns date language sql stable as
$$ select (now() at time zone 'America/Sao_Paulo')::date $$;

create function apoiarcred_private.has_permission(p_user uuid,p_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((
  select t.active and m.active
   and (t.trial_until is null or t.trial_until>=apoiarcred_private.today_sp())
   and exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=t.id and g.permission_key=p_key)
   and coalesce((select o.allow from apoiarcred_private.member_overrides o
                 where o.tenant_id=m.tenant_id and o.user_id=m.user_id and o.permission_key=p_key),
                exists(select 1 from apoiarcred_private.role_permissions rp where rp.role_id=m.role_id and rp.permission_key=p_key))
  from apoiarcred_private.tenant_members m join apoiarcred_private.tenants t on t.id=m.tenant_id
  where m.user_id=p_user),false);
$$;

create view apoiarcred_private.effective_permissions with (security_barrier) as
 select m.tenant_id,m.user_id,p.key as permission_key
 from apoiarcred_private.tenant_members m cross join apoiarcred_private.permissions p
 where apoiarcred_private.has_permission(m.user_id,p.key);
revoke all on apoiarcred_private.effective_permissions from public,anon,authenticated;

create function apoiarcred_private.user_tenant(p_user uuid)
returns uuid language sql stable security definer set search_path='' as
$$ select tenant_id from apoiarcred_private.tenant_members where user_id=p_user $$;

-- Regra de acesso aos dados da etapa 3: mesma empresa e (ver a empresa ou ter criado).
-- O claim tenant_id do token evita a consulta por linha quando o hook estiver ligado.
create function apoiarcred_private.can_see(p_tenant uuid,p_owner uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_tenant is not null and auth.uid() is not null
  and p_tenant=coalesce(nullif(auth.jwt()->>'tenant_id','')::uuid,apoiarcred_private.user_tenant(auth.uid()))
  and (p_owner=auth.uid() or coalesce((auth.jwt()->>'tenant_scope')='empresa',
       apoiarcred_private.has_permission(auth.uid(),'dados.ver_empresa')));
$$;

create function public.can(p_key text)
returns boolean language sql stable security definer set search_path='' as
$$ select auth.uid() is not null and apoiarcred_private.has_permission(auth.uid(),p_key) $$;

do $$
declare f text;
begin
 foreach f in array array['apoiarcred_private.seed_tenant_roles(uuid)','apoiarcred_private.has_permission(uuid,text)',
  'apoiarcred_private.user_tenant(uuid)','apoiarcred_private.can_see(uuid,uuid)'] loop
  execute 'revoke all on function '||f||' from public,anon,authenticated';
 end loop;
end $$;
revoke all on function public.can(text) from public,anon;
grant execute on function public.can(text) to authenticated;
-- RLS policies run as the signed-in user; can_see only answers about auth.uid() itself.
grant execute on function apoiarcred_private.can_see(uuid,uuid) to authenticated;

-- 7. Contexto do usuário para o painel
create function public.tenant_context()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'tenant_id',t.id,'tenant_name',t.name,'role',r.code,'role_name',r.name,
  'active',t.active and m.active,'trial_until',t.trial_until,
  'daily_limit',t.daily_limit,
  'used_today',coalesce((select u.used from apoiarcred_private.tenant_daily_usage u where u.tenant_id=t.id and u.day=apoiarcred_private.today_sp()),0),
  'platform_admin',exists(select 1 from apoiarcred_private.platform_admins a where a.user_id=m.user_id),
  'permissions',coalesce((select jsonb_agg(e.permission_key order by e.permission_key)
    from apoiarcred_private.effective_permissions e where e.user_id=m.user_id),'[]'))
 from apoiarcred_private.tenant_members m
 join apoiarcred_private.tenants t on t.id=m.tenant_id
 join apoiarcred_private.tenant_roles r on r.id=m.role_id
 where m.user_id=auth.uid();
$$;
revoke all on function public.tenant_context() from public,anon;
grant execute on function public.tenant_context() to authenticated;

-- 8. Hook de claims do token (Supabase Auth → Custom Access Token Hook).
-- Ligar em Authentication → Hooks apontando para public.custom_access_token_hook.
create function public.custom_access_token_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=(event->>'user_id')::uuid; claims jsonb:=coalesce(event->'claims','{}');
 member apoiarcred_private.tenant_members; role_code text;
begin
 select * into member from apoiarcred_private.tenant_members where user_id=uid;
 if member.user_id is not null then
  select code into role_code from apoiarcred_private.tenant_roles where id=member.role_id;
  claims:=claims||jsonb_build_object('tenant_id',member.tenant_id,'tenant_role',role_code,
   'tenant_scope',case when apoiarcred_private.has_permission(uid,'dados.ver_empresa') then 'empresa' else 'proprios' end);
 end if;
 return jsonb_set(event,'{claims}',claims);
end $$;
revoke all on function public.custom_access_token_hook(jsonb) from public,anon,authenticated;
do $$ begin
 if exists(select 1 from pg_roles where rolname='supabase_auth_admin') then
  grant usage on schema apoiarcred_private to supabase_auth_admin;
  grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
  grant select on apoiarcred_private.tenant_members,apoiarcred_private.tenant_roles to supabase_auth_admin;
 end if;
end $$;

-- 9. Cota diária só por empresa (bloqueio na linha da empresa serializa consumos concorrentes)
create function apoiarcred_private.tenant_consume(p_user uuid,p_key text,p_amount integer)
returns void language plpgsql security definer set search_path='' as $$
declare company apoiarcred_private.tenants; today date:=apoiarcred_private.today_sp();
begin
 if p_amount is null or p_amount<1 or p_amount>100000 then raise exception 'Quantidade inválida.';end if;
 select t.* into company from apoiarcred_private.tenants t
  join apoiarcred_private.tenant_members m on m.tenant_id=t.id where m.user_id=p_user for update of t;
 if not found then raise insufficient_privilege;end if;
 if not apoiarcred_private.has_permission(p_user,p_key) then
  raise insufficient_privilege using message='Consulta não autorizada para este usuário e empresa.';
 end if;
 insert into apoiarcred_private.tenant_daily_usage values(company.id,today,0) on conflict do nothing;
 update apoiarcred_private.tenant_daily_usage u set used=u.used+p_amount
  where u.tenant_id=company.id and u.day=today and (company.daily_limit is null or u.used+p_amount<=company.daily_limit);
 if not found then raise sqlstate 'PT429' using message='Limite diário da empresa atingido.';end if;
end $$;
revoke all on function apoiarcred_private.tenant_consume(uuid,text,integer) from public,anon,authenticated;

-- 10. Empresa para cada perfil, mantida em dia com a tela atual de parceiros.
-- Enquanto a gestão de parceiros antiga existir (até a etapa 4), o teto, a cota e o status da
-- empresa de cada perfil são recalculados sempre que o perfil ou suas permissões mudam.
create function apoiarcred_private.sync_legacy_tenant(p_user uuid)
returns void language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles; company uuid; service_limits integer;
begin
 select id into company from apoiarcred_private.tenants where legacy_owner_id=p_user;
 select * into profile from apoiarcred_private.user_profiles where user_id=p_user;
 if company is null or profile.user_id is null then return;end if;
 -- Cota única da empresa: a compartilhada, ou a soma dos limites individuais dos serviços liberados
 -- (que passam a valer também para campanhas, por decisão do negócio). Sem limite quando não havia.
 select nullif(sum(daily_limit),0) into service_limits from apoiarcred_private.partner_permissions
  where user_id=p_user and enabled and allow_individual;
 update apoiarcred_private.tenants set
  name=coalesce(nullif(btrim(profile.name),''),profile.email,'Empresa'),active=profile.active,trial_until=profile.trial_until,
  daily_limit=case when profile.role='admin' then null when profile.shared_quota then profile.shared_daily_limit else service_limits end
 where id=company;
 update apoiarcred_private.tenant_members set active=profile.active where tenant_id=company and user_id=p_user;
 -- Teto da empresa = o que o perfil pode fazer hoje.
 delete from apoiarcred_private.tenant_grants where tenant_id=company;
 insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select company,p.key from apoiarcred_private.permissions p
 left join apoiarcred_private.partner_permissions r on r.user_id=p_user and r.service=p.service
 where profile.role='admin'
  or (p.service in ('digimais_saldo_parcela','tjba_margem') and coalesce(r.enabled,false)
      and case p.mode when 'individual' then coalesce(r.allow_individual,false) else coalesce(r.allow_campaign,false) end)
  or (p.service='amigoz' and coalesce(profile.allow_amigoz,false))
  or (p.service is null and (p.key<>'integracoes' or profile.role='admin' or coalesce(profile.allow_integrations,false)));
 if profile.role='admin' then
  insert into apoiarcred_private.platform_admins(user_id) values(p_user) on conflict do nothing;
 else
  delete from apoiarcred_private.platform_admins where user_id=p_user;
 end if;
end $$;

create function apoiarcred_private.provision_tenant(p_user uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles; company uuid; admin_role uuid;
begin
 select tenant_id into company from apoiarcred_private.tenant_members where user_id=p_user;
 if company is not null then return company;end if;
 select * into profile from apoiarcred_private.user_profiles where user_id=p_user;
 if not found then return null;end if;
 insert into apoiarcred_private.tenants(name,legacy_owner_id)
 values(coalesce(nullif(btrim(profile.name),''),profile.email,'Empresa'),p_user) returning id into company;
 perform apoiarcred_private.seed_tenant_roles(company);
 select id into admin_role from apoiarcred_private.tenant_roles where tenant_id=company and code='administrador';
 insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id) values(company,p_user,admin_role);
 perform apoiarcred_private.sync_legacy_tenant(p_user);
 return company;
end $$;

create function apoiarcred_private.legacy_tenant_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='user_profiles' and tg_op='INSERT' then perform apoiarcred_private.provision_tenant(new.user_id);
 else perform apoiarcred_private.sync_legacy_tenant(case when tg_op='DELETE' then old.user_id else new.user_id end);end if;
 return null;
end $$;
create trigger legacy_tenant after insert or update on apoiarcred_private.user_profiles
 for each row execute function apoiarcred_private.legacy_tenant_trigger();
create trigger legacy_tenant after insert or update or delete on apoiarcred_private.partner_permissions
 for each row execute function apoiarcred_private.legacy_tenant_trigger();
do $$ declare f text; begin
 foreach f in array array['apoiarcred_private.sync_legacy_tenant(uuid)','apoiarcred_private.provision_tenant(uuid)',
  'apoiarcred_private.legacy_tenant_trigger()'] loop
  execute 'revoke all on function '||f||' from public,anon,authenticated';
 end loop;
end $$;

-- 11. Migração dos perfis atuais
select count(apoiarcred_private.provision_tenant(user_id)) as empresas_criadas from apoiarcred_private.user_profiles;

-- Consumo já registrado: a cota compartilhada, ou a soma por serviço de quem não compartilhava.
insert into apoiarcred_private.tenant_daily_usage
select t.id,u.day,sum(u.used)::integer from apoiarcred_private.partner_daily_usage u
join apoiarcred_private.tenants t on t.legacy_owner_id=u.user_id
join apoiarcred_private.user_profiles p on p.user_id=u.user_id
where (p.shared_quota and u.service='shared') or (not p.shared_quota and u.service<>'shared')
group by t.id,u.day
on conflict do nothing;

-- 12. tenant_id nos dados e nos recursos (dono = empresa; user_id continua sendo quem criou).
-- Gatilhos de usuário ficam desligados durante o preenchimento: um UPDATE em consulta_jobs
-- dispararia webhooks, sincronização do painel e do CRM para cada linha antiga.
create function apoiarcred_private.fill_tenant_id()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.tenant_id is null and new.user_id is not null then
  new.tenant_id:=apoiarcred_private.user_tenant(new.user_id);
  if new.tenant_id is null then new.tenant_id:=apoiarcred_private.provision_tenant(new.user_id);end if;
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.fill_tenant_id() from public,anon,authenticated;

do $$
declare item text; schema_name text; table_name text;
begin
 foreach item in array array[
  'public.amigoz_coefficient_simulations','public.amigoz_comissoes','public.amigoz_comissoes_tabela',
  'public.amigoz_jobs','public.amigoz_simulacoes','public.consulta_jobs','public.consulta_lotes',
  'public.consulta_tjba_historico','public.crm_cadastros','public.crm_campanhas_reuso','public.crm_card_settings',
  'public.crm_classificacoes','public.crm_dados_cliente','public.crm_etapas','public.crm_exportacoes',
  'public.crm_import_requests','public.crm_margens_vinculo','public.crm_movimentacoes','public.crm_oportunidades',
  'public.crm_vinculos','public.painel_exclusoes','public.tjba_jobs','public.tjba_lotes',
  'apoiarcred_private.api_tokens','apoiarcred_private.digimais_preferences','apoiarcred_private.tjba_credentials',
  'apoiarcred_private.tjba_robot_credentials','apoiarcred_private.webhooks','apoiarcred_private.webhook_events',
  'apoiarcred_private.webhook_campaign_dirty'] loop
  schema_name:=split_part(item,'.',1);table_name:=split_part(item,'.',2);
  execute format('alter table %I.%I add column tenant_id uuid references apoiarcred_private.tenants(id)',schema_name,table_name);
  execute format('alter table %I.%I disable trigger user',schema_name,table_name);
  execute format('update %I.%I r set tenant_id=m.tenant_id from apoiarcred_private.tenant_members m where m.user_id=r.user_id',schema_name,table_name);
  execute format('alter table %I.%I enable trigger user',schema_name,table_name);
  execute format('create index %I on %I.%I(tenant_id)',table_name||'_tenant_idx',schema_name,table_name);
  execute format('create trigger a_fill_tenant_id before insert or update of user_id on %I.%I for each row execute function apoiarcred_private.fill_tenant_id()',schema_name,table_name);
 end loop;
end $$;
