-- Consultas e campanhas do painel: o Gestor vê as da empresa, o Operador só as dele, outra empresa nada.
begin;
create temporary table tq as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() other;
grant select on tq to authenticated;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-painel.invalid' from tq,unnest(array[a,b,c,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
 select a,'partner','Empresa A',a::text||'@x.invalid' from tq union all select other,'partner','Empresa B',other::text||'@x.invalid' from tq;
insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select m.tenant_id,p.key from tq,unnest(array[a,other]) x join apoiarcred_private.tenant_members m on m.user_id=x
 join apoiarcred_private.permissions p on p.service='digimais_saldo_parcela';
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from tq join apoiarcred_private.tenant_members m on m.user_id=tq.a
 cross join lateral (values(tq.b,'gestor'),(tq.c,'operador')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;

set local role authenticated;
do $$
declare f tq; who uuid; names text;
begin
 select * into f from tq;
 foreach who in array array[f.c,f.other] loop
  perform set_config('request.jwt.claim.sub',who::text,true);
  insert into public.consulta_lotes(id,user_id,nome,tipo) values(gen_random_uuid(),who,'PAINEL '||who,'campanha');
 end loop;
end $$;
reset role;
-- Rows written in this same transaction are not in the sync snapshot yet; mark them as already published.
alter table public.consulta_lotes disable trigger painel_marcar_mudanca;
update public.consulta_lotes set sync_xid=null where nome like 'PAINEL %';
alter table public.consulta_lotes enable trigger painel_marcar_mudanca;
set local role authenticated;
do $$
declare f tq; names text;
begin
 select * into f from tq;
 -- Gestor: sees the Operador's campaign in the panel sync.
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 select string_agg(e->'dados'->>'nome',',') into names from jsonb_array_elements(public.painel_consultas_sync()->'rows') e where e->>'origem'='consulta_lotes';
 if names is distinct from 'PAINEL '||f.c then raise exception 'Gestor panel sees: %',names;end if;
 -- Operador: own only; company B: own only.
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 if (select count(*) from jsonb_array_elements(public.painel_consultas_sync()->'rows') e where e->>'origem'='consulta_lotes')<>1 then
  raise exception 'Operador panel wrong';end if;
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 select string_agg(e->'dados'->>'nome',',') into names from jsonb_array_elements(public.painel_consultas_sync()->'rows') e where e->>'origem'='consulta_lotes';
 if names is distinct from 'PAINEL '||f.other then raise exception 'Company B panel sees: %',names;end if;
end $$;
reset role;
rollback;
