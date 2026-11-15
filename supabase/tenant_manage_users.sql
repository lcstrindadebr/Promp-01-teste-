-- Run after tenant_foundation.sql. The VPS verifies the session before calling this RPC.
create function public.tenant_manage_users(actor uuid, operation text, input jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 company uuid;
 target uuid;
 member apoiarcred_private.tenant_members;
 new_role text;
 new_active boolean;
 new_limit integer;
 rules jsonb;
 rule record;
 profile_name text;
begin
 select m.tenant_id into company
 from apoiarcred_private.tenant_members m join apoiarcred_private.tenants t on t.id=m.tenant_id
 where m.user_id=actor and m.role='admin' and m.active and t.active for update of t;
 if company is null or not apoiarcred_private.tenant_can_action(actor,'users') then
  raise insufficient_privilege;
 end if;
 if operation='list' then
  return jsonb_build_object(
   'users',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.user_id,'name',p.name,'email',p.email,'role',m.role,'active',m.active,
    'daily_limit',m.daily_limit,'services',(select coalesce(jsonb_agg(to_jsonb(u)-'tenant_id'-'user_id'),'[]')
     from apoiarcred_private.tenant_user_permissions u where u.user_id=m.user_id)
   ) order by p.name,p.email),'[]')
   from apoiarcred_private.tenant_members m join apoiarcred_private.user_profiles p on p.user_id=m.user_id
   where m.tenant_id=company),
   'services',(select jsonb_agg(to_jsonb(s)-'tenant_id' order by s.service)
   from apoiarcred_private.tenant_permissions s where s.tenant_id=company));
 end if;
 if operation='check' then return jsonb_build_object('tenant_id',company);end if;
 if operation is null or operation not in ('create','update') then raise invalid_parameter_value;end if;
 target:=(input->>'id')::uuid;
 new_role:=input->>'role';
 new_active:=(input->>'active')::boolean;
 new_limit:=(input->>'daily_limit')::integer;
 profile_name:=btrim(input->>'name');
 rules:=input->'services';
 if target is null or new_role is null or new_role not in ('admin','operator')
  or jsonb_typeof(input->'active') is distinct from 'boolean'
  or coalesce(length(profile_name),0) not between 1 and 160
  or (new_limit is not null and new_limit not between 0 and 100000)
  or jsonb_typeof(rules) is distinct from 'array' then raise invalid_parameter_value;end if;
 if jsonb_array_length(rules)<>3 or (select count(distinct x->>'service') from jsonb_array_elements(rules) x)<>3 then
  raise invalid_parameter_value;
 end if;
 for rule in select x.*,s.enabled as tenant_enabled,s.allow_individual as tenant_individual,s.allow_campaign as tenant_campaign
  from jsonb_to_recordset(rules) x(service text,enabled boolean,allow_individual boolean,allow_campaign boolean)
  left join apoiarcred_private.tenant_permissions s on s.tenant_id=company and s.service=x.service
 loop
  if rule.tenant_enabled is null or rule.enabled is null or rule.allow_individual is null or rule.allow_campaign is null
   or (rule.enabled and not rule.tenant_enabled)
   or (rule.allow_individual and (not rule.enabled or not rule.tenant_individual))
   or (rule.allow_campaign and (not rule.enabled or not rule.tenant_campaign)) then
   raise invalid_parameter_value using message='Permissões fora dos serviços liberados para a empresa.';
  end if;
 end loop;
 select * into member from apoiarcred_private.tenant_members where user_id=target;
 if operation='create' then
  if member.user_id is not null then raise insufficient_privilege;end if;
  insert into apoiarcred_private.tenant_members(user_id,tenant_id,role,active,daily_limit)
  values(target,company,new_role,new_active,new_limit);
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,created_by)
  select id,'partner',profile_name,email,new_active,actor from auth.users where id=target and email is not null;
  if not found then raise invalid_parameter_value;end if;
 else
  if member.tenant_id is distinct from company then raise insufficient_privilege;end if;
  if member.active and member.role='admin' and (not new_active or new_role<>'admin')
    and not exists(select 1 from apoiarcred_private.tenant_members
    where tenant_id=company and user_id<>target and role='admin' and active) then
   raise invalid_parameter_value using message='A empresa precisa de pelo menos um administrador ativo.';
  end if;
  update apoiarcred_private.tenant_members set active=new_active,role=new_role,daily_limit=new_limit where user_id=target;
  update apoiarcred_private.user_profiles set name=profile_name,updated_at=now() where user_id=target;
 end if;
 insert into apoiarcred_private.tenant_user_permissions
 select company,target,x.service,x.enabled,x.allow_individual,x.allow_campaign
 from jsonb_to_recordset(rules) x(service text,enabled boolean,allow_individual boolean,allow_campaign boolean)
 on conflict(user_id,service) do update set enabled=excluded.enabled,
 allow_individual=excluded.allow_individual,allow_campaign=excluded.allow_campaign;
 insert into apoiarcred_private.tenant_user_actions
 select company,target,action,enabled and new_role='admin'
 from apoiarcred_private.tenant_actions where tenant_id=company and action='users'
 on conflict(user_id,action) do update set enabled=excluded.enabled;
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
 values(company,actor,target,operation,input-'password');
 return jsonb_build_object('id',target);
end $$;
revoke all on function public.tenant_manage_users(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.tenant_manage_users(uuid,text,jsonb) to service_role;
