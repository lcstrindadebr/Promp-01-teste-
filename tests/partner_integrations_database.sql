-- Rollback fixtures: no endpoint is contacted, and no secret is printed.
begin;
create temporary table pi_fixture as select gen_random_uuid() admin_uid,gen_random_uuid() partner_uid,null::text token,null::uuid hid;
insert into auth.users(id,aud,role,email) select admin_uid,'authenticated','authenticated',admin_uid||'@pi.invalid' from pi_fixture union all select partner_uid,'authenticated','authenticated',partner_uid||'@pi.invalid' from pi_fixture;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select admin_uid,'admin','Integration fixture',admin_uid||'@pi.invalid' from pi_fixture;
grant select,update on pi_fixture to authenticated,service_role;
set local role service_role;
do $$declare f record;r jsonb;begin
 select * into f from pi_fixture;
 r=public.admin_partner_manage(f.admin_uid,'create',jsonb_build_object('user_id',f.partner_uid,'email',f.partner_uid||'@pi.invalid','name','Integration partner','active',true,'permissions','[{"service":"digimais_saldo_parcela","enabled":true,"allow_individual":true,"daily_limit":10,"allow_campaign":true},{"service":"tjba_margem","enabled":true,"allow_individual":true,"daily_limit":10,"allow_campaign":true}]'::jsonb));
 if (r->>'allow_integrations')::boolean or not (apoiarcred_private.access_for(f.admin_uid)->>'allow_integrations')::boolean then raise exception 'Wrong default/admin capability';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select partner_uid::text from pi_fixture),true);
set local role authenticated;
do $$begin
 perform public.create_individual_consulta('{"nome":"FIXTURE","cpf":"00000000191","telefone":"11999999999"}');
 begin perform public.manage_api_tokens('list');raise exception 'Token listing not restricted';exception when insufficient_privilege then null;end;
 begin perform public.manage_api_tokens('create','{"name":"Blocked","scopes":["read"]}');raise exception 'Token creation not restricted';exception when insufficient_privilege then null;end;
 begin perform public.manage_webhooks('list');raise exception 'Webhook access not restricted';exception when insufficient_privilege then null;end;
 begin update apoiarcred_private.user_profiles set allow_integrations=true where user_id=auth.uid();raise exception 'Partner granted own integration access';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role service_role;
do $$declare f record;r jsonb;begin
 select * into f from pi_fixture;
 r=public.admin_partner_manage(f.admin_uid,'update',jsonb_build_object('user_id',f.partner_uid,'name','Integration partner','active',true,'allow_integrations',true,'permissions','[{"service":"digimais_saldo_parcela","enabled":true,"allow_individual":true,"daily_limit":10,"allow_campaign":true},{"service":"tjba_margem","enabled":true,"allow_individual":true,"daily_limit":10,"allow_campaign":true}]'::jsonb));
 if not (r->>'allow_integrations')::boolean then raise exception 'Admin grant failed';end if;
end $$;
reset role;
set local role authenticated;
do $$declare r jsonb;begin
 r=public.manage_api_tokens('create','{"name":"Integration fixture","scopes":["read"]}');update pi_fixture set token=r->>'token';
 r=public.manage_webhooks('create','{"name":"Integration fixture","url":"https://example.com/hook","scope":"all","events":["consulta.finalizada"],"statuses":["concluida"],"client_filter":"all"}');update pi_fixture set hid=(r->>'id')::uuid;
 perform public.manage_webhooks('test',jsonb_build_object('id',(select hid from pi_fixture)));
 if jsonb_array_length(public.manage_webhooks('list'))<>1 then raise exception 'Granted list failed';end if;
end $$;
reset role;
set local role service_role;
do $$declare f record;r jsonb;begin
 select * into f from pi_fixture;
 r=public.api_execute(encode(extensions.digest(f.token,'sha256'),'hex'),'GET','/servicos');if (r->>'status')::int<>200 then raise exception 'Enabled API rejected';end if;
 r=public.admin_partner_manage(f.admin_uid,'update',jsonb_build_object('user_id',f.partner_uid,'name','Integration partner','active',true,'allow_integrations',false,'permissions','[{"service":"digimais_saldo_parcela","enabled":true,"allow_individual":true,"daily_limit":10,"allow_campaign":true},{"service":"tjba_margem","enabled":true,"allow_individual":true,"daily_limit":10,"allow_campaign":true}]'::jsonb));
 r=public.api_execute(encode(extensions.digest(f.token,'sha256'),'hex'),'GET','/servicos');if (r->>'status')::int<>403 or r->'body'->'error'->>'code'<>'integrations_disabled' then raise exception 'Existing token remained usable';end if;
end $$;
reset role;
do $$declare f record;n int;begin
 select * into f from pi_fixture;
 select count(*) into n from apoiarcred_private.webhook_events where user_id=f.partner_uid;
 perform apoiarcred_private.wh_enqueue(f.partner_uid,'blocked-fixture','consulta.finalizada','{}','digimais_saldo_parcela',null,'individual','concluida',true,false);
 if (select count(*) from apoiarcred_private.webhook_events where user_id=f.partner_uid)<>n then raise exception 'Revoked webhook captured event';end if;
 -- Avoid inspecting unrelated deliveries if this test is reused on a configured project.
 if not exists(select 1 from apoiarcred_private.webhooks where user_id<>f.partner_uid) then
  if public.claim_webhook_deliveries()<>'[]'::jsonb then raise exception 'Pending delivery ignored revoked capability';end if;
 end if;
 if not exists(select 1 from apoiarcred_private.webhook_deliveries where hook_id=f.hid and state='pending') then raise exception 'Pending delivery was lost';end if;
end $$;
set local role authenticated;
do $$begin
 begin perform public.manage_webhooks('test',jsonb_build_object('id',(select hid from pi_fixture)));raise exception 'Revoked test allowed';exception when insufficient_privilege then null;end;
 begin perform public.manage_api_tokens('list');raise exception 'Revoked token administration allowed';exception when insufficient_privilege then null;end;
 perform public.create_individual_consulta('{"nome":"PANEL STILL WORKS","cpf":"00000000272","telefone":"11999999999"}');
end $$;
reset role;
do $$declare f record;r jsonb;begin
 select * into f from pi_fixture;
 update apoiarcred_private.user_profiles set allow_integrations=true where user_id=f.partner_uid;
 if not exists(select 1 from apoiarcred_private.webhooks where user_id<>f.partner_uid) then
  r=public.claim_webhook_deliveries();if jsonb_array_length(r)<>1 or r->0->>'id' is null then raise exception 'Re-enabled pending delivery did not resume';end if;
 end if;
end $$;
rollback;
