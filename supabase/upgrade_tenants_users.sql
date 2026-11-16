-- Multi-tenant · etapa 4: usuários da empresa.
-- Quem tem usuarios.gerenciar cria usuários com e-mail e senha provisória (a conta no Auth é
-- criada pela API da VPS), escolhe o papel e ajusta permissões dentro do que a empresa contratou.
-- O usuário troca a senha no primeiro acesso. Aplicar depois de upgrade_tenants_crm.sql.

alter table apoiarcred_private.tenant_members
 add column name text check(name is null or length(btrim(name)) between 1 and 160),
 add column email text check(email is null or length(email)<=254),
 add column must_change_password boolean not null default false;
update apoiarcred_private.tenant_members m set name=p.name,email=p.email
 from apoiarcred_private.user_profiles p where p.user_id=m.user_id;

-- Membro desativado deixa de ver os dados da empresa na hora (sem esperar o token vencer).
create or replace function apoiarcred_private.current_tenant()
returns uuid language sql stable security definer set search_path='' as
$$ select tenant_id from apoiarcred_private.tenant_members where user_id=auth.uid() and active $$;

-- 1. Painel: nome, papel e aviso de troca de senha.
create or replace function public.tenant_context()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'tenant_id',t.id,'tenant_name',t.name,'role',r.code,'role_name',r.name,
  'active',t.active and m.active,'trial_until',t.trial_until,
  'daily_limit',t.daily_limit,
  'used_today',coalesce((select u.used from apoiarcred_private.tenant_daily_usage u where u.tenant_id=t.id and u.day=apoiarcred_private.today_sp()),0),
  'platform_admin',exists(select 1 from apoiarcred_private.platform_admins a where a.user_id=m.user_id),
  'owner',t.legacy_owner_id=m.user_id,
  'must_change_password',m.must_change_password,
  'permissions',coalesce((select jsonb_agg(e.permission_key order by e.permission_key)
    from apoiarcred_private.effective_permissions e where e.user_id=m.user_id),'[]'))
 from apoiarcred_private.tenant_members m
 join apoiarcred_private.tenants t on t.id=m.tenant_id
 join apoiarcred_private.tenant_roles r on r.id=m.role_id
 where m.user_id=auth.uid();
$$;

do $$
declare def text=pg_get_functiondef('apoiarcred_private.access_for(uuid)'::regprocedure);
begin
 if position('''name'',coalesce(p.name,t.name)' in def)=0 or position('''tenant'',public.tenant_context())' in def)=0 then
  raise exception 'access_for mudou; revise a migração';end if;
 def=replace(def,'''name'',coalesce(p.name,t.name)','''name'',coalesce(p.name,m.name,t.name)');
 def=replace(def,'''tenant'',public.tenant_context())',
  '''tenant'',public.tenant_context(),''must_change_password'',coalesce(m.must_change_password,false))');
 execute def;
end $$;

-- 2. Gestão de usuários (chamada pela API da VPS com a sessão de quem administra).
create function apoiarcred_private.tenant_member_json(p_user uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',m.user_id,
  'name',coalesce(m.name,p.name,u.email),'email',coalesce(m.email,p.email,u.email),
  'role',r.code,'role_name',r.name,'active',m.active,'must_change_password',m.must_change_password,
  'owner',t.legacy_owner_id=m.user_id,'created_at',m.created_at,
  'overrides',coalesce((select jsonb_object_agg(o.permission_key,o.allow) from apoiarcred_private.member_overrides o
    where o.tenant_id=m.tenant_id and o.user_id=m.user_id),'{}'),
  'permissions',coalesce((select jsonb_agg(e.permission_key order by e.permission_key)
    from apoiarcred_private.effective_permissions e where e.user_id=m.user_id),'[]'))
 from apoiarcred_private.tenant_members m
 join apoiarcred_private.tenants t on t.id=m.tenant_id
 join apoiarcred_private.tenant_roles r on r.id=m.role_id
 left join apoiarcred_private.user_profiles p on p.user_id=m.user_id
 left join auth.users u on u.id=m.user_id
 where m.user_id=p_user;
$$;

create function public.tenant_users_manage(p_actor uuid,p_action text,p_input jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor apoiarcred_private.tenant_members; actor_role text; company apoiarcred_private.tenants;
 target apoiarcred_private.tenant_members; target_role text; new_role apoiarcred_private.tenant_roles;
 uid uuid; item record; result jsonb;
begin
 select * into actor from apoiarcred_private.tenant_members where user_id=p_actor;
 if actor.user_id is null or not actor.active or not apoiarcred_private.has_permission(p_actor,'usuarios.gerenciar') then
  raise insufficient_privilege using message='Apenas quem gerencia usuários da empresa pode fazer isso.';
 end if;
 select * into company from apoiarcred_private.tenants where id=actor.tenant_id;
 select code into actor_role from apoiarcred_private.tenant_roles where id=actor.role_id;

 if p_action='check' then
  return jsonb_build_object('tenant_id',company.id,'tenant_name',company.name,'actor_role',actor_role,
   'roles',(select jsonb_agg(jsonb_build_object('code',r.code,'name',r.name,
     'permissions',coalesce((select jsonb_agg(rp.permission_key order by rp.permission_key) from apoiarcred_private.role_permissions rp
      join apoiarcred_private.tenant_grants g on g.tenant_id=r.tenant_id and g.permission_key=rp.permission_key
      where rp.role_id=r.id),'[]'))
     order by array_position(array['administrador','gestor','operador','leitura'],r.code))
    from apoiarcred_private.tenant_roles r where r.tenant_id=company.id),
   'catalog',(select jsonb_agg(jsonb_build_object('key',p.key,'description',p.description) order by p.service nulls last,p.key)
    from apoiarcred_private.permissions p join apoiarcred_private.tenant_grants g on g.permission_key=p.key and g.tenant_id=company.id));
 end if;

 if p_action='list' then
  return coalesce((select jsonb_agg(apoiarcred_private.tenant_member_json(m.user_id) order by m.active desc,lower(coalesce(m.name,m.email,'')))
   from apoiarcred_private.tenant_members m where m.tenant_id=company.id),'[]');
 end if;

 if p_action not in ('create','update','reset_password') then raise exception using errcode='22023',message='Ação inválida.';end if;
 uid:=(p_input->>'user_id')::uuid;
 if uid is null then raise exception using errcode='22023',message='Usuário não informado.';end if;

 if p_action='create' then
  if exists(select 1 from apoiarcred_private.tenant_members where user_id=uid) then
   raise exception using errcode='23505',message='Este usuário já pertence a uma empresa.';end if;
  if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 then raise exception using errcode='22023',message='Informe o nome do usuário.';end if;
  select * into new_role from apoiarcred_private.tenant_roles where tenant_id=company.id and code=p_input->>'role';
  if new_role.id is null then raise exception using errcode='22023',message='Papel inválido.';end if;
  if new_role.code='administrador' and actor_role<>'administrador' then
   raise insufficient_privilege using message='Apenas administradores criam outros administradores.';end if;
  insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id,name,email,must_change_password)
   values(company.id,uid,new_role.id,btrim(p_input->>'name'),lower(btrim(p_input->>'email')),true);
 else
  select * into target from apoiarcred_private.tenant_members where user_id=uid and tenant_id=company.id for update;
  if target.user_id is null then raise exception using errcode='P0002',message='Usuário não encontrado nesta empresa.';end if;
  select code into target_role from apoiarcred_private.tenant_roles where id=target.role_id;
  if target_role='administrador' and actor_role<>'administrador' then
   raise insufficient_privilege using message='Apenas administradores alteram outros administradores.';end if;
  if uid=p_actor then raise insufficient_privilege using message='Use a sua conta para trocar a sua senha; papel e acesso são alterados por outro administrador.';end if;
 end if;

 if p_action='reset_password' then
  update apoiarcred_private.tenant_members set must_change_password=true where user_id=uid;
  insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action) values(company.id,p_actor,uid,'usuario.senha_provisoria');
  return apoiarcred_private.tenant_member_json(uid);
 end if;

 if p_action='update' then
  if p_input ? 'name' then
   if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 then raise exception using errcode='22023',message='Informe o nome do usuário.';end if;
   update apoiarcred_private.tenant_members set name=btrim(p_input->>'name') where user_id=uid;
  end if;
  if (p_input ? 'role' and p_input->>'role' is distinct from target_role) or (p_input ? 'active' and (p_input->>'active')::boolean is distinct from target.active) then
   if company.legacy_owner_id=uid then
    raise insufficient_privilege using message='O responsável pela empresa não pode ser desativado nem mudar de papel.';end if;
  end if;
  if p_input ? 'role' then
   select * into new_role from apoiarcred_private.tenant_roles where tenant_id=company.id and code=p_input->>'role';
   if new_role.id is null then raise exception using errcode='22023',message='Papel inválido.';end if;
   if new_role.code='administrador' and actor_role<>'administrador' then
    raise insufficient_privilege using message='Apenas administradores criam outros administradores.';end if;
   update apoiarcred_private.tenant_members set role_id=new_role.id where user_id=uid;
  end if;
  if p_input ? 'active' then
   if jsonb_typeof(p_input->'active')<>'boolean' then raise exception using errcode='22023',message='Situação inválida.';end if;
   update apoiarcred_private.tenant_members set active=(p_input->>'active')::boolean where user_id=uid;
  end if;
 end if;

 -- Ajustes por usuário: substituem os anteriores; só dentro do que a empresa contratou.
 if p_input ? 'overrides' then
  if jsonb_typeof(p_input->'overrides')<>'object' then raise exception using errcode='22023',message='Permissões inválidas.';end if;
  for item in select key,value from jsonb_each(p_input->'overrides') loop
   if jsonb_typeof(item.value)<>'boolean' or not exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=company.id and g.permission_key=item.key) then
    raise exception using errcode='22023',message='Permissão fora do que a empresa contratou: '||item.key;end if;
   if item.key='usuarios.gerenciar' and item.value='true'::jsonb and actor_role<>'administrador' then
    raise insufficient_privilege using message='Apenas administradores liberam a gestão de usuários.';end if;
  end loop;
  delete from apoiarcred_private.member_overrides where tenant_id=company.id and user_id=uid;
  insert into apoiarcred_private.member_overrides(tenant_id,user_id,permission_key,allow)
   select company.id,uid,key,value::boolean from jsonb_each_text(p_input->'overrides');
 end if;

 if not exists(select 1 from apoiarcred_private.tenant_members m join apoiarcred_private.tenant_roles r on r.id=m.role_id
  where m.tenant_id=company.id and m.active and r.code='administrador') then
  raise exception using errcode='22023',message='A empresa precisa de pelo menos um administrador ativo.';end if;

 result:=apoiarcred_private.tenant_member_json(uid);
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(company.id,p_actor,uid,'usuario.'||case p_action when 'create' then 'criado' else 'alterado' end,
   jsonb_build_object('role',result->>'role','active',result->'active','overrides',result->'overrides'));
 return result;
end $$;
revoke all on function public.tenant_users_manage(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.tenant_users_manage(uuid,text,jsonb) to service_role;

-- 3. Troca de senha concluída (a API da VPS só chama depois de o Auth confirmar a nova senha).
create function public.tenant_password_changed(p_actor uuid)
returns void language sql security definer set search_path='' as
$$ update apoiarcred_private.tenant_members set must_change_password=false where user_id=p_actor and must_change_password $$;
revoke all on function public.tenant_password_changed(uuid) from public,anon,authenticated;
grant execute on function public.tenant_password_changed(uuid) to service_role;
