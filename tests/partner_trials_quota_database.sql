begin;
do $$
declare
 admin_id uuid:=gen_random_uuid(); partner_id uuid:=gen_random_uuid();
 today date:=(now() at time zone 'America/Sao_Paulo')::date;
 config jsonb; items jsonb; result jsonb; lot_id uuid; token_hash text:=repeat('f',64);
begin
 insert into auth.users(id,aud,role,email) values
  (admin_id,'authenticated','authenticated',admin_id||'@trial-admin.invalid'),
  (partner_id,'authenticated','authenticated',partner_id||'@trial-partner.invalid');
 insert into apoiarcred_private.user_profiles(user_id,role,name,email)
  values(admin_id,'admin','Quota test',admin_id||'@trial-admin.invalid');
 config=jsonb_build_object('user_id',partner_id,'name','Trial test','email',partner_id||'@trial-partner.invalid',
  'shared_daily_limit',100,'trial_until',today+2,'allow_integrations',true,
  'permissions','[{"service":"digimais_saldo_parcela","enabled":true,"allow_individual":true,"allow_campaign":true,"daily_limit":0},{"service":"tjba_margem","enabled":true,"allow_individual":true,"allow_campaign":true,"daily_limit":0}]'::jsonb);
 result=public.admin_partner_manage(admin_id,'create',config);
 if result->>'trial_days_left' is distinct from '3' or result->>'remaining' is distinct from '100' then raise exception 'Invalid new trial settings';end if;
 perform set_config('request.jwt.claim.sub',partner_id::text,true);
 select jsonb_agg(jsonb_build_object('nome','Fixture','cpf',lpad(i::text,11,'0'),'telefone','11999999999')) into items from generate_series(1,50) i;
 lot_id=public.create_consulta_campaign('Fixture campaign',items);
 if apoiarcred_private.access_for(partner_id)->>'remaining' is distinct from '50' then raise exception 'Campaign did not consume the shared quota';end if;
 insert into apoiarcred_private.api_tokens(user_id,name,token_hash,prefix,scopes)
 values(partner_id,'Fixture token',token_hash,'fixture',array['read','consultas:create','campanhas:write']);
 result=public.api_execute(token_hash,'POST','/consultas','{"servico":"tjba_margem","cpf":"00000000000"}','trial-fixture');
 if result->>'status' is distinct from '202' then raise exception 'Cross-service API consultation failed: %',result;end if;
 result=public.api_execute(token_hash,'POST','/consultas','{"servico":"tjba_margem","cpf":"00000000000"}','trial-fixture');
 if result->>'replayed' is distinct from 'true' or apoiarcred_private.access_for(partner_id)->>'remaining' is distinct from '49' then raise exception 'API replay spent quota twice';end if;
 begin
  perform public.create_consulta_campaign('Over quota',items);
  raise exception 'Oversized campaign accepted';
 exception when sqlstate 'PT429' then null;
 end;
 if apoiarcred_private.access_for(partner_id)->>'remaining' is distinct from '49' or
  exists(select 1 from public.consulta_lotes where user_id=partner_id and nome='Over quota') then raise exception 'Rejected campaign spent quota or left a lot';end if;
 perform public.admin_partner_manage(admin_id,'update',config||jsonb_build_object('trial_until',today-1));
 result=public.api_execute(token_hash,'POST','/consultas','{"servico":"tjba_margem","cpf":"00000000000"}','expired-fixture');
 if result->>'status' is distinct from '403' then raise exception 'Expired trial created a consultation';end if;
 result=public.api_execute(token_hash,'GET','/campanhas/'||lot_id||'/leads');
 if result->>'status' is distinct from '200' or jsonb_array_length(result->'body'->'data') is distinct from 50 then raise exception 'Expired trial lost history';end if;
 perform public.admin_partner_manage(admin_id,'update',config||'{"shared_daily_limit":null,"trial_until":null}'::jsonb);
 result=apoiarcred_private.access_for(partner_id);
 if result->>'trial_until' is not null or result->>'remaining' is not null or result->>'shared_quota' is distinct from 'true' then raise exception 'Regular unlimited settings incorrect';end if;
end $$;
rollback;
