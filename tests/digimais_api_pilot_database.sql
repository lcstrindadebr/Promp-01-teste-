begin;
create temporary table pilot_fixture as select gen_random_uuid() uid,gen_random_uuid() lot;
insert into auth.users(id,aud,role,email) select uid,'authenticated','authenticated',uid::text||'@pilot-test.invalid' from pilot_fixture;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select uid,'admin','Pilot fixture',uid::text||'@pilot-test.invalid' from pilot_fixture on conflict(user_id) do update set role='admin',active=true;
select set_config('request.jwt.claim.sub',(select uid::text from pilot_fixture),true);
set local role authenticated;
select public.manage_digimais_pilot('api',false,12);
reset role;
insert into public.consulta_lotes(id,user_id,nome,tipo) select lot,uid,'API TEST','campanha' from pilot_fixture;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone) select lot,uid,'FIXTURE',lpad(n::text,11,'0'),'11999999999' from pilot_fixture cross join generate_series(1,14) n;
do $$begin
 if exists(select 1 from public.consulta_jobs where lote_id=(select lot from pilot_fixture) and execution_mode<>'api') then raise exception 'Mode not captured';end if;
 if has_function_privilege('authenticated','public.claim_consulta_job_for_api(integer)','execute') or has_function_privilege('anon','public.manage_digimais_pilot(text,boolean,integer)','execute') or has_function_privilege('authenticated','public.get_digimais_api_config()','execute') then raise exception 'Unsafe grants';end if;
end$$;
-- Pause applies to queued jobs, and does not rewrite their selected mode.
select public.manage_digimais_pilot('robot',true,12);
do $$begin
 if exists(select 1 from public.claim_consulta_job_for_api(1)) then raise exception 'Paused API claimed';end if;
end$$;
select public.manage_digimais_pilot('robot',false,12);
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone) select lot,uid,'ROBOT','00000000099','11999999999' from pilot_fixture;
do $$declare i integer;j public.consulta_jobs;begin
 for i in 1..12 loop
  select * into j from public.claim_consulta_job_for_api(i);
  if j.id is null or j.user_id<>(select uid from pilot_fixture) or j.execution_mode<>'api' then raise exception 'Reservation failure %',i;end if;
 end loop;
 if exists(select 1 from public.claim_consulta_job_for_api(1)) then raise exception 'Slot duplicated';end if;
 if (select count(*) from public.consulta_jobs where lote_id=(select lot from pilot_fixture) and status='processando')<>12 then raise exception 'Wrong cap';end if;
end$$;
-- Existing reservations finish; lower owner limit blocks additional claims.
select public.manage_digimais_pilot('api',false,1);
update public.consulta_jobs set status='concluida' where lote_id=(select lot from pilot_fixture) and api_slot=1;
do $$begin
 if exists(select 1 from public.claim_consulta_job_for_api(1)) then raise exception 'Owner cap ignored';end if;
end$$;
update apoiarcred_private.user_profiles set role='partner' where user_id=(select uid from pilot_fixture);
set local role authenticated;
do $$begin
 begin perform public.manage_digimais_pilot('api',false,12);raise exception 'Partner accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;
update public.consulta_jobs set status='concluida' where lote_id=(select lot from pilot_fixture) and status='processando';
do $$begin
 if exists(select 1 from public.claim_consulta_job_for_api(1)) then raise exception 'Demoted admin claimed';end if;
end$$;
rollback;
