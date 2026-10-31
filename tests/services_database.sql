begin;
create temporary table service_fixture as select gen_random_uuid() uid;
grant select on service_fixture to authenticated;
insert into auth.users(id,aud,role,email) select uid,'authenticated','authenticated',uid::text||'@test.invalid' from service_fixture;
set local role authenticated;
do $$ declare cid uuid; denied boolean=false; begin
 perform set_config('request.jwt.claim.sub',(select uid::text from service_fixture),true);
 cid=public.create_consulta_campaign('SERVICE TEST','[{"nome":"TESTE","cpf":"00123456789","telefone":"11999999999"}]'::jsonb,'digimais_saldo_parcela');
 if not exists(select 1 from public.consulta_lotes where id=cid and servico='digimais_saldo_parcela') or not exists(select 1 from public.consulta_jobs where lote_id=cid and servico='digimais_saldo_parcela') then raise exception 'Service identity missing';end if;
 begin perform public.create_consulta_campaign('UNAVAILABLE','[{"nome":"TESTE","cpf":"00123456789","telefone":"11999999999"}]'::jsonb,'margem');exception when raise_exception then denied=true;end;
 if not denied or exists(select 1 from public.consulta_lotes where nome='UNAVAILABLE') then raise exception 'Unavailable service accepted';end if;
end $$;
reset role;
rollback;
select 'PASS: service identity persisted; unavailable margin service rejected without creating campaign; fixtures rolled back' result;
