begin;
create temporary table campaign_fixture as select gen_random_uuid() as owner_id,gen_random_uuid() as other_id,null::uuid as campaign_id;
grant all on campaign_fixture to authenticated;
insert into auth.users(id,aud,role,email)
select owner_id,'authenticated','authenticated',owner_id::text||'@campaign-test.invalid' from campaign_fixture
union all select other_id,'authenticated','authenticated',other_id::text||'@campaign-test.invalid' from campaign_fixture;
set local role authenticated;
do $$
declare owner_uuid uuid; other_uuid uuid; cid uuid; refused boolean:=false;
begin
 select owner_id,other_id into owner_uuid,other_uuid from campaign_fixture;
 perform set_config('request.jwt.claim.sub',owner_uuid::text,true);
 cid:=public.create_consulta_campaign('Campaign transaction fixture','[{"nome":"TESTE","cpf":"00123456789","telefone":"11999999999"}]'::jsonb);
 update campaign_fixture set campaign_id=cid;
 if (select count(*) from public.consulta_jobs where lote_id=cid)<>1 then raise exception 'Campaign creation failed'; end if;
 begin perform public.create_consulta_campaign('Invalid campaign fixture','[{"nome":"TESTE","cpf":"invalid","telefone":"11999999999"}]'::jsonb); exception when check_violation then refused:=true; end;
 if not refused or exists(select 1 from public.consulta_lotes where nome='Invalid campaign fixture') then raise exception 'Campaign creation is not atomic'; end if;
 perform set_config('request.jwt.claim.sub',other_uuid::text,true);
 if exists(select 1 from public.consulta_lotes where id=cid) then raise exception 'RLS exposed campaign'; end if;
 refused:=false;
 begin perform public.retry_consulta_campaign(cid); exception when insufficient_privilege then refused:=true; end;
 if not refused then raise exception 'Unauthorized campaign retry accepted'; end if;
end $$;
reset role;
update public.consulta_jobs set status='concluida',saldo_liquidacao=100,total_parcelas=12,valor_parcela=10 where lote_id=(select campaign_id from campaign_fixture);
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status)
select campaign_id,owner_id,'TESTE','0000000000'||n::text,'11999999999',s from campaign_fixture cross join (values(1,'erro'),(2,'revisao'),(3,'nao_cliente'),(4,'processando')) as v(n,s);
set local role authenticated;
do $$
declare cid uuid; uid uuid; refused boolean:=false;
begin
 select campaign_id,owner_id into cid,uid from campaign_fixture;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 if public.retry_consulta_campaign(cid)<>2 then raise exception 'Retry must target exactly error/review'; end if;
 if public.retry_consulta_campaign(cid)<>0 then raise exception 'Duplicate retry must not duplicate jobs'; end if;
 if (select count(*) from public.consulta_jobs where lote_id=cid)<>5 then raise exception 'Retry inflated campaign size'; end if;
 if (select count(*) from public.consulta_jobs where lote_id=cid and status='processando')<>1 then raise exception 'Running job was changed'; end if;
 if (select count(*) from public.consulta_jobs where lote_id=cid and status='nao_cliente')<>1 then raise exception 'Nonclient was changed'; end if;
 if not exists(select 1 from public.consulta_jobs where lote_id=cid and status='concluida' and saldo_liquidacao=100) then raise exception 'Completed result was changed'; end if;
 begin update public.consulta_jobs set saldo_liquidacao=1 where lote_id=cid; exception when insufficient_privilege then refused:=true; end;
 if not refused then raise exception 'Direct output write privilege exposed'; end if;
end $$;
reset role;
rollback;
select 'PASS: atomic creation, owner RLS, scoped retry, unchanged completed/nonclient/running jobs, stable totals, duplicate retry and output protection; fixtures rolled back' as result;
