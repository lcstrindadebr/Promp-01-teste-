begin;
create temporary table fila_fixture as select gen_random_uuid() uid,gen_random_uuid() lot,gen_random_uuid() tlot;
insert into auth.users(id,aud,role,email) select uid,'authenticated','authenticated',uid::text||'@fila-test.invalid' from fila_fixture;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select uid,'admin','Fila fixture',uid::text||'@fila-test.invalid' from fila_fixture on conflict(user_id) do update set role='admin',active=true;
insert into apoiarcred_private.digimais_api_config(config) values('{}') on conflict(id) do nothing;
select set_config('request.jwt.claim.sub',(select uid::text from fila_fixture),true);
set local role authenticated;
select public.manage_digimais_pilot('api',false,5);
reset role;
insert into public.consulta_lotes(id,user_id,nome,tipo) select lot,uid,'FILA TEST','campanha' from fila_fixture;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone) select lot,uid,'FIXTURE',lpad(n::text,11,'0'),'11999999999' from fila_fixture cross join generate_series(1,8) n;

-- Grants: only the VPS (service_role) may reserve or release.
do $$begin
 if has_function_privilege('authenticated','public.claim_consulta_jobs_for_api(integer[])','execute')
  or has_function_privilege('anon','public.claim_consulta_jobs_for_api(integer[])','execute')
  or has_function_privilege('authenticated','public.release_stale_jobs(integer)','execute')
  or has_function_privilege('anon','public.release_stale_jobs(integer)','execute') then raise exception 'Unsafe grants';end if;
 if not has_function_privilege('service_role','public.claim_consulta_jobs_for_api(integer[])','execute')
  or not has_function_privilege('service_role','public.release_stale_jobs(integer)','execute') then raise exception 'Missing service_role grants';end if;
end$$;

-- One call reserves one job per free slot, respecting the account's concurrency (5).
do $$declare n integer;slots integer[];begin
 select count(*),array_agg(api_slot order by api_slot) into n,slots from public.claim_consulta_jobs_for_api(array[1,2,3,4,5,6,7,8]);
 if n<>5 then raise exception 'Batch should respect max_concurrency 5, got %',n;end if;
 if slots<>array[1,2,3,4,5] then raise exception 'Unexpected slots %',slots;end if;
 if (select count(*) from public.consulta_jobs where lote_id=(select lot from fila_fixture) and status='processando')<>5 then raise exception 'Wrong processing count';end if;
 -- Busy slots are skipped and the cap still holds.
 if exists(select 1 from public.claim_consulta_jobs_for_api(array[1,2,3])) then raise exception 'Busy slots claimed again';end if;
 if exists(select 1 from public.claim_consulta_jobs_for_api(array[9])) then raise exception 'Cap exceeded';end if;
 if exists(select 1 from public.claim_consulta_jobs_for_api(null)) or exists(select 1 from public.claim_consulta_jobs_for_api('{}')) then raise exception 'Empty input claimed';end if;
end$$;

-- Fresh reservations are kept; old ones go back to the queue with partial data cleared.
update public.consulta_jobs set resultado_saldo='{"x":1}',saldo_liquidacao=10,progress=50 where lote_id=(select lot from fila_fixture) and api_slot=1;
update public.consulta_jobs set locked_at=now()-interval '31 minutes' where lote_id=(select lot from fila_fixture) and api_slot in (1,2);
update public.consulta_jobs set locked_at=now()-interval '31 minutes',attempts=3 where lote_id=(select lot from fila_fixture) and api_slot=3;
do $$declare r jsonb;begin
 r:=public.release_stale_jobs(1800);
 if (r#>>'{consulta_jobs,devolvidas}')::int<>2 or (r#>>'{consulta_jobs,revisao}')::int<>1 then raise exception 'Unexpected release %',r;end if;
 if (select count(*) from public.consulta_jobs where lote_id=(select lot from fila_fixture) and status='processando')<>2 then raise exception 'Fresh reservations released';end if;
 if exists(select 1 from public.consulta_jobs where lote_id=(select lot from fila_fixture) and status='aguardando'
   and (api_slot is not null or locked_at is not null or resultado_saldo is not null or saldo_liquidacao is not null or progress<>0)) then raise exception 'Requeued job kept partial data';end if;
 if (select count(*) from public.consulta_jobs where lote_id=(select lot from fila_fixture) and status='revisao' and api_slot is null)<>1 then raise exception 'Third interruption not sent to review';end if;
end$$;

-- A late result from the first attempt cannot overwrite the job after it was requeued and claimed again.
do $$declare j public.consulta_jobs;updated integer;begin
 select * into j from public.claim_consulta_jobs_for_api(array[1]) limit 1;
 if j.id is null or j.attempts<>2 then raise exception 'Requeued job not claimed again (attempts %)',j.attempts;end if;
 update public.consulta_jobs set status='concluida' where id=j.id and status='processando' and attempts=1;
 get diagnostics updated=row_count;
 if updated<>0 then raise exception 'Stale attempt overwrote the new reservation';end if;
end$$;

-- On worker start everything it held is released at once.
do $$declare r jsonb;begin
 r:=public.release_stale_jobs(0);
 if exists(select 1 from public.consulta_jobs where lote_id=(select lot from fila_fixture) and status='processando') then raise exception 'Startup release left jobs processing %',r;end if;
end$$;

-- ConsigX jobs follow the same rule.
insert into public.tjba_lotes(id,user_id,nome,tipo) select tlot,uid,'TJBA FILA','campanha' from fila_fixture;
insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone,status,locked_at,attempts,resultado_tjba)
 select tlot,uid,'TJBA',lpad((100+n)::text,11,'0'),'',
  'processando',now()-interval '40 minutes',n,'{"x":1}' from fila_fixture cross join generate_series(1,3) n;
do $$declare r jsonb;begin
 r:=public.release_stale_jobs(1800);
 if (r#>>'{tjba_jobs,devolvidas}')::int<>2 or (r#>>'{tjba_jobs,revisao}')::int<>1 then raise exception 'Unexpected TJBA release %',r;end if;
 if exists(select 1 from public.tjba_jobs where lote_id=(select tlot from fila_fixture) and status='aguardando' and resultado_tjba is not null) then raise exception 'TJBA partial data kept';end if;
end$$;
rollback;
