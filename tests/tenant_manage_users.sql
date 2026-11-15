-- Run in a transaction after tenant_foundation.sql and tenant_manage_users.sql.
do $test$
declare company_a uuid; company_b uuid; owner_a uuid; owner_b uuid;
 operator_id uuid:=gen_random_uuid(); payload jsonb;
begin
 select id,legacy_owner_id into strict company_a,owner_a
 from apoiarcred_private.tenants where active order by id limit 1;
 select id,legacy_owner_id into strict company_b,owner_b
 from apoiarcred_private.tenants where active and id<>company_a order by id limit 1;
 insert into auth.users(id,aud,role,email)
 values(operator_id,'authenticated','authenticated',operator_id||'@tenant-test.invalid');
 payload:=jsonb_build_object('id',operator_id,'role','operator','active',true,'daily_limit',2,'name','Operador teste',
  'services',(select jsonb_agg(jsonb_build_object('service',service,'enabled',false,
    'allow_individual',false,'allow_campaign',false)) from apoiarcred_private.tenant_permissions where tenant_id=company_a));
 perform public.tenant_manage_users(owner_a,'create',payload);
 if not exists(select 1 from apoiarcred_private.tenant_members where user_id=operator_id and tenant_id=company_a) then
  raise exception 'O operador não foi vinculado à empresa correta.';
 end if;
 begin
  perform public.tenant_manage_users(owner_b,'update',payload);
  raise exception 'A alteração atravessou a fronteira entre empresas.';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.tenant_manage_users(operator_id,'list');
  raise exception 'O operador ganhou acesso à gestão de usuários.';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.tenant_manage_users(owner_a,'update',payload||jsonb_build_object('id',owner_a,'role','operator'));
  raise exception 'O último administrador foi removido.';
 exception when invalid_parameter_value then null;
 end;
 if not exists(select 1 from apoiarcred_private.tenant_audit where tenant_id=company_a and target_id=operator_id and actor_id=owner_a and action='create') then
  raise exception 'Faltou registrar a criação na auditoria.';
 end if;
end
$test$;
