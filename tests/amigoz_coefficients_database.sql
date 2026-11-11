begin;
create temporary table coefficient_fixture as select gen_random_uuid() uid,gen_random_uuid() other_uid,gen_random_uuid() lot,gen_random_uuid() job;
grant select on coefficient_fixture to authenticated;
insert into auth.users(id,aud,role,email) select uid,'authenticated','authenticated',uid::text||'@coef.invalid' from coefficient_fixture union all select other_uid,'authenticated','authenticated',other_uid::text||'@coef.invalid' from coefficient_fixture;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select uid,'admin','Fixture',uid::text||'@coef.invalid' from coefficient_fixture on conflict(user_id) do update set role='admin',active=true;
insert into public.consulta_lotes(id,user_id,nome,tipo) select lot,uid,'Coefficient fixture','campanha' from coefficient_fixture;
insert into public.consulta_jobs(id,lote_id,user_id,nome,cpf,telefone,status,saldo_liquidacao,valor_parcela,consultado_em)
select job,lot,uid,'Fixture','00000000191','11999999999','concluida',200,200,now() from coefficient_fixture;
insert into public.crm_cadastros(user_id,cpf,nome,ultima_atividade) select uid,'00000000191','Fixture',now() from coefficient_fixture on conflict do nothing;
insert into public.crm_margens_vinculo(user_id,cpf,convenio,matricula,instituicao,produto,valor,observado_em,origem)
select uid,'00000000191','amigoz_23','A','amigoz','beneficio',50,now(),'consulta' from coefficient_fixture;
insert into public.crm_margens_vinculo(user_id,cpf,convenio,matricula,instituicao,produto,valor,observado_em,origem)
select uid,'00000000191','amigoz_23','B','consigx','emprestimo',999,now(),'consulta' from coefficient_fixture;
select set_config('request.jwt.claim.sub',(select uid::text from coefficient_fixture),true);
set local role authenticated;
do $$declare cfg jsonb;r jsonb;ctx jsonb;k text;expected numeric[]=array[4059.30,3792.50,3554.17,3338.89,3161.53,2817.69];i integer;before_count integer;begin
 select config into cfg from public.amigoz_model_versions order by id desc limit 1;
 r=apoiarcred_private.amigoz_coefficient_calculate(200,200,cfg,'amigoz_23');
 for i in 0..5 loop
  if (r->i->>'troco')::numeric<>expected[i+1] then raise exception 'Wrong reference %',i;end if;
 end loop;
 if (r->0->>'comprometimento_total')::numeric<>139.55 then raise exception 'Wrong component installments';end if;
 r=apoiarcred_private.amigoz_coefficient_calculate(350,10000,cfg,'amigoz_23');
 if (r->0->>'saque_bruto')::numeric<>7347.55 or r->0->>'parcela_quitacao' is not null then raise exception 'Unvalidated debt adjustment';end if;
 r=apoiarcred_private.amigoz_coefficient_calculate(200,200,cfg,'amigoz_23','{"3":100}'::jsonb);
 if (r->0->>'troco')::numeric<>4098.60 then raise exception 'Bank IOF precedence';end if;
 ctx=public.amigoz_simulation_context('000.000.001-91','amigoz_23',(select job from coefficient_fixture));
 select x->>'key' into k from jsonb_array_elements(ctx->'margens') x where x->>'matricula'='A';
 r=public.amigoz_simular_coeficientes(jsonb_build_object('cpf','00000000191','job_id',(select job from coefficient_fixture),'convenio','amigoz_23','mode','aggregate','margin_key',k));
 if (r->>'base')::numeric<>250 or (r->>'margem_adicional')::numeric<>50 then raise exception 'Wrong aggregation';end if;
 select count(*) into before_count from public.amigoz_coefficient_simulations;
 r=public.amigoz_exportar_estimativas(jsonb_build_array(jsonb_build_object('cpf','00000000191','job_id',(select job from coefficient_fixture),'convenio','amigoz_23')));
 if (r->0->>'base')::numeric<>250 then raise exception 'Export lost selected margin';end if;
 if (select count(*) from public.amigoz_coefficient_simulations)<>before_count then raise exception 'Export writes simulations';end if;
 r=public.amigoz_simular_coeficientes(jsonb_build_object('cpf','00000000191','job_id',(select job from coefficient_fixture),'convenio','amigoz_23','mode','manual','manual',229.37));
 if (r->>'base')::numeric<>229.37 then raise exception 'Manual total double counted';end if;
 select x->>'key' into k from jsonb_array_elements(ctx->'margens') x where x->>'matricula'='B';
 r=public.amigoz_simular_coeficientes(jsonb_build_object('cpf','00000000191','convenio','amigoz_23','mode','aggregate','margin_key',k));
 if jsonb_array_length(r->'tabelas')<>0 then raise exception 'Ineligible margin accepted';end if;
 begin
  perform public.amigoz_simular_coeficientes('{"cpf":"00000000191","convenio":"amigoz_23","mode":"original","prazo":84}');
  raise exception 'Unexpected acceptance' using errcode='XX001';
 exception when sqlstate 'P0001' then null;end;
end$$;
reset role;
update public.consulta_jobs set valor_parcela=201 where id=(select job from coefficient_fixture);
set local role authenticated;
do $$declare r jsonb;begin
 r=public.amigoz_exportar_estimativas(jsonb_build_array(jsonb_build_object('cpf','00000000191','job_id',(select job from coefficient_fixture),'convenio','amigoz_23')));
 if jsonb_array_length(r->0->'tabelas')<>0 or position('desatualizada' in r->0->>'motivo')=0 then raise exception 'Stale simulation exported';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub',(select other_uid::text from coefficient_fixture),true);
set local role authenticated;
do $$declare r jsonb;begin
 if exists(select 1 from public.amigoz_coefficient_simulations) then raise exception 'Cross-account history';end if;
 begin perform public.amigoz_simulation_context('00000000191','amigoz_23',(select job from coefficient_fixture));raise exception 'Cross-account source' using errcode='XX001';exception when sqlstate 'P0001' then null;end;
 begin perform public.amigoz_save_model('{}');raise exception 'Partner changed model' using errcode='XX001';exception when insufficient_privilege then null;end;
end$$;
rollback;
