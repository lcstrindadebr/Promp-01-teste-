-- Fundação multi-tenant: provisionamento, teto, papéis, exceções, visibilidade, cota, claims e tenant_id.
begin;
create temporary table tf as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() other;
grant select on tf to authenticated;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-test.invalid' from tf,unnest(array[a,b,c,other]) x;

-- Profiles created by the current partner screen provision a company each, kept in sync with permissions.
insert into apoiarcred_private.user_profiles(user_id,role,name,email,shared_quota,shared_daily_limit)
 select a,'partner','Empresa A',a::text||'@tenant-test.invalid',false,null from tf
 union all select other,'partner','Empresa B',other::text||'@tenant-test.invalid',true,50 from tf;
insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,allow_campaign,daily_limit)
 select a,'digimais_saldo_parcela',true,true,true,1000 from tf
 union all select a,'tjba_margem',false,false,false,0 from tf;

do $$
declare ta uuid; tb uuid;
begin
 select tenant_id into ta from apoiarcred_private.tenant_members where user_id=(select a from tf);
 select tenant_id into tb from apoiarcred_private.tenant_members where user_id=(select other from tf);
 if ta is null or tb is null or ta=tb then raise exception 'Each profile must get its own company';end if;
 if (select daily_limit from apoiarcred_private.tenants where id=ta)<>1000 then raise exception 'Individual limit must become the company quota';end if;
 if (select daily_limit from apoiarcred_private.tenants where id=tb)<>50 then raise exception 'Shared quota must become the company quota';end if;
 if not exists(select 1 from apoiarcred_private.tenant_grants where tenant_id=ta and permission_key='consulta.digimais.campanha')
  or exists(select 1 from apoiarcred_private.tenant_grants where tenant_id=ta and permission_key like 'consulta.consigx.%')
  or exists(select 1 from apoiarcred_private.tenant_grants where tenant_id=ta and permission_key='integracoes') then
  raise exception 'Company ceiling must mirror the partner permissions';end if;
 if (select count(*) from apoiarcred_private.tenant_roles where tenant_id=ta)<>4 then raise exception 'Four built-in roles expected';end if;
 -- Changing permissions in the current screen updates the ceiling.
 update apoiarcred_private.partner_permissions set enabled=false where user_id=(select a from tf) and service='digimais_saldo_parcela';
 if exists(select 1 from apoiarcred_private.tenant_grants where tenant_id=ta and permission_key like 'consulta.digimais.%') then raise exception 'Ceiling not resynced';end if;
 update apoiarcred_private.partner_permissions set enabled=true where user_id=(select a from tf) and service='digimais_saldo_parcela';
 begin
  insert into apoiarcred_private.tenant_roles(tenant_id,code,name,builtin) values(ta,'supervisor','Supervisor',false);
  raise exception 'Custom role accepted';
 exception when check_violation then null;end;
end $$;

-- Two more members of company A: a Gestor and an Operador.
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from tf
 join apoiarcred_private.tenant_members m on m.user_id=tf.a
 cross join lateral (values(tf.b,'gestor'),(tf.c,'operador')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;

do $$
declare f tf;
begin
 select * into f from tf;
 if not apoiarcred_private.has_permission(f.b,'dados.ver_empresa') or apoiarcred_private.has_permission(f.c,'dados.ver_empresa') then
  raise exception 'Role defaults wrong (Gestor sees company, Operador only own)';end if;
 if apoiarcred_private.has_permission(f.c,'clientes.exportar') then raise exception 'Operador must not export by default';end if;
 -- Per-user exception grants inside the ceiling...
 insert into apoiarcred_private.member_overrides select m.tenant_id,f.c,'clientes.exportar',true from apoiarcred_private.tenant_members m where m.user_id=f.c;
 if not apoiarcred_private.has_permission(f.c,'clientes.exportar') then raise exception 'Override allow ignored';end if;
 -- ...and never above it.
 insert into apoiarcred_private.member_overrides select m.tenant_id,f.c,'consulta.consigx.individual',true from apoiarcred_private.tenant_members m where m.user_id=f.c;
 if apoiarcred_private.has_permission(f.c,'consulta.consigx.individual') then raise exception 'Override exceeded the company ceiling';end if;
 insert into apoiarcred_private.member_overrides select m.tenant_id,f.b,'oportunidade.mover',false from apoiarcred_private.tenant_members m where m.user_id=f.b;
 if apoiarcred_private.has_permission(f.b,'oportunidade.mover') then raise exception 'Override deny ignored';end if;
 -- Inactive member or company loses everything.
 update apoiarcred_private.tenant_members set active=false where user_id=f.c;
 if apoiarcred_private.has_permission(f.c,'consulta.digimais.individual') then raise exception 'Inactive member kept access';end if;
 update apoiarcred_private.tenant_members set active=true where user_id=f.c;
end $$;

-- Visibility rule of stage 3 (same company and (company scope or own row)), as each user.
create temporary table tf_rows as select (select tenant_id from apoiarcred_private.tenant_members where user_id=a) ta,
 (select tenant_id from apoiarcred_private.tenant_members where user_id=other) tb from tf;
grant select on tf_rows to authenticated;
set local role authenticated;
do $$
declare f tf; r tf_rows;
begin
 select * into f from tf;select * into r from tf_rows;
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 if not apoiarcred_private.can_see(r.ta,f.c) then raise exception 'Operador cannot see own row';end if;
 if apoiarcred_private.can_see(r.ta,f.a) then raise exception 'Operador sees colleague row';end if;
 if apoiarcred_private.can_see(r.tb,f.c) then raise exception 'Row of another company visible';end if;
 if not public.can('consulta.digimais.campanha') or public.can('usuarios.gerenciar') then raise exception 'can() wrong for Operador';end if;
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 if not apoiarcred_private.can_see(r.ta,f.a) then raise exception 'Gestor cannot see company row';end if;
 if apoiarcred_private.can_see(r.tb,f.other) then raise exception 'Gestor sees another company';end if;
 if (public.tenant_context()->>'role')<>'gestor' or (public.tenant_context()->>'tenant_id')::uuid<>r.ta then raise exception 'tenant_context wrong';end if;
end $$;
do $$begin
 perform 1 from apoiarcred_private.tenant_members;
 raise exception 'authenticated can read tenant tables';
exception when insufficient_privilege then null;end $$;
reset role;

-- Company quota: one daily limit for everything.
do $$
declare f tf; blocked boolean:=false;
begin
 select * into f from tf;
 update apoiarcred_private.tenants set daily_limit=3 where id=(select ta from tf_rows);
 perform apoiarcred_private.tenant_consume(f.c,'consulta.digimais.campanha',2);
 perform apoiarcred_private.tenant_consume(f.b,'consulta.digimais.individual',1);
 begin perform apoiarcred_private.tenant_consume(f.a,'consulta.digimais.individual',1);
 exception when sqlstate 'PT429' then blocked:=true;end;
 if not blocked then raise exception 'Company quota exceeded';end if;
 begin perform apoiarcred_private.tenant_consume(f.c,'consulta.consigx.individual',1);raise exception 'Consumed without permission';
 exception when insufficient_privilege then null;end;
end $$;

-- Token claims hook.
do $$
declare f tf; claims jsonb;
begin
 select * into f from tf;
 claims:=public.custom_access_token_hook(jsonb_build_object('user_id',f.c,'claims',jsonb_build_object('sub',f.c)))->'claims';
 if claims->>'tenant_role'<>'operador' or claims->>'tenant_scope'<>'proprios' or (claims->>'tenant_id')::uuid<>(select ta from tf_rows) then
  raise exception 'Hook claims wrong: %',claims;end if;
 claims:=public.custom_access_token_hook(jsonb_build_object('user_id',f.b,'claims','{}'::jsonb))->'claims';
 if claims->>'tenant_scope'<>'empresa' then raise exception 'Gestor scope claim wrong';end if;
 if has_function_privilege('authenticated','public.custom_access_token_hook(jsonb)','execute') then raise exception 'Hook callable by users';end if;
end $$;

-- New rows get tenant_id from their creator; creating data does not change who owns existing rows.
-- (Until stage 3 the legacy lot guard still requires a legacy profile, so the company owner creates it.)
insert into public.consulta_lotes(id,user_id,nome,tipo) select gen_random_uuid(),a,'TENANT TEST','campanha' from tf;
do $$begin
 if (select tenant_id from public.consulta_lotes where nome='TENANT TEST')<>(select ta from tf_rows) then raise exception 'tenant_id not filled on insert';end if;
end $$;
rollback;
