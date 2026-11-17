-- Etapa 6b: a limpeza só roda quando nada mais usa o modelo antigo, e o sistema continua funcionando depois.
begin;
\ir ../supabase/upgrade_tenants_cleanup.sql
do $$
declare admin_id uuid=gen_random_uuid(); partner uuid=gen_random_uuid(); r jsonb;
begin
 if to_regclass('apoiarcred_private.partner_permissions') is not null or to_regclass('apoiarcred_private.partner_daily_usage') is not null then
  raise exception 'Legacy tables still exist';end if;
 insert into auth.users(id,aud,role,email) values(admin_id,'authenticated','authenticated',admin_id||'@cleanup.invalid'),(partner,'authenticated','authenticated',partner||'@cleanup.invalid');
 insert into apoiarcred_private.user_profiles(user_id,role,name,email) values(admin_id,'admin','Equipe',admin_id||'@cleanup.invalid');
 r:=public.admin_partner_manage(admin_id,'create',jsonb_build_object('user_id',partner,'email',partner||'@cleanup.invalid','name','Depois da limpeza',
  'active',true,'shared_daily_limit',5,'permissions','[{"service":"digimais_saldo_parcela","enabled":true,"allow_individual":true,"allow_campaign":true,"daily_limit":0},{"service":"tjba_margem","enabled":false,"allow_individual":false,"allow_campaign":false,"daily_limit":0}]'::jsonb));
 if r->>'remaining'<>'5' or not (r->'services'->0->>'allow_campaign')::boolean then raise exception 'Platform screen broken after cleanup: %',r;end if;
 perform apoiarcred_private.check_partner_access(partner,'digimais_saldo_parcela','individual',true);
 if apoiarcred_private.access_for(partner)->>'remaining'<>'4' then raise exception 'Quota broken after cleanup';end if;
end $$;
rollback;

