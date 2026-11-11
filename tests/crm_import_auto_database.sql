begin;
do $$
declare fixture uuid=gen_random_uuid();
begin
 insert into auth.users(id,aud,role,email) values(fixture,'authenticated','authenticated',fixture||'@test.invalid');
 insert into apoiarcred_private.user_profiles(user_id,role,name,email) values(fixture,'admin','Fixture',fixture||'@test.invalid');
 perform set_config('request.jwt.claim.sub',fixture::text,true);
end $$;
set local role authenticated;
do $$
declare token uuid=gen_random_uuid(); r jsonb; rows jsonb='[{"cpf":"00000000101","nome":"Teste","telefone":"11999999999"}]';
begin
 r=public.crm_import_and_start(token,'SP','amigoz_33',array['amigoz_margem','amigoz_saque','digimais_saldo'],rows);
 if (r->>'consultas')::int<>2 or (select count(*) from public.amigoz_jobs)<>1 or (select count(*) from public.consulta_jobs)<>1 then raise exception 'Missing queued jobs';end if;
 if public.crm_import_and_start(token,'SP','amigoz_33',array['amigoz_margem','amigoz_saque','digimais_saldo'],rows)<>r or (select count(*) from public.amigoz_jobs)<>1 then raise exception 'Duplicate retry';end if;
 r=public.crm_import_and_start(gen_random_uuid(),'BA','tjba',array['consigx_margem'],rows);
 if (select count(*) from public.tjba_jobs)<>1 then raise exception 'Missing ConsigX';end if;
 r=public.crm_import_and_start(gen_random_uuid(),'BA','saeb','{}',rows);
 if (r->>'consultas')::int<>0 then raise exception 'Unexpected jobs';end if;
 begin
  perform public.crm_import_and_start(gen_random_uuid(),'BA','tjba',array['digimais_saldo'],'[{"cpf":"00000000202"}]');
  raise exception 'Accepted incomplete Digi+';
 exception when raise_exception then
  if sqlerrm<>'Digi+ exige nome e telefone com DDD em todas as linhas.' then raise;end if;
 end;
 if exists(select 1 from public.crm_cadastros where cpf='00000000202') then raise exception 'Partial commit';end if;
 if (select count(*) from public.crm_consultas)<>3 then raise exception 'History incomplete';end if;
end $$;
reset role;
-- Worker claim ownership and fenced result persistence, without any external calls.
set local role service_role;
do $$
declare job public.amigoz_jobs;
begin
 select * into job from public.claim_amigoz_import_job();
 if job.status<>'processando' then raise exception 'Claim failed';end if;
 if exists(select 1 from public.claim_amigoz_import_job()) then raise exception 'Double claim';end if;
 if public.finish_amigoz_import_job(job.id,gen_random_uuid(),'concluida','{}','Teste') then raise exception 'Stale lease accepted';end if;
 if not public.finish_amigoz_import_job(job.id,job.lease,'concluida','{"saque":{"status":"respondido"}}','Teste') then raise exception 'Finish failed';end if;
end $$;
reset role;
-- A different account cannot read the first account's history or bypass permission.
do $$
declare fixture uuid=gen_random_uuid();
begin
 insert into auth.users(id,aud,role,email) values(fixture,'authenticated','authenticated',fixture||'@test.invalid');
 insert into apoiarcred_private.user_profiles(user_id,role,name,email,shared_quota,shared_daily_limit,allow_amigoz)
 values(fixture,'partner','Partner fixture',fixture||'@test.invalid',true,1,false);
 perform set_config('request.jwt.claim.sub',fixture::text,true);
end $$;
set local role authenticated;
do $$
begin
 if exists(select 1 from public.amigoz_jobs) then raise exception 'Cross-account read';end if;
 begin
  perform public.crm_import_and_start(gen_random_uuid(),'SP','amigoz_33',array['amigoz_saque'],'[{"cpf":"00000000101"}]');
  raise exception 'Permission bypass';
 exception when insufficient_privilege then null;end;
 if exists(select 1 from public.crm_cadastros) then raise exception 'Failed import left clients';end if;
end $$;
reset role;
update apoiarcred_private.user_profiles set allow_amigoz=true where user_id=auth.uid();
set local role authenticated;
do $$
begin
 begin
  perform public.crm_import_and_start(gen_random_uuid(),'SP','amigoz_33',array['amigoz_saque'],'[{"cpf":"00000000101"},{"cpf":"00000000202"}]');
  raise exception 'Quota bypass';
 exception when sqlstate 'PT429' then null;end;
 if exists(select 1 from public.amigoz_jobs) or exists(select 1 from public.crm_cadastros) then raise exception 'Partial quota commit';end if;
end $$;
reset role;

rollback;
