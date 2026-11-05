begin;
create temporary table partner_fixture as select gen_random_uuid() admin_uid,gen_random_uuid() partner_uid,gen_random_uuid() unknown_uid,null::uuid job_id,null::uuid campaign_id,null::text token;
insert into auth.users(id,aud,role,email) select admin_uid,'authenticated','authenticated',admin_uid||'@partner-admin.invalid' from partner_fixture union all select partner_uid,'authenticated','authenticated',partner_uid||'@partner-test.invalid' from partner_fixture union all select unknown_uid,'authenticated','authenticated',unknown_uid||'@partner-unknown.invalid' from partner_fixture;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select admin_uid,'admin','Admin test',admin_uid||'@partner-admin.invalid' from partner_fixture;
grant select,update on partner_fixture to authenticated,service_role;
set local role service_role;
do $$declare f record;r jsonb;begin
 select * into f from partner_fixture;
 r=public.admin_partner_manage(f.admin_uid,'create',jsonb_build_object('user_id',f.partner_uid,'email',f.partner_uid||'@partner-test.invalid','name','Partner test','active',true,'permissions','[{"service":"digimais_saldo_parcela","enabled":true,"allow_individual":true,"daily_limit":2,"allow_campaign":false},{"service":"tjba_margem","enabled":true,"allow_individual":true,"daily_limit":1,"allow_campaign":true}]'::jsonb));
 if r->>'role'<>'partner' then raise exception 'Wrong role';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select partner_uid::text from partner_fixture),true);
set local role authenticated;
do $$declare f record;r jsonb;j uuid;begin
 select * into f from partner_fixture;
 r=public.my_access();if r->>'role'<>'partner' or not (r->>'active')::boolean or public.am_i_admin() then raise exception 'Invalid partner access';end if;
 j=public.create_individual_consulta('{"nome":"TEST","cpf":"00000000191","telefone":"11999999999"}');update partner_fixture set job_id=j;
 begin perform public.create_consulta_campaign('NOT ALLOWED','[{"nome":"TEST","cpf":"00000000272","telefone":"11999999999"}]');raise exception 'Campaign permitted';exception when insufficient_privilege then null;end;
 r=public.manage_api_tokens('create','{"name":"Partner integration","scopes":["read","consultas:create","campanhas:write"]}');update partner_fixture set token=r->>'token';
 if exists(select 1 from public.vps_monitoramento) then raise exception 'Global monitoring leaked to partner';end if;
end $$;
reset role;
set local role service_role;
do $$declare f record;r jsonb;h text;begin
 select * into f from partner_fixture;h=encode(extensions.digest(f.token,'sha256'),'hex');
 r=public.api_execute(h,'POST','/consultas','{"nome":"TEST API","cpf":"00000000272","telefone":"11999999999"}','partner-individual');
 if (r->>'status')::int<>202 then raise exception 'API second accepted request failed: %',r;end if;
 r=public.api_execute(h,'POST','/consultas','{"nome":"TEST API","cpf":"00000000272","telefone":"11999999999"}','partner-individual');
 if not (r->>'replayed')::boolean then raise exception 'Replay failed';end if;
 r=public.api_execute(h,'POST','/consultas','{"nome":"THIRD","cpf":"00000000353","telefone":"11999999999"}','partner-over-limit');
 if (r->>'status')::int<>429 or r->'body'->'error'->>'code'<>'daily_limit' then raise exception 'API bypassed daily limit: %',r;end if;
 if (select used from apoiarcred_private.partner_daily_usage where user_id=f.partner_uid and service='digimais_saldo_parcela')<>2 then raise exception 'Usage or replay charged incorrectly';end if;
end $$;
reset role;
set local role authenticated;
do $$declare f record;r jsonb;begin
 select * into f from partner_fixture;
 delete from public.consulta_jobs where id=f.job_id;
 begin perform public.create_individual_consulta('{"nome":"TEST","cpf":"00000000191","telefone":"11999999999"}');raise exception 'Deletion refunded quota';exception when sqlstate 'PT429' then null;end;
 perform public.create_individual_consulta('{"cpf":"00000000191"}','tjba_margem','tjba');
 begin perform public.create_individual_consulta('{"cpf":"00000000272"}','tjba_margem','tjba');raise exception 'Independent ConsigX quota failed';exception when sqlstate 'PT429' then null;end;
 update partner_fixture set campaign_id=public.create_consigx_campaign('Allowed campaign','[{"cpf":"00000000353"},{"cpf":"00000000434"}]','tjba');
 r=public.my_access();if (r->'services'->1->>'used')::int<>1 then raise exception 'Campaign consumed individual quota: %',r;end if;
end $$;
reset role;
set local role service_role;
do $$declare f record;r jsonb;begin
 select * into f from partner_fixture;
 if (select count(*) from public.consulta_lotes where user_id=f.partner_uid and tipo='individual')<>2 then raise exception 'Rejected requests left empty lots';end if;
 r=public.admin_partner_manage(f.admin_uid,'update',jsonb_build_object('user_id',f.partner_uid,'name','Updated partner','active',true,'permissions','[{"service":"digimais_saldo_parcela","enabled":false,"allow_individual":false,"daily_limit":2,"allow_campaign":false},{"service":"tjba_margem","enabled":true,"allow_individual":true,"daily_limit":1,"allow_campaign":false}]'::jsonb));
 begin perform public.admin_partner_manage(f.partner_uid,'list');raise exception 'Partner managed users';exception when insufficient_privilege then null;end;
 update apoiarcred_private.user_profiles set active=false where user_id=f.partner_uid;
 r=apoiarcred_private.access_for(f.partner_uid);if (r->>'active')::boolean or not (r->'services'->1->>'enabled')::boolean then raise exception 'Inactive account lost its configured permissions';end if;
end $$;
reset role;
set local role authenticated;
do $$declare f record;begin
 select * into f from partner_fixture;
 begin perform public.create_individual_consulta('{"nome":"TEST","cpf":"00000000191","telefone":"11999999999"}');raise exception 'Disabled service accepted';exception when insufficient_privilege then null;end;
 begin perform public.create_individual_consulta('{"cpf":"00000000272"}','tjba_margem','tjba');raise exception 'Inactive account accepted';exception when insufficient_privilege then null;end;
 perform public.set_campaign_paused(f.campaign_id,'tjba_margem',true);
 begin perform public.set_campaign_paused(f.campaign_id,'tjba_margem',false);raise exception 'Campaign resume bypassed permissions';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select unknown_uid::text from partner_fixture),true);
set local role authenticated;
do $$begin
 begin perform public.create_individual_consulta('{"nome":"UNKNOWN","cpf":"00000000191","telefone":"11999999999"}');raise exception 'Unknown account accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin
 if has_function_privilege('authenticated','public.admin_partner_manage(uuid,text,jsonb)','execute') then raise exception 'Admin RPC exposed';end if;
 if has_table_privilege('authenticated','apoiarcred_private.partner_daily_usage','update') or has_table_privilege('authenticated','apoiarcred_private.user_profiles','select') then raise exception 'Partner policies exposed';end if;
 if has_function_privilege('anon','public.my_access()','execute') then raise exception 'Anonymous access';end if;
end $$;
rollback;
