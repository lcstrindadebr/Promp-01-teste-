begin;
create temporary table amigoz_fixture as select gen_random_uuid() uid,gen_random_uuid() other_uid,gen_random_uuid() job,gen_random_uuid() lot;
grant select on amigoz_fixture to authenticated;
insert into auth.users(id,aud,role,email) select uid,'authenticated','authenticated',uid::text||'@test.invalid' from amigoz_fixture union all select other_uid,'authenticated','authenticated',other_uid::text||'@test.invalid' from amigoz_fixture;
insert into public.consulta_lotes(id,user_id,nome,tipo) select lot,uid,'TESTE','individual' from amigoz_fixture;
insert into public.consulta_jobs(id,lote_id,user_id,nome,cpf,telefone,status,saldo_liquidacao,valor_parcela) select job,lot,uid,'TESTE','00123456789','11999999999','concluida',1000,179.37 from amigoz_fixture;
set local role authenticated;
do $$ declare f record; r jsonb; item jsonb; denied boolean=false; begin
 select * into f from amigoz_fixture;
 perform set_config('request.jwt.claim.sub',f.uid::text,true);
 insert into public.amigoz_comissoes(taxa,percentual) values (3,5),(3.25,0);
 r=public.simular_amigoz(f.job);
 if jsonb_array_length(r->'tabelas')<>7 then raise exception 'Seven tables required'; end if;
 if (r#>>'{tabelas,0,troco}')::numeric<>3780.17 or (r#>>'{tabelas,0,comissao}')::numeric<>239.01 then raise exception 'CET estimate/commission incorrect'; end if;
 if (r#>>'{tabelas,1,comissao}')::numeric<>0 or r#>>'{tabelas,2,comissao}' is not null then raise exception 'Zero and unset must differ'; end if;
 for item in select value from jsonb_array_elements(r->'tabelas') loop
 if (item->>'liberado')::numeric<>(item->>'troco')::numeric+(item->>'quitacao')::numeric then raise exception 'Double cost deduction'; end if;
 if item->>'limite' is not null then raise exception 'Invented limit'; end if;
 end loop;
 perform set_config('request.jwt.claim.sub',f.other_uid::text,true);
 if exists(select 1 from public.amigoz_comissoes) or exists(select 1 from public.amigoz_simulacoes) then raise exception 'Owner isolation failed'; end if;
 begin perform public.simular_amigoz(f.job); exception when raise_exception then denied=true; end;
 if not denied then raise exception 'Unauthorized simulation'; end if;
end $$;
reset role;
update public.consulta_jobs set saldo_liquidacao=999999 where id=(select job from amigoz_fixture);
set local role authenticated;
do $$ declare r jsonb; begin
 perform set_config('request.jwt.claim.sub',(select uid::text from amigoz_fixture),true);
 r=public.simular_amigoz((select job from amigoz_fixture));
 if exists(select 1 from jsonb_array_elements(r->'tabelas') t where not (t->>'insuficiente')::boolean or t->>'troco' is not null or t->>'comissao' is not null) then raise exception 'Insufficient availability failed'; end if;
end $$;
reset role;
rollback;
select 'PASS: seven CET tables, commission rounding, zero/unset, no duplicate costs, no invented limit, insufficient availability, owner isolation; fixtures rolled back' result;
