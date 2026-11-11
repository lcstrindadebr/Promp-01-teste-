begin;
do $$
declare fixture uuid=gen_random_uuid(); job public.amigoz_jobs;
begin
 insert into auth.users(id,aud,role,email) values(fixture,'authenticated','authenticated',fixture||'@history-test.invalid');
 insert into apoiarcred_private.user_profiles(user_id,role,name,email) values(fixture,'admin','Fixture',fixture||'@history-test.invalid');
 perform set_config('request.jwt.claim.sub',fixture::text,true);
 select * into job from public.start_amigoz_individual(fixture,'00000000101','amigoz_33','SP','ambos');
 if job.status<>'processando' or job.numero_matricula is not null then raise exception 'CPF-only start failed';end if;
 if not public.finish_amigoz_import_job(job.id,job.lease,'revisao','{"saque":{"status":"respondido","dados":{"ofertas":[]}},"margem":{"status":"erro"}}','Resultado parcial') then raise exception 'Save failed';end if;
 if not exists(select 1 from public.crm_consultas where id=job.id and resultado_amigoz->'saque'->>'status'='respondido' and status='revisao') then raise exception 'Partial history lost';end if;
 if not exists(select 1 from public.crm_cadastros where user_id=fixture and cpf='00000000101') then raise exception 'Missing CRM client';end if;
end $$;
rollback;
