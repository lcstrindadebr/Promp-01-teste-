-- Inadimplência: classificação pela assessoria (mesma regra do robô), situações aceitas,
-- números e filtro da campanha e log dos robôs.
begin;
do $$
declare r record;
begin
 select * into r from apoiarcred_private.inadimplencia_classificar('Informamos que seu contrato está sob a responsabilidade da nossa assessoria de cobrança,**MZ ASSESSORIA E COBRANÇA - (11)4293-0260**. Assim, todas');
 if r.status<>'inadimplencia_administrativa' or r.assessoria<>'MZ ASSESSORIA E COBRANÇA' or r.telefone<>'(11)4293-0260' then raise exception 'MZ wrong: %',r;end if;
 select * into r from apoiarcred_private.inadimplencia_classificar('assessoria de cobrança, J.S. SANTOS- JURIDICO. Assim, todas as negociações');
 if r.status<>'inadimplencia_juridica' or r.assessoria<>'J.S. SANTOS- JURIDICO' or r.telefone is not null then raise exception 'J.S. wrong: %',r;end if;
 select * into r from apoiarcred_private.inadimplencia_classificar('assessoria de cobrança,**PASQUALI JURIDICO - 0800 602 9934**. Assim');
 if r.status<>'inadimplencia_juridica' or r.assessoria<>'PASQUALI JURIDICO' or r.telefone<>'0800 602 9934' then raise exception 'Pasquali wrong: %',r;end if;
 select * into r from apoiarcred_private.inadimplencia_classificar('assessoria de cobrança,**VEZZI LAPOLLA ADV ASSOCIADOS**.');
 if r.status<>'inadimplencia_juridica' then raise exception 'ADV wrong: %',r;end if;
 select * into r from apoiarcred_private.inadimplencia_classificar('assessoria de cobrança,**AG DIST CONSIG - 31 A 60 DIAS**.');
 if r.status<>'inadimplencia_administrativa' or r.assessoria<>'AG DIST CONSIG - 31 A 60 DIAS' then raise exception 'AG wrong: %',r;end if;
 select * into r from apoiarcred_private.inadimplencia_classificar('sem assessoria');
 if r.status<>'inadimplencia_administrativa' or r.assessoria is not null then raise exception 'Empty wrong: %',r;end if;
end $$;

create temporary table ia as select gen_random_uuid() owner,gen_random_uuid() camp;
grant select on ia to authenticated;
insert into auth.users(id,aud,role,email) select owner,'authenticated','authenticated',owner::text||'@ia.invalid' from ia;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select owner,'partner','P',owner::text||'@ia.invalid' from ia;
alter table public.consulta_jobs disable trigger guard_partner_job;alter table public.consulta_lotes disable trigger guard_partner_lot;
alter table public.consulta_jobs disable trigger assign_digimais_execution;
insert into public.consulta_lotes(id,user_id,nome,tipo) select camp,owner,'Campanha IA','campanha' from ia;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status,message,consultado_em,robot_slot)
 select camp,owner,'Adm','00000000191','11999999999','inadimplencia_administrativa','Assessoria: MZ ASSESSORIA E COBRANÇA · (11)4293-0260',now(),1 from ia
 union all select camp,owner,'Jur','00000000272','11999999999','inadimplencia_juridica','Assessoria: PASQUALI JURIDICO · 0800 602 9934',now(),1 from ia
 union all select camp,owner,'Ok','00000000353','11999999999','concluida',null,now(),1 from ia;

set local role authenticated;
do $$
declare f ia; r jsonb;
begin
 select * into f from ia;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 r:=public.painel_campanha(f.camp);
 if (r->'resumo'->>'inad_adm')::int<>1 or (r->'resumo'->>'inad_jur')::int<>1 then raise exception 'Campaign counts wrong: %',r->'resumo';end if;
 r:=public.painel_campanha(f.camp,'','inadimplencia');
 if (r->>'filtrados')::int<>2 then raise exception 'Both-type filter wrong: %',r->>'filtrados';end if;
 r:=public.painel_campanha(f.camp,'','Inadimplência jurídica');
 if (r->>'filtrados')::int<>1 or r->'linhas'->0->'dados'->>'nome'<>'Jur' then raise exception 'Juridical filter wrong: %',r;end if;
 r:=public.painel_log_consultas('robo','',50);
 if jsonb_array_length(r)<>3 then raise exception 'Robot log missing delinquency: %',jsonb_array_length(r);end if;
end $$;
reset role;
rollback;
