-- Campanhas da empresa: Gestor pausa, retoma e repete falhas da campanha de um colega;
-- Leitura e Operador (em campanha alheia) não; outra empresa nunca.
begin;
create temporary table tk as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() l,gen_random_uuid() other,gen_random_uuid() lot;
grant select on tk to authenticated;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-camp.invalid' from tk,unnest(array[a,b,c,l,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
 select a,'partner','Empresa A',a::text||'@x.invalid' from tk union all select other,'partner','Empresa B',other::text||'@x.invalid' from tk;
insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select m.tenant_id,p.key from tk,unnest(array[a,other]) x join apoiarcred_private.tenant_members m on m.user_id=x
 join apoiarcred_private.permissions p on p.service='digimais_saldo_parcela';
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from tk join apoiarcred_private.tenant_members m on m.user_id=tk.a
 cross join lateral (values(tk.b,'gestor'),(tk.c,'operador'),(tk.l,'leitura')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;

-- The Operador's campaign with one failed consultation.
insert into public.consulta_lotes(id,user_id,nome,tipo) select lot,c,'CAMP C','campanha' from tk;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status)
 select lot,c,'Falhou','00000000191','11999999999','erro' from tk;

set local role authenticated;
do $$
declare f tk;
begin
 select * into f from tk;
 -- Gestor: pause, resume and retry a colleague's campaign.
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 perform public.set_campaign_paused(f.lot,'digimais_saldo_parcela',true);
 perform public.set_campaign_paused(f.lot,'digimais_saldo_parcela',false);
 if public.retry_consulta_campaign(f.lot)<>1 then raise exception 'Gestor retry did not requeue';end if;
 -- Leitura sees but cannot act; another company cannot touch it.
 foreach f.a in array array[f.l,f.other] loop
  perform set_config('request.jwt.claim.sub',f.a::text,true);
  begin perform public.set_campaign_paused(f.lot,'digimais_saldo_parcela',true);raise exception 'Paused by %',f.a;
  exception when insufficient_privilege then null;end;
  begin perform public.retry_consulta_campaign(f.lot);raise exception 'Retried by %',f.a;
  exception when insufficient_privilege then null;end;
 end loop;
 -- The owner still controls their own campaign.
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 perform public.set_campaign_paused(f.lot,'digimais_saldo_parcela',true);
end $$;
reset role;
do $$begin
 if not (select paused from public.consulta_lotes where id=(select lot from tk)) then raise exception 'Owner pause lost';end if;
 if (select status from public.consulta_jobs where lote_id=(select lot from tk))<>'aguardando' then raise exception 'Retry not applied';end if;
end $$;
rollback;
