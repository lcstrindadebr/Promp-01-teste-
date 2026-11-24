-- Início: clientes do CRM e oportunidades por situação, no escopo de quem pergunta.
begin;
create temporary table ct as select gen_random_uuid() owner,gen_random_uuid() other;
grant select on ct to authenticated;
insert into auth.users(id,aud,role,email) select u,'authenticated','authenticated',u::text||'@ct.invalid' from ct,unnest(array[owner,other]) u;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select u,'partner','P',u::text||'@ct.invalid' from ct,unnest(array[owner,other]) u;

insert into public.crm_cadastros(user_id,cpf,nome,ultima_atividade) select owner,c,'Cliente',now() from ct,unnest(array['00000000191','00000000272','00000000353']) c;
insert into public.crm_cadastros(user_id,cpf,nome,ultima_atividade) select other,'00000000434','Outra empresa',now() from ct;
insert into public.crm_oportunidades(user_id,cpf,nome,produto,convenio,etapa)
 select owner,'00000000191','Cliente','recompra','INSS','novo' from ct
 union all select owner,'00000000272','Cliente','recompra','INSS','ganho' from ct
 union all select owner,'00000000353','Cliente','recompra','INSS','perdido' from ct
 union all select owner,'00000000353','Cliente','margem','INSS','novo' from ct
 union all select other,'00000000434','Outra','recompra','INSS','novo' from ct;

set local role authenticated;
do $$
declare f ct; r jsonb;
begin
 select * into f from ct;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 r:=public.painel_crm_totais();
 if (r->>'clientes')::int<>3 then raise exception 'Clients wrong: %',r;end if;
 if (r->'oportunidades'->>'abertas')::int<>2 or (r->'oportunidades'->>'ganhas')::int<>1
  or (r->'oportunidades'->>'perdidas')::int<>1 or (r->'oportunidades'->>'total')::int<>4 then raise exception 'Opportunities wrong: %',r;end if;
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 r:=public.painel_crm_totais();
 if (r->>'clientes')::int<>1 or (r->'oportunidades'->>'total')::int<>1 then raise exception 'Other company sees wrong data: %',r;end if;
end $$;
reset role;
do $$ begin
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.painel_crm_totais();raise exception 'Anonymous call must fail';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
