-- Etapa 3a: isolamento entre empresas e escopo de cada papel nas tabelas (RLS) e na autorização.
begin;
create temporary table ta as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() other;
grant select on ta to authenticated;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-access.invalid' from ta,unnest(array[a,b,c,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email,shared_quota,shared_daily_limit)
 select a,'partner','Empresa A',a::text||'@tenant-access.invalid',true,100 from ta
 union all select other,'partner','Empresa B',other::text||'@tenant-access.invalid',true,100 from ta;
insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select m.tenant_id,p.key from ta,unnest(array[a,other]) x join apoiarcred_private.tenant_members m on m.user_id=x
 join apoiarcred_private.permissions p on p.service in ('digimais_saldo_parcela');
-- Company A: Administrador (a), Gestor (b), Operador (c).
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from ta join apoiarcred_private.tenant_members m on m.user_id=ta.a
 cross join lateral (values(ta.b,'gestor'),(ta.c,'operador')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;

-- Each one creates a campaign lot in their own name.
create temporary table ta_lots(owner text,id uuid);
grant select on ta_lots to authenticated;
do $$
declare f ta; who text; uid uuid; lot uuid;
begin
 select * into f from ta;
 foreach who in array array['a','c','other'] loop
  uid:=case who when 'a' then f.a when 'c' then f.c else f.other end;
  perform set_config('request.jwt.claim.sub',uid::text,true);
  lot:=gen_random_uuid();
  insert into public.consulta_lotes(id,user_id,nome,tipo) values(lot,uid,'ACCESS '||who,'campanha');
  insert into ta_lots values(who,lot);
 end loop;
end $$;

set local role authenticated;
do $$
declare f ta; seen text;
begin
 select * into f from ta;
 -- Operador: only what they created.
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 select string_agg(nome,',' order by nome) into seen from public.consulta_lotes where nome like 'ACCESS %';
 if seen is distinct from 'ACCESS c' then raise exception 'Operador sees %',seen;end if;
 -- Gestor: the whole company, nothing from company B.
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 select string_agg(nome,',' order by nome) into seen from public.consulta_lotes where nome like 'ACCESS %';
 if seen is distinct from 'ACCESS a,ACCESS c' then raise exception 'Gestor sees %',seen;end if;
 -- Company B sees only itself.
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 select string_agg(nome,',' order by nome) into seen from public.consulta_lotes where nome like 'ACCESS %';
 if seen is distinct from 'ACCESS other' then raise exception 'Company B sees %',seen;end if;
 -- Company B cannot delete company A rows (nothing visible, nothing deleted).
 delete from public.consulta_lotes where id=(select id from ta_lots where owner='a');
 -- Operador has no dados.excluir: delete is a no-op even on own rows.
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 delete from public.consulta_lotes where id=(select id from ta_lots where owner='c');
 -- Gestor cannot create in a colleague's name.
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 begin
  insert into public.consulta_lotes(id,user_id,nome,tipo) values(gen_random_uuid(),f.c,'ACCESS forged','campanha');
  raise exception 'Created a lot in another user name';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin
 if (select count(*) from public.consulta_lotes where nome in ('ACCESS a','ACCESS c'))<>2 then raise exception 'Unauthorized delete went through';end if;
end $$;
-- Administrador deletes company data (dados.excluir + company scope).
set local role authenticated;
do $$
declare f ta;
begin
 select * into f from ta;
 perform set_config('request.jwt.claim.sub',f.a::text,true);
 delete from public.consulta_lotes where id=(select id from ta_lots where owner='c');
end $$;
reset role;
do $$
declare f ta; r jsonb;
begin
 select * into f from ta;
 if exists(select 1 from public.consulta_lotes where nome='ACCESS c') then raise exception 'Administrador could not delete company row';end if;
 -- Authorization comes from the company: role defaults plus per-user exception.
 perform apoiarcred_private.check_partner_access(f.c,'digimais_saldo_parcela','campanha',false);
 insert into apoiarcred_private.member_overrides select m.tenant_id,f.c,'consulta.digimais.campanha',false
  from apoiarcred_private.tenant_members m where m.user_id=f.c;
 begin
  perform apoiarcred_private.check_partner_access(f.c,'digimais_saldo_parcela','campanha',false);
  raise exception 'Override deny ignored by consultation check';
 exception when insufficient_privilege then null;end;
 begin
  perform apoiarcred_private.check_partner_access(f.c,'tjba_margem','individual',false);
  raise exception 'Service outside the company ceiling accepted';
 exception when insufficient_privilege then null;end;
 -- Quota is shared by the company: what c spends shows for a.
 perform apoiarcred_private.check_partner_access(f.c,'digimais_saldo_parcela','individual',true);
 r:=apoiarcred_private.access_for(f.a);
 if r->>'remaining' is distinct from '99' or r->>'shared_quota' is distinct from 'true' then raise exception 'Company quota not shared: %',r;end if;
 if (apoiarcred_private.access_for(f.other)->>'remaining') is distinct from '100' then raise exception 'Quota leaked across companies';end if;
 if (apoiarcred_private.access_for(f.c)->'services'->0->>'allow_campaign')::boolean then raise exception 'Panel shows a denied permission';end if;
 if apoiarcred_private.is_admin(f.a) then raise exception 'Company admin became platform admin';end if;
end $$;
rollback;
