-- clientes.importar: o Operador não importa base de clientes; Gestor e Administrador importam.
begin;
create temporary table ts as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c;
grant select on ts to authenticated;
insert into auth.users(id,aud,role,email) select x,'authenticated','authenticated',x::text||'@tenant-sec.invalid' from ts,unnest(array[a,b,c]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select a,'partner','Empresa A',a::text||'@x.invalid' from ts;
insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select m.tenant_id,p.key from ts join apoiarcred_private.tenant_members m on m.user_id=ts.a
 join apoiarcred_private.permissions p on p.service='tjba_margem' on conflict do nothing;
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from ts join apoiarcred_private.tenant_members m on m.user_id=ts.a
 cross join lateral (values(ts.b,'gestor'),(ts.c,'operador')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;
set local role authenticated;
do $$
declare f ts; who uuid; r jsonb; rows jsonb='[{"cpf":"00000000892","numero_matricula":"000123"}]';
begin
 select * into f from ts;
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 begin perform public.crm_import_and_start(gen_random_uuid(),'BA','saeb',array['consigx_margem'],rows);raise exception 'Operador imported';
 exception when insufficient_privilege then if sqlerrm not like '%importar bases de clientes%' then raise; end if;end;
 begin perform public.crm_import_clients('BA','saeb',false,rows);raise exception 'Operador imported clients';
 exception when insufficient_privilege then null;end;
 r:=public.crm_preview_import('BA','saeb',array['consigx_margem'],rows);
 if (r->>'valido')::boolean or r->'erros'->0->>'mensagem' not like '%importar bases de clientes%' then raise exception 'Preview let Operador through: %',r;end if;
 foreach who in array array[f.b,f.a] loop
  perform set_config('request.jwt.claim.sub',who::text,true);
  r:=public.crm_preview_import('BA','saeb',array['consigx_margem'],rows);
  if not (r->>'valido')::boolean then raise exception 'Import blocked for %: %',who,r;end if;
 end loop;
end $$;
reset role;
do $$begin
 if exists(select 1 from pg_proc where proname in ('today_sp','consult_key') and not coalesce(proconfig::text,'') like '%search_path%') then
  raise exception 'search_path not fixed';end if;
end $$;
rollback;
