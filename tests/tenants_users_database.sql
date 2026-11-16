-- Etapa 4: usuários da empresa criados com senha provisória, papéis, ajustes e regras de proteção.
begin;
create temporary table tu as select gen_random_uuid() owner,gen_random_uuid() gestor,gen_random_uuid() novo,
 gen_random_uuid() outro,gen_random_uuid() other_owner;
grant select on tu to authenticated,service_role;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-users.invalid' from tu,unnest(array[owner,gestor,novo,outro,other_owner]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
 select owner,'partner','Empresa A',owner::text||'@tenant-users.invalid' from tu
 union all select other_owner,'partner','Empresa B',other_owner::text||'@tenant-users.invalid' from tu;
insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select m.tenant_id,p.key from tu join apoiarcred_private.tenant_members m on m.user_id=tu.owner
 join apoiarcred_private.permissions p on p.service='digimais_saldo_parcela';
update apoiarcred_private.tenants set daily_limit=10 where legacy_owner_id=(select owner from tu);

set local role service_role;
do $$
declare f tu; r jsonb;
begin
 select * into f from tu;
 r:=public.tenant_users_manage(f.owner,'check');
 if r->>'actor_role'<>'administrador' or jsonb_array_length(r->'roles')<>4
  or exists(select 1 from jsonb_array_elements(r->'catalog') c where c->>'key' like 'consulta.consigx.%') then
  raise exception 'check wrong: %',r;end if;
 -- Gestor created by the owner, with a temporary password to change.
 r:=public.tenant_users_manage(f.owner,'create',jsonb_build_object('user_id',f.gestor,'email','GESTOR@Empresa.invalid','name','Gestor A','role','gestor'));
 if r->>'role'<>'gestor' or not (r->>'must_change_password')::boolean or r->>'email'<>'gestor@empresa.invalid' then raise exception 'create wrong: %',r;end if;
 -- Only administrators manage users by default.
 begin perform public.tenant_users_manage(f.gestor,'list');raise exception 'Gestor managed users';
 exception when insufficient_privilege then null;end;
 -- Operador with an exception inside the ceiling; outside the ceiling is refused.
 r:=public.tenant_users_manage(f.owner,'create',jsonb_build_object('user_id',f.novo,'email','op@empresa.invalid','name','Operador A','role','operador',
  'overrides',jsonb_build_object('clientes.exportar',true,'consulta.digimais.campanha',false)));
 if not (r->'permissions') ? 'clientes.exportar' or (r->'permissions') ? 'consulta.digimais.campanha' then
  raise exception 'Overrides not applied';end if;
 begin
  perform public.tenant_users_manage(f.owner,'update',jsonb_build_object('user_id',f.novo,'overrides',jsonb_build_object('consulta.consigx.individual',true)));
  raise exception 'Override above ceiling accepted';
 exception when invalid_parameter_value then null;end;
 -- A member of another company cannot be added or managed.
 begin perform public.tenant_users_manage(f.owner,'create',jsonb_build_object('user_id',f.other_owner,'email','x@y.invalid','name','X','role','operador'));
  raise exception 'Member of another company added';
 exception when unique_violation then null;end;
 begin perform public.tenant_users_manage(f.owner,'update',jsonb_build_object('user_id',f.other_owner,'active',false));
  raise exception 'Managed another company';
 exception when no_data_found then null;end;
 -- Gestor promoted to manage users still cannot create administrators or touch them.
 perform public.tenant_users_manage(f.owner,'update',jsonb_build_object('user_id',f.gestor,'overrides',jsonb_build_object('usuarios.gerenciar',true)));
 begin perform public.tenant_users_manage(f.gestor,'create',jsonb_build_object('user_id',f.outro,'email','o@e.invalid','name','Outro','role','administrador'));
  raise exception 'Gestor created an administrator';
 exception when insufficient_privilege then null;end;
 begin perform public.tenant_users_manage(f.gestor,'reset_password',jsonb_build_object('user_id',f.owner));
  raise exception 'Gestor reset the administrator password';
 exception when insufficient_privilege then null;end;
 -- The company owner is protected; nobody manages themselves here.
 begin perform public.tenant_users_manage(f.owner,'update',jsonb_build_object('user_id',f.owner,'active',false));
  raise exception 'Self change accepted';
 exception when insufficient_privilege then null;end;
 -- Reset password flags the user; the change clears it.
 perform public.tenant_users_manage(f.owner,'reset_password',jsonb_build_object('user_id',f.novo));
 perform public.tenant_password_changed(f.gestor);
 if (select must_change_password from apoiarcred_private.tenant_members where user_id=f.gestor) then raise exception 'Flag not cleared';end if;
 if not (select must_change_password from apoiarcred_private.tenant_members where user_id=f.novo) then raise exception 'Flag cleared for the wrong user';end if;
 if (select count(*) from apoiarcred_private.tenant_audit a join apoiarcred_private.tenant_members m on m.tenant_id=a.tenant_id
  where m.user_id=f.owner)<4 then raise exception 'Audit missing';end if;
end $$;
reset role;

-- The new member (no legacy profile) works through the company: sees the flag, consults, then is deactivated.
set local role authenticated;
do $$
declare f tu; r jsonb;
begin
 select * into f from tu;
 perform set_config('request.jwt.claim.sub',f.novo::text,true);
 r:=public.my_access();
 if not (r->>'must_change_password')::boolean or r->>'name'<>'Operador A' or not (r->'tenant'->>'must_change_password')::boolean then
  raise exception 'Panel does not get the password flag: %',r;end if;
 perform public.create_individual_consulta('{"nome":"MEMBRO","cpf":"00000000191","telefone":"11999999999"}');
 if (select count(*) from public.consulta_lotes where nome<>'')<1 then raise exception 'Member cannot see own consultation';end if;
end $$;
reset role;
update apoiarcred_private.tenant_members set active=false where user_id=(select novo from tu);
set local role authenticated;
do $$
declare f tu;
begin
 select * into f from tu;
 perform set_config('request.jwt.claim.sub',f.novo::text,true);
 if exists(select 1 from public.consulta_lotes) then raise exception 'Deactivated member still reads data';end if;
 begin perform public.create_individual_consulta('{"nome":"MEMBRO","cpf":"00000000272","telefone":"11999999999"}');
  raise exception 'Deactivated member consulted';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin
 if has_function_privilege('authenticated','public.tenant_users_manage(uuid,text,jsonb)','execute')
  or has_function_privilege('authenticated','public.tenant_password_changed(uuid)','execute') then raise exception 'User management exposed';end if;
end $$;
rollback;
