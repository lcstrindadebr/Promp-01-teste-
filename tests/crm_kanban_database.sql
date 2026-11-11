begin;
create temp table crm_test_users as select id,row_number() over(order by id) as n from auth.users order by id limit 2;
grant select on crm_test_users to authenticated;
insert into public.crm_cadastros(user_id,cpf,nome,ultima_atividade)
 select id,'00000000001','CRM test rollback',now() from crm_test_users on conflict do nothing;
select set_config('request.jwt.claim.sub',(select id::text from crm_test_users where n=1),true);
set local role authenticated;
do $$
declare result integer; opp uuid;
begin
 select count(*) into result from public.crm_cadastros where cpf='00000000001';
 if result<>1 then raise exception 'FAIL owner isolation'; end if;
 insert into public.crm_card_settings(visible,fields) values(array['cpf'],'[{"id":"cf_1234567890abcdef","label":"Contato previsto","type":"date","visible":true}]');
 insert into public.crm_oportunidades(cpf,nome,produto) values('00000000001','CRM test rollback','recompra') returning id into opp;
 update public.crm_oportunidades set campos='{"cf_1234567890abcdef":"2026-11-20"}',etapa='contato' where id=opp;
 if not exists(select 1 from public.crm_opportunity_cards where id=opp and etapa='contato' and campos->>'cf_1234567890abcdef'='2026-11-20') then raise exception 'FAIL persistence'; end if;
 begin
  update public.crm_oportunidades set campos='{"saldo":100}' where id=opp;
  raise exception 'FAIL financial override accepted';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 begin
  update public.crm_card_settings set fields='[{"id":"cf_1234567890abcdef","label":"Margem editável","type":"date","visible":true}]';
  raise exception 'FAIL protected name accepted';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise; end if; end;
 select count(*) into result from public.crm_filter_clients('CRM test rollback');
 if result<>1 then raise exception 'FAIL filtered owner search'; end if;
 if exists(select 1 from public.crm_filter_clients('CRM test rollback','SP','missing')) then raise exception 'FAIL unknown classification'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from crm_test_users where n=2),true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.crm_opportunity_cards where nome='CRM test rollback') then raise exception 'FAIL cross-user read'; end if;
 if exists(select 1 from public.crm_card_settings where user_id<>(select auth.uid())) then raise exception 'FAIL settings isolation'; end if;
 update public.crm_oportunidades set etapa='ganho' where nome='CRM test rollback';
 if found then raise exception 'FAIL cross-user update'; end if;
end $$;
reset role;
select 'PASS: persistence, protected fields, owner filters, cross-user isolation' as result;
rollback;
