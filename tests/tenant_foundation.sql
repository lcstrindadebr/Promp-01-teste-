-- BEGIN; aplicar supabase/tenant_foundation.sql; executar este arquivo; ROLLBACK.
-- Executar após a migração, dentro de BEGIN/ROLLBACK.
do $test$
declare owner_a uuid:=gen_random_uuid();owner_b uuid:=gen_random_uuid();
 operator_a uuid:=gen_random_uuid();company_a uuid;company_b uuid;result jsonb;
begin
 insert into auth.users(id,aud,role,email)
 values(owner_a,'authenticated','authenticated',owner_a||'@tenant-test.invalid'),
       (owner_b,'authenticated','authenticated',owner_b||'@tenant-test.invalid'),
       (operator_a,'authenticated','authenticated',operator_a||'@tenant-test.invalid');
 insert into apoiarcred_private.tenants(legacy_owner_id,name,daily_limit)
 values(owner_a,'Tenant A',3) returning id into company_a;
 insert into apoiarcred_private.tenants(legacy_owner_id,name)
 values(owner_b,'Tenant B') returning id into company_b;
 insert into apoiarcred_private.tenant_members(user_id,tenant_id,role,daily_limit)
 values(owner_a,company_a,'admin',null),(operator_a,company_a,'operator',2),
       (owner_b,company_b,'admin',null);
 insert into apoiarcred_private.tenant_permissions(tenant_id,service,enabled,allow_individual,allow_campaign)
 values(company_a,'digimais_saldo_parcela',true,true,true),(company_a,'tjba_margem',true,true,true),
       (company_b,'digimais_saldo_parcela',true,true,true);
 insert into apoiarcred_private.tenant_user_permissions
 values(company_a,operator_a,'digimais_saldo_parcela',true,true,false),
       (company_a,operator_a,'tjba_margem',false,false,false),
       (company_a,owner_a,'digimais_saldo_parcela',true,true,true);
 if not apoiarcred_private.tenant_can_service(operator_a,'digimais_saldo_parcela','individual')
  or apoiarcred_private.tenant_can_service(operator_a,'digimais_saldo_parcela','campanha')
  or apoiarcred_private.tenant_can_service(operator_a,'tjba_margem','read') then
  raise exception 'Permissões individuais incorretas';
 end if;
 update apoiarcred_private.tenant_permissions set enabled=false
 where tenant_id=company_a and service='digimais_saldo_parcela';
 if apoiarcred_private.tenant_can_service(operator_a,'digimais_saldo_parcela','individual') then
  raise exception 'Permissão do usuário ultrapassou a empresa';
 end if;
 update apoiarcred_private.tenant_permissions set enabled=true
 where tenant_id=company_a and service='digimais_saldo_parcela';
 perform apoiarcred_private.tenant_consume(operator_a,'digimais_saldo_parcela','individual',2);
 begin
  perform apoiarcred_private.tenant_consume(operator_a,'digimais_saldo_parcela','individual',1);
  raise exception 'Cota do usuário ultrapassada';
 exception when sqlstate 'PT429' then null;
 end;
 if (select used from apoiarcred_private.tenant_daily_usage where tenant_id=company_a)<>2 then
  raise exception 'Falha consumiu cota da empresa';
 end if;
 perform apoiarcred_private.tenant_consume(owner_a,'digimais_saldo_parcela','individual',1);
 begin
  perform apoiarcred_private.tenant_consume(owner_a,'digimais_saldo_parcela','individual',1);
  raise exception 'Cota da empresa ultrapassada';
 exception when sqlstate 'PT429' then null;
 end;
 perform set_config('request.jwt.claim.sub',operator_a::text,true);
 result:=public.tenant_context();
 if result->>'tenant_id'<>company_a::text or result->>'role'<>'operator' then
  raise exception 'Contexto incorreto';
 end if;
 perform set_config('request.jwt.claim.sub',owner_b::text,true);
 if public.tenant_context()->>'tenant_id'<>company_b::text then
  raise exception 'Contexto vazou entre empresas';
 end if;
 if has_function_privilege('authenticated','apoiarcred_private.tenant_consume(uuid,text,text,integer)','execute')
  or has_table_privilege('authenticated','apoiarcred_private.tenant_members','update')
  or has_function_privilege('anon','public.tenant_context()','execute') then
  raise exception 'Privilégios indevidos';
 end if;
end
$test$;
