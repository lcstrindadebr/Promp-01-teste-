-- Etapa 5: acesso ConsigX, Digi+ pela API e integrações pertencem à empresa.
begin;
create temporary table tr as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() other,null::uuid hook,null::uuid token;
grant select,update on tr to authenticated,service_role;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-res.invalid' from tr,unnest(array[a,b,c,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email,allow_integrations,shared_quota,shared_daily_limit)
 select a,'partner','Empresa A',a::text||'@tenant-res.invalid',true,true,100 from tr
 union all select other,'partner','Empresa B',other::text||'@tenant-res.invalid',true,true,100 from tr;
insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,allow_campaign,daily_limit)
 select x,s,true,true,true,0 from tr,unnest(array[a,other]) x,unnest(array['digimais_saldo_parcela','tjba_margem']) s;
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from tr join apoiarcred_private.tenant_members m on m.user_id=tr.a
 cross join lateral (values(tr.b,'gestor'),(tr.c,'operador')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;
-- The Gestor also takes care of integrations.
insert into apoiarcred_private.member_overrides select m.tenant_id,m.user_id,'integracoes',true
 from apoiarcred_private.tenant_members m where m.user_id=(select b from tr);

set local role authenticated;
do $$
declare f tr; r jsonb;
begin
 select * into f from tr;
 -- ConsigX: the administrator registers the company access; the Operador cannot change it but sees it.
 perform set_config('request.jwt.claim.sub',f.a::text,true);
 perform public.save_tjba_credentials('empresa-a','senha-a-do-not-use',true);
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 r:=public.tjba_credentials_status();
 if not (r->>'configured')::boolean or r->>'username'<>'empresa-a' or (r->>'can_edit')::boolean then raise exception 'Operador status wrong: %',r;end if;
 begin perform public.save_tjba_credentials('outro','x',true);raise exception 'Operador changed the company access';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 if (public.tjba_credentials_status()->>'configured')::boolean then raise exception 'Company B sees company A access';end if;
 -- Integrations: the administrator creates; the Gestor (with integracoes) manages; the Operador cannot.
 perform set_config('request.jwt.claim.sub',f.a::text,true);
 r:=public.manage_webhooks('create','{"name":"Empresa A","url":"https://example.com/hook","scope":"all","events":["consulta.finalizada"],"statuses":["concluida"],"client_filter":"all"}');
 update tr set hook=(r->>'id')::uuid;
 r:=public.manage_api_tokens('create','{"name":"ERP","scopes":["read"]}');
 update tr set token=(r->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 if jsonb_array_length(public.manage_webhooks('list'))<>1 then raise exception 'Gestor does not see the company webhook';end if;
 r:=public.manage_api_tokens('list');
 if jsonb_array_length(r)<>1 or r->0->>'created_by'<>'Empresa A' then raise exception 'Gestor token list wrong: %',r;end if;
 perform public.manage_api_tokens('revoke',jsonb_build_object('id',(select token from tr)));
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 begin perform public.manage_webhooks('list');raise exception 'Operador managed integrations';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 if jsonb_array_length(public.manage_webhooks('list'))<>0 or jsonb_array_length(public.manage_api_tokens('list'))<>0 then
  raise exception 'Company B sees company A integrations';end if;
end $$;
reset role;

do $$
declare f tr;
begin
 select * into f from tr;
 if (select revoked_at from apoiarcred_private.api_tokens where id=f.token) is null then raise exception 'Gestor revoke ignored';end if;
 -- The robot uses the company access for every member, never another company's.
 if (select username from apoiarcred_private.tjba_robot_login(f.c,1))<>'empresa-a' then raise exception 'Member does not get the company access';end if;
 if exists(select 1 from apoiarcred_private.tjba_robot_login(f.other,1)) then raise exception 'Company B got an access';end if;
 update apoiarcred_private.tenant_members set active=false where user_id=f.c;
 if exists(select 1 from apoiarcred_private.tjba_robot_login(f.c,1)) then raise exception 'Deactivated member got the access';end if;
 update apoiarcred_private.tenant_members set active=true where user_id=f.c;
 -- A consultation by the Operador triggers the company webhook.
 perform apoiarcred_private.wh_enqueue(f.c,'tenant-res-1','consulta.finalizada','{}','digimais_saldo_parcela',null,'individual','concluida',true,false);
 if not exists(select 1 from apoiarcred_private.webhook_deliveries where hook_id=f.hook) then raise exception 'Company webhook missed a member event';end if;
 perform apoiarcred_private.wh_enqueue(f.other,'tenant-res-2','consulta.finalizada','{}','digimais_saldo_parcela',null,'individual','concluida',true,false);
 if (select count(*) from apoiarcred_private.webhook_deliveries where hook_id=f.hook)<>1 then raise exception 'Webhook got another company event';end if;
 -- Digi+ by API is enabled for the company: every member with Digi+ uses it, other companies do not.
 insert into apoiarcred_private.digimais_preferences(user_id,mode,paused,max_concurrency,api_enabled) values(f.a,'api',false,5,true);
 if not apoiarcred_private.can_use_digimais_api(f.c) or apoiarcred_private.can_use_digimais_api(f.other) then raise exception 'Digi+ API not by company';end if;
 insert into apoiarcred_private.member_overrides select m.tenant_id,f.c,k,false
  from apoiarcred_private.tenant_members m,unnest(array['consulta.digimais.individual','consulta.digimais.campanha']) k where m.user_id=f.c;
 if apoiarcred_private.can_use_digimais_api(f.c) then raise exception 'Member without Digi+ uses the API';end if;
end $$;
rollback;
