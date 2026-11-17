-- Excluir usuário (os dados dele vão junto; recursos da empresa ficam) e excluir parceiro (a empresa inteira).
begin;
create temporary table td as select gen_random_uuid() admin,gen_random_uuid() owner,gen_random_uuid() op,gen_random_uuid() gestor,gen_random_uuid() other;
grant select on td to authenticated,service_role;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-delete.invalid' from td,unnest(array[admin,owner,op,gestor,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select admin,'admin','Equipe',admin::text||'@x.invalid' from td;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select owner,'partner','Empresa A',owner::text||'@x.invalid' from td
 union all select other,'partner','Empresa B',other::text||'@x.invalid' from td;
insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select m.tenant_id,p.key from td,unnest(array[owner,other]) x join apoiarcred_private.tenant_members m on m.user_id=x
 join apoiarcred_private.permissions p on p.service='digimais_saldo_parcela';
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from td join apoiarcred_private.tenant_members m on m.user_id=td.owner
 cross join lateral (values(td.op,'operador'),(td.gestor,'gestor')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;
insert into apoiarcred_private.member_overrides select m.tenant_id,m.user_id,'funil.configurar',true
 from apoiarcred_private.tenant_members m where m.user_id=(select op from td);

-- Each one creates data; the Operador also creates a company stage that colleagues' cards use.
insert into public.crm_cadastros(user_id,cpf,nome,ultima_atividade)
 select x,'00000000191','CLIENTE',now() from td,unnest(array[owner,op,other]) x;
set local role authenticated;
do $$
declare f td; who uuid; stage uuid; card uuid;
begin
 select * into f from td;
 foreach who in array array[f.owner,f.op,f.other] loop
  perform set_config('request.jwt.claim.sub',who::text,true);
  insert into public.consulta_lotes(id,user_id,nome,tipo) values(gen_random_uuid(),who,'DELETE '||who,'individual');
  insert into public.crm_oportunidades(cpf,nome,produto) values('00000000191','CLIENTE','recompra');
 end loop;
 perform set_config('request.jwt.claim.sub',f.op::text,true);
 stage:=(public.crm_salvar_etapa(null,'{"nome":"Criada pelo operador","posicao":15}')->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 select id into card from public.crm_oportunidades where user_id=f.owner;
 perform public.crm_mover_etapa(card,stage,(select etapa_id from public.crm_oportunidades where id=card));
end $$;
reset role;

set local role service_role;
do $$
declare f td; r jsonb;
begin
 select * into f from td;
 -- Protections: not yourself, not the owner, Gestor cannot delete without usuarios.gerenciar.
 begin perform public.tenant_user_delete(f.owner,f.owner);raise exception 'Deleted self';exception when insufficient_privilege then null;end;
 begin perform public.tenant_user_delete(f.gestor,f.op);raise exception 'Gestor deleted a user';exception when insufficient_privilege then null;end;
 begin perform public.tenant_user_delete(f.other,f.op);raise exception 'Other company deleted a user';exception when insufficient_privilege or no_data_found then null;end;
 r:=public.tenant_user_delete(f.owner,f.op);
 if (r->>'registros')::int<2 then raise exception 'User data not deleted: %',r;end if;
end $$;
reset role;

do $$
declare f td;
begin
 select * into f from td;
 if exists(select 1 from apoiarcred_private.tenant_members where user_id=f.op) then raise exception 'Member still listed';end if;
 if exists(select 1 from public.consulta_lotes where user_id=f.op) or exists(select 1 from public.crm_oportunidades where user_id=f.op)
  or exists(select 1 from public.crm_cadastros where user_id=f.op) then raise exception 'Deleted user data remains';end if;
 -- The company keeps the stage the Operador created, and the owner's card stays in it.
 if (select e.user_id from public.crm_oportunidades o join public.crm_etapas e on e.id=o.etapa_id where o.user_id=f.owner)<>f.owner then
  raise exception 'Company stage not handed over';end if;
 if not exists(select 1 from public.consulta_lotes where user_id=f.owner) then raise exception 'Colleague data touched';end if;
 if not exists(select 1 from apoiarcred_private.tenant_audit where action='usuario.excluido') then raise exception 'Audit missing';end if;
 -- The login can now be removed without touching anything else.
 delete from auth.users where id=f.op;
end $$;

set local role service_role;
do $$
declare f td; r jsonb;
begin
 select * into f from td;
 begin perform public.admin_partner_delete(f.owner,f.other,'Empresa B');raise exception 'Partner deleted a company';
 exception when insufficient_privilege then null;end;
 begin perform public.admin_partner_delete(f.admin,f.owner,'Empresa errada');raise exception 'Deleted without the right name';
 exception when invalid_parameter_value then null;end;
 r:=public.admin_partner_delete(f.admin,f.owner,'Empresa A');
 if jsonb_array_length(r->'usuarios')<>2 then raise exception 'Members to remove: %',r;end if;
end $$;
reset role;

do $$
declare f td;
begin
 select * into f from td;
 if exists(select 1 from apoiarcred_private.tenants where name='Empresa A') then raise exception 'Company still exists';end if;
 if exists(select 1 from public.consulta_lotes where user_id in (f.owner,f.gestor)) or exists(select 1 from public.crm_etapas e
  where e.user_id in (f.owner,f.gestor,f.op)) then raise exception 'Company data remains';end if;
 if not exists(select 1 from public.consulta_lotes where user_id=f.other) then raise exception 'Other company touched';end if;
 delete from auth.users where id in (f.owner,f.gestor);
 if exists(select 1 from apoiarcred_private.user_profiles where user_id=f.owner) then raise exception 'Profile remains';end if;
end $$;
rollback;
