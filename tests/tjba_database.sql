begin;
create temporary table tjba_fixture as select gen_random_uuid() uid,gen_random_uuid() other_uid,null::uuid cid,null::uuid job;
grant select,update on tjba_fixture to authenticated;
grant select on tjba_fixture to service_role;
insert into auth.users(id,aud,role,email) select uid,'authenticated','authenticated',uid::text||'@tjba-test.invalid' from tjba_fixture union all select other_uid,'authenticated','authenticated',other_uid::text||'@tjba-test.invalid' from tjba_fixture;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select id,'admin','Test fixture',email from auth.users where (email like '%@tjba-test.invalid') and not exists(select 1 from apoiarcred_private.user_profiles p where p.user_id=auth.users.id);

set local role authenticated;
do $$ declare f record; campaign_uuid uuid; denied boolean=false; info jsonb; begin
 select * into f from tjba_fixture;perform set_config('request.jwt.claim.sub',f.uid::text,true);
 perform public.save_tjba_credentials('test-user','test-password-do-not-use',false);
 info=public.tjba_credentials_status();if not (info->>'configured')::boolean or info->>'password' is not null or (info->>'enabled')::boolean then raise exception 'Credential status leaks or default enabled';end if;
 perform public.save_tjba_credentials('test-user','',true);
 campaign_uuid=public.create_tjba_campaign('TJBA TEST','[{"cpf":"00123456789"},{"cpf":"00000000191"},{"cpf":"00000000272"}]');
 update tjba_fixture set cid=campaign_uuid;
 -- Use unique alias to avoid PL/pgSQL variable/column ambiguity.
 update tjba_fixture set job=(select id from public.tjba_jobs j where j.lote_id=campaign_uuid order by j.cpf limit 1);
 if (select count(*) from public.tjba_jobs j where j.lote_id=campaign_uuid)<>3 then raise exception 'Three CPF creation failed';end if;
 begin perform public.get_tjba_credentials(f.uid);exception when insufficient_privilege then denied=true;end;
 if not denied then raise exception 'Browser can decrypt';end if;
 denied=false;begin update public.tjba_jobs set emprestimo_disponivel=0 where lote_id=campaign_uuid;exception when insufficient_privilege then denied=true;end;
 if not denied then raise exception 'Browser can modify results';end if;
 perform set_config('request.jwt.claim.sub',f.other_uid::text,true);
 if exists(select 1 from public.tjba_jobs where lote_id=campaign_uuid) then raise exception 'Other user sees jobs';end if;
 if (public.tjba_credentials_status()->>'configured')::boolean then raise exception 'Other user sees credential status';end if;
 denied=false;begin perform public.retry_tjba_campaign(campaign_uuid);exception when insufficient_privilege then denied=true;end;
 if not denied then raise exception 'Other user can retry';end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$ declare secret jsonb; begin
 secret=public.get_tjba_credentials((select uid from tjba_fixture));
 if secret->>'password'<>'test-password-do-not-use' or not (secret->>'enabled')::boolean then raise exception 'Worker decrypt failed';end if;
end $$;
reset role;
update public.tjba_jobs set status='concluida',progress=100,tjba_status='consultado',matricula='000123',emprestimo_disponivel=0,cartao_disponivel=-10.25,consultado_em=now(),resultado_tjba='{"status":"consultado","matricula":"000123","emprestimo_disponivel":"0.00","cartao_disponivel":"-10.25"}' where id=(select job from tjba_fixture);
update public.tjba_jobs set status='revisao',tjba_status='revisao_matricula',resultado_tjba='{"status":"revisao_matricula","vinculos":[{"situacao":"Ativo"},{"situacao":"Ativo"}]}' where lote_id=(select cid from tjba_fixture) and id<>(select job from tjba_fixture);
set local role authenticated;
do $$ declare f record; begin
 select * into f from tjba_fixture;perform set_config('request.jwt.claim.sub',f.uid::text,true);
 if not exists(select 1 from public.tjba_jobs where id=f.job and matricula='000123' and emprestimo_disponivel=0 and cartao_disponivel=-10.25) then raise exception 'Typed values/zero/negative lost';end if;
 if (select count(*) from public.consulta_tjba_historico where job_id in (select id from public.tjba_jobs where lote_id=f.cid))<>3 then raise exception 'History missing';end if;
 if public.retry_tjba_campaign(f.cid)<>2 then raise exception 'Retry scope failed';end if;
 if (select count(*) from public.consulta_tjba_historico where user_id=f.uid)<>3 then raise exception 'Retry removed history';end if;
 delete from public.tjba_lotes where id=f.cid;
 if exists(select 1 from public.tjba_jobs where lote_id=f.cid) or exists(select 1 from public.consulta_tjba_historico where user_id=f.uid) then raise exception 'Delete cascade failed';end if;
end $$;
reset role;
rollback;
select 'PASS: encrypted credentials, owner isolation, worker-only decryption, three-CPF campaign, zero/negative values, preserved history, scoped retry and cascade; all fixtures rolled back' result;
