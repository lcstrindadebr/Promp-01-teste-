-- Escopo do painel: 'avulsas' traz campanhas e consultas avulsas, sem as consultas de campanha;
-- 'tudo' segue igual. Logs: encerradas mais recentes, por robô ou por API, só da empresa.
begin;
create temporary table pe as select gen_random_uuid() owner,gen_random_uuid() other,
 gen_random_uuid() camp,gen_random_uuid() solo,gen_random_uuid() tj_solo,gen_random_uuid() other_solo;
grant select on pe to authenticated;
insert into auth.users(id,aud,role,email) select x,'authenticated','authenticated',x::text||'@pe.invalid' from pe,unnest(array[owner,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select x,'partner','P',x::text||'@pe.invalid' from pe,unnest(array[owner,other]) x;
alter table public.consulta_jobs disable trigger guard_partner_job;alter table public.consulta_jobs disable trigger assign_digimais_execution;alter table public.consulta_lotes disable trigger guard_partner_lot;
alter table public.tjba_jobs disable trigger guard_partner_job;alter table public.tjba_lotes disable trigger guard_partner_lot;
insert into public.consulta_lotes(id,user_id,nome,tipo) select camp,owner,'Campanha PE','campanha' from pe
 union all select solo,owner,'Avulsa','individual' from pe union all select other_solo,other,'Outra','individual' from pe;
insert into public.tjba_lotes(id,user_id,nome,tipo) select tj_solo,owner,'Avulsa ConsigX','individual' from pe;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status,robot_slot,execution_mode,consultado_em)
 select camp,owner,'Camp '||g,lpad(g::text,11,'0'),'11999999999','concluida',1+g%2,'robot',now()-make_interval(mins=>g) from pe,generate_series(1,30) g
 union all select solo,owner,'Solo','00000000191','11999999999','erro',null,'robot',now() from pe
 union all select camp,owner,'Na fila','00000000999','11999999999','aguardando',null,'robot',null from pe
 union all select other_solo,other,'Outra','00000000272','11999999999','concluida',1,'robot',now() from pe;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status,execution_mode,api_slot,consultado_em)
 select camp,owner,'Api '||g,lpad((700+g)::text,11,'0'),'11999999999','concluida','api',g,now()-make_interval(mins=>g) from pe,generate_series(1,3) g;
insert into public.tjba_jobs(lote_id,user_id,nome,cpf,status,robot_slot,consultado_em) select tj_solo,owner,'Margem','00000000353','concluida',2,now()-interval '1 second' from pe;
-- Linhas desta transação ainda não estão no instantâneo da sincronização: marca como já publicadas.
alter table public.consulta_jobs disable trigger painel_marcar_mudanca;alter table public.tjba_jobs disable trigger painel_marcar_mudanca;
alter table public.consulta_lotes disable trigger painel_marcar_mudanca;alter table public.tjba_lotes disable trigger painel_marcar_mudanca;
update public.consulta_jobs set sync_xid=null;update public.tjba_jobs set sync_xid=null;
update public.consulta_lotes set sync_xid=null;update public.tjba_lotes set sync_xid=null;

set local role authenticated;
do $$
declare f pe; r jsonb; keys text;
begin
 select * into f from pe;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 -- Avulsas: as duas consultas avulsas do dono e os lotes; nenhuma consulta de campanha.
 r:=public.painel_consultas_sync(null,null,null,'avulsas');
 select string_agg(x->>'origem',',' order by x->>'origem') into keys from jsonb_array_elements(r->'rows') x where x->>'origem' like '%jobs';
 if keys<>'consulta_jobs,tjba_jobs' then raise exception 'Avulsas scope wrong: %',keys;end if;
 if not exists(select 1 from jsonb_array_elements(r->'rows') x where (x->>'id')::uuid=f.camp) then raise exception 'Campaign lot missing';end if;
 -- Padrão: tudo, como antes (34 consultas do dono + 2 lotes de consulta + 1 de ConsigX + 1 ConsigX).
 r:=public.painel_consultas_sync(null,null,null);
 if (select count(*) from jsonb_array_elements(r->'rows') x where x->>'origem'='consulta_jobs')<>35 then raise exception 'Full scope wrong';end if;

 -- Log dos robôs: só encerradas, sem API, mais recentes primeiro, por robô.
 r:=public.painel_log_consultas('robo','',500);
 if jsonb_array_length(r)<>32 then raise exception 'Robot log size wrong: %',jsonb_array_length(r);end if;
 if r->0->>'nome'<>'Solo' or r->1->>'nome'<>'Margem' then raise exception 'Robot log order wrong: % %',r->0->>'nome',r->1->>'nome';end if;
 r:=public.painel_log_consultas('robo','2',500);
 if jsonb_array_length(r)<>16 then raise exception 'Robot slot filter wrong: %',jsonb_array_length(r);end if;
 r:=public.painel_log_consultas('robo','unassigned',500);
 if jsonb_array_length(r)<>1 or r->0->>'nome'<>'Solo' then raise exception 'Unassigned filter wrong: %',r;end if;
 r:=public.painel_log_consultas('robo','',5);
 if jsonb_array_length(r)<>5 then raise exception 'Limit wrong';end if;
 -- Log da API.
 r:=public.painel_log_consultas('api','',50);
 if jsonb_array_length(r)<>3 or r->0->>'nome'<>'Api 1' then raise exception 'API log wrong: %',r;end if;
 r:=public.painel_log_consultas('api','2',50);
 if jsonb_array_length(r)<>1 then raise exception 'API slot filter wrong';end if;
 begin perform public.painel_log_consultas('outro');raise exception 'Bad mode accepted';exception when raise_exception then
  if sqlerrm not like 'Modo de log%' then raise;end if;end;
 -- Outra empresa não aparece.
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 if jsonb_array_length(public.painel_log_consultas('robo'))<>1 then raise exception 'Other company leaked into log';end if;
end $$;
reset role;
rollback;
