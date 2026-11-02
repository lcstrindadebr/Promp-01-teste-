begin;
create temporary table cx_test as select gen_random_uuid() uid;
grant select on cx_test to authenticated;
insert into auth.users(id,aud,role,email) select uid,'authenticated','authenticated',uid::text||'@test.invalid' from cx_test;
set local role authenticated;
do $$ declare c text; lot uuid;
begin
 perform set_config('request.jwt.claim.sub',(select uid::text from cx_test),true);
 foreach c in array array['tjba','dpeba','embasa','saeb','suprev'] loop
  lot=public.create_consigx_campaign('TEST','[{"cpf":"00000000191"}]',c);
  if not exists(select 1 from public.tjba_jobs j where j.lote_id=lot and j.convenio=c) then raise exception 'Wrong agreement';end if;
 end loop;
end $$;
rollback;
