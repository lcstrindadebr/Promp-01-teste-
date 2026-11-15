-- Preparação aditiva. A ativação exige adaptar os consumidores legados de user_id.
-- Execute em uma transação junto às demais migrações da versão de tenants.
create table apoiarcred_private.tenants (
 id uuid primary key default gen_random_uuid(),
 legacy_owner_id uuid not null unique references auth.users(id),
 name text not null check(length(btrim(name)) between 1 and 160),
 active boolean not null default true,
 daily_limit integer check(daily_limit between 0 and 100000),
 trial_until date,
 created_at timestamptz not null default now()
);
create table apoiarcred_private.tenant_members (
 user_id uuid primary key references auth.users(id),
 tenant_id uuid not null references apoiarcred_private.tenants(id),
 role text not null check(role in ('admin','operator')),
 active boolean not null default true,
 daily_limit integer check(daily_limit between 0 and 100000),
 created_at timestamptz not null default now(),
 unique(tenant_id,user_id)
);
create index tenant_members_company on apoiarcred_private.tenant_members(tenant_id,active);
create table apoiarcred_private.tenant_permissions (
 tenant_id uuid not null references apoiarcred_private.tenants(id),
 service text not null check(service in ('digimais_saldo_parcela','tjba_margem','amigoz')),
 enabled boolean not null default false,
 allow_individual boolean not null default false,
 allow_campaign boolean not null default false,
 individual_daily_limit integer check(individual_daily_limit between 0 and 100000),
 primary key(tenant_id,service)
);
create table apoiarcred_private.tenant_user_permissions (
 tenant_id uuid not null,
 user_id uuid not null,
 service text not null,
 enabled boolean not null default false,
 allow_individual boolean not null default false,
 allow_campaign boolean not null default false,
 primary key(user_id,service),
 foreign key(tenant_id,user_id) references apoiarcred_private.tenant_members(tenant_id,user_id),
 foreign key(tenant_id,service) references apoiarcred_private.tenant_permissions(tenant_id,service)
);
create table apoiarcred_private.tenant_actions (
 tenant_id uuid not null references apoiarcred_private.tenants(id),
 action text not null check(action in ('import','export','delete','integrations','users')),
 enabled boolean not null default false,
 primary key(tenant_id,action)
);
create table apoiarcred_private.tenant_user_actions (
 tenant_id uuid not null,
 user_id uuid not null,
 action text not null,
 enabled boolean not null default false,
 primary key(user_id,action),
 foreign key(tenant_id,user_id) references apoiarcred_private.tenant_members(tenant_id,user_id),
 foreign key(tenant_id,action) references apoiarcred_private.tenant_actions(tenant_id,action)
);
create table apoiarcred_private.tenant_daily_usage (
 tenant_id uuid not null references apoiarcred_private.tenants(id),
 day date not null,
 used integer not null default 0 check(used>=0),
 primary key(tenant_id,day)
);
create table apoiarcred_private.tenant_user_daily_usage (
 tenant_id uuid not null,
 user_id uuid not null,
 day date not null,
 used integer not null default 0 check(used>=0),
 primary key(user_id,day),
 foreign key(tenant_id,user_id) references apoiarcred_private.tenant_members(tenant_id,user_id)
);
create table apoiarcred_private.tenant_service_daily_usage (
 tenant_id uuid not null,
 service text not null,
 day date not null,
 used integer not null default 0 check(used>=0),
 primary key(tenant_id,service,day),
 foreign key(tenant_id,service) references apoiarcred_private.tenant_permissions(tenant_id,service)
);
create table apoiarcred_private.tenant_audit (
 id bigint generated always as identity primary key,
 tenant_id uuid not null references apoiarcred_private.tenants(id),
 actor_id uuid references auth.users(id),
 target_id uuid references auth.users(id),
 action text not null,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index tenant_audit_company_date on apoiarcred_private.tenant_audit(tenant_id,created_at desc);

do $migration$
declare item text;
begin
 foreach item in array array['tenants','tenant_members','tenant_permissions',
  'tenant_user_permissions','tenant_actions','tenant_user_actions','tenant_daily_usage',
  'tenant_user_daily_usage','tenant_service_daily_usage','tenant_audit']
 loop
  execute format('alter table apoiarcred_private.%I enable row level security',item);
  execute format('revoke all on apoiarcred_private.%I from public,anon,authenticated',item);
 end loop;
end
$migration$;

-- Cada perfil existente recebe uma empresa própria e conserva o identificador original.
insert into apoiarcred_private.tenants(legacy_owner_id,name,active,daily_limit,trial_until)
select user_id,name,active,case when shared_quota then shared_daily_limit end,trial_until
from apoiarcred_private.user_profiles;

insert into apoiarcred_private.tenant_members(user_id,tenant_id,role,active)
select t.legacy_owner_id,t.id,'admin',p.active
from apoiarcred_private.tenants t
join apoiarcred_private.user_profiles p on p.user_id=t.legacy_owner_id;

insert into apoiarcred_private.tenant_permissions
 (tenant_id,service,enabled,allow_individual,allow_campaign,individual_daily_limit)
select t.id,s.service,
 p.role='admin' or coalesce(r.enabled,false),
 p.role='admin' or coalesce(r.allow_individual,false),
 p.role='admin' or coalesce(r.allow_campaign,false),
 case when p.role<>'admin' and not p.shared_quota then coalesce(r.daily_limit,0) end
from apoiarcred_private.tenants t
join apoiarcred_private.user_profiles p on p.user_id=t.legacy_owner_id
cross join (values('digimais_saldo_parcela'),('tjba_margem')) s(service)
left join apoiarcred_private.partner_permissions r on r.user_id=p.user_id and r.service=s.service;
insert into apoiarcred_private.tenant_permissions
 (tenant_id,service,enabled,allow_individual,allow_campaign)
select t.id,'amigoz',p.role='admin' or p.allow_amigoz,
 p.role='admin' or p.allow_amigoz,p.role='admin' or p.allow_amigoz
from apoiarcred_private.tenants t
join apoiarcred_private.user_profiles p on p.user_id=t.legacy_owner_id;

insert into apoiarcred_private.tenant_user_permissions
select p.tenant_id,m.user_id,p.service,p.enabled,p.allow_individual,p.allow_campaign
from apoiarcred_private.tenant_permissions p
join apoiarcred_private.tenant_members m on m.tenant_id=p.tenant_id;

insert into apoiarcred_private.tenant_actions
select t.id,a.action,case when a.action='integrations' then p.role='admin' or p.allow_integrations else true end
from apoiarcred_private.tenants t
join apoiarcred_private.user_profiles p on p.user_id=t.legacy_owner_id
cross join (values('import'),('export'),('delete'),('integrations'),('users')) a(action);
insert into apoiarcred_private.tenant_user_actions
select a.tenant_id,m.user_id,a.action,a.enabled
from apoiarcred_private.tenant_actions a
join apoiarcred_private.tenant_members m on m.tenant_id=a.tenant_id;

-- Preserva o consumo já registrado, inclusive no dia da migração.
insert into apoiarcred_private.tenant_daily_usage
select t.id,u.day,u.used from apoiarcred_private.partner_daily_usage u
join apoiarcred_private.tenants t on t.legacy_owner_id=u.user_id where u.service='shared';
insert into apoiarcred_private.tenant_user_daily_usage
select t.id,u.user_id,u.day,sum(u.used)::integer
from apoiarcred_private.partner_daily_usage u
join apoiarcred_private.tenants t on t.legacy_owner_id=u.user_id
group by t.id,u.user_id,u.day;
insert into apoiarcred_private.tenant_service_daily_usage
select t.id,u.service,u.day,u.used from apoiarcred_private.partner_daily_usage u
join apoiarcred_private.tenants t on t.legacy_owner_id=u.user_id
where u.service in ('digimais_saldo_parcela','tjba_margem');

create function apoiarcred_private.tenant_can_service(actor uuid,service_id text,mode text)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((
  select t.active and m.active
   and (t.trial_until is null or t.trial_until>=(now() at time zone 'America/Sao_Paulo')::date)
   and p.enabled and u.enabled
   and case mode when 'individual' then p.allow_individual and u.allow_individual
       when 'campanha' then p.allow_campaign and u.allow_campaign
       when 'read' then true else false end
  from apoiarcred_private.tenant_members m
  join apoiarcred_private.tenants t on t.id=m.tenant_id
  join apoiarcred_private.tenant_permissions p on p.tenant_id=t.id and p.service=service_id
  join apoiarcred_private.tenant_user_permissions u on u.user_id=m.user_id and u.service=p.service
  where m.user_id=actor
 ),false);
$$;
revoke all on function apoiarcred_private.tenant_can_service(uuid,text,text) from public,anon,authenticated;

create function apoiarcred_private.tenant_can_action(actor uuid,action_id text)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((
  select t.active and m.active and a.enabled and u.enabled
   and (action_id<>'users' or m.role='admin')
  from apoiarcred_private.tenant_members m
  join apoiarcred_private.tenants t on t.id=m.tenant_id
  join apoiarcred_private.tenant_actions a on a.tenant_id=t.id and a.action=action_id
  join apoiarcred_private.tenant_user_actions u on u.user_id=m.user_id and u.action=a.action
  where m.user_id=actor
 ),false);
$$;
revoke all on function apoiarcred_private.tenant_can_action(uuid,text) from public,anon,authenticated;

-- Os chamadores internos devem validar a sessão antes de fornecer actor.
create function apoiarcred_private.tenant_consume(actor uuid,service_id text,mode text,amount integer)
returns void language plpgsql security definer set search_path='' as $$
declare company apoiarcred_private.tenants; member apoiarcred_private.tenant_members;
 service_limit integer; today date:=(now() at time zone 'America/Sao_Paulo')::date; used integer;
begin
 if amount is null or amount<1 or amount>100000 then raise exception 'Quantidade inválida.';end if;
 -- Ordem única de bloqueios para serializar cotas da empresa e do usuário.
 select t.* into company from apoiarcred_private.tenants t
 join apoiarcred_private.tenant_members m on m.tenant_id=t.id
 where m.user_id=actor for update of t;
 if not found then raise insufficient_privilege;end if;
 select * into member from apoiarcred_private.tenant_members where user_id=actor for update;
 if not apoiarcred_private.tenant_can_service(actor,service_id,mode) then
  raise insufficient_privilege using message='Consulta não autorizada para este usuário e empresa.';
 end if;
 insert into apoiarcred_private.tenant_daily_usage values(company.id,today,0) on conflict do nothing;
 update apoiarcred_private.tenant_daily_usage set used=tenant_daily_usage.used+amount
 where tenant_id=company.id and day=today
 and (company.daily_limit is null or tenant_daily_usage.used+amount<=company.daily_limit);
 if not found then raise sqlstate 'PT429' using message='Limite diário da empresa atingido.';end if;
 insert into apoiarcred_private.tenant_user_daily_usage values(company.id,actor,today,0) on conflict do nothing;
 update apoiarcred_private.tenant_user_daily_usage set used=tenant_user_daily_usage.used+amount
 where user_id=actor and day=today
 and (member.daily_limit is null or tenant_user_daily_usage.used+amount<=member.daily_limit);
 if not found then raise sqlstate 'PT429' using message='Limite diário do usuário atingido.';end if;
 if mode='individual' then
  select individual_daily_limit into service_limit from apoiarcred_private.tenant_permissions
  where tenant_id=company.id and service=service_id;
  insert into apoiarcred_private.tenant_service_daily_usage values(company.id,service_id,today,0) on conflict do nothing;
  update apoiarcred_private.tenant_service_daily_usage set used=tenant_service_daily_usage.used+amount
  where tenant_id=company.id and service=service_id and day=today
   and (service_limit is null or tenant_service_daily_usage.used+amount<=service_limit);
  if not found then raise sqlstate 'PT429' using message='Limite diário deste serviço atingido.';end if;
 end if;
end
$$;
revoke all on function apoiarcred_private.tenant_consume(uuid,text,text,integer) from public,anon,authenticated;

create function public.tenant_context()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('tenant_id',t.id,'name',t.name,'role',m.role,
  'active',t.active and m.active,'daily_limit',t.daily_limit,'user_daily_limit',m.daily_limit,
  'services',(select jsonb_agg(jsonb_build_object('id',p.service,
   'enabled',apoiarcred_private.tenant_can_service(m.user_id,p.service,'read'),
   'allow_individual',apoiarcred_private.tenant_can_service(m.user_id,p.service,'individual'),
   'allow_campaign',apoiarcred_private.tenant_can_service(m.user_id,p.service,'campanha')) order by p.service)
   from apoiarcred_private.tenant_permissions p where p.tenant_id=t.id),
  'actions',(select jsonb_object_agg(a.action,apoiarcred_private.tenant_can_action(m.user_id,a.action))
   from apoiarcred_private.tenant_actions a where a.tenant_id=t.id))
 from apoiarcred_private.tenant_members m
 join apoiarcred_private.tenants t on t.id=m.tenant_id where m.user_id=auth.uid();
$$;
revoke all on function public.tenant_context() from public,anon;
grant execute on function public.tenant_context() to authenticated;
