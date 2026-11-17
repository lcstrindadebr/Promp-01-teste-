-- Saúde da fila: só a equipe vê; fila esperando sem conclusões recentes = parada; campanha pausada não conta.
begin;
create temporary table qh as select gen_random_uuid() adm,gen_random_uuid() partner,gen_random_uuid() lot,gen_random_uuid() paused_lot;
grant select on qh to authenticated;
insert into auth.users(id,aud,role,email) select x,'authenticated','authenticated',x::text||'@qh.invalid' from qh,unnest(array[adm,partner]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select adm,'admin','Equipe',adm::text||'@qh.invalid' from qh;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select partner,'partner','P',partner::text||'@qh.invalid' from qh;
-- Isolate from fixtures of other tests in this database: only our rows exist in this transaction view.
delete from public.consulta_jobs;delete from public.tjba_jobs;
insert into public.consulta_lotes(id,user_id,nome,tipo,paused) select lot,adm,'QH','campanha',false from qh union all select paused_lot,adm,'QH pausada','campanha',true from qh;
alter table public.consulta_jobs disable trigger user;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status,created_at)
 select lot,adm,'Espera','00000000191','11999999999','aguardando',now()-interval '40 minutes' from qh
 union all select paused_lot,adm,'Pausada','00000000272','11999999999','aguardando',now()-interval '90 minutes' from qh;
alter table public.consulta_jobs enable trigger user;
set local role authenticated;
do $$
declare f qh; r jsonb; d jsonb;
begin
 select * into f from qh;
 perform set_config('request.jwt.claim.sub',f.partner::text,true);
 begin perform public.admin_queue_health();raise exception 'Partner saw queue health';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',f.adm::text,true);
 r:=public.admin_queue_health();
 select x into d from jsonb_array_elements(r->'servicos') x where x->>'servico'='digimais_saldo_parcela';
 if (d->>'na_fila')::int<>1 then raise exception 'Paused campaign counted: %',d;end if;
 if (d->>'espera_minutos')::int not between 39 and 41 then raise exception 'Wait time wrong: %',d;end if;
 if not (d->>'parada')::boolean then raise exception 'Stalled queue not flagged: %',d;end if;
end $$;
reset role;
-- A recent completion means the queue is moving.
alter table public.consulta_jobs disable trigger user;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status,consultado_em)
 select lot,adm,'Feita','00000000353','11999999999','concluida',now()-interval '2 minutes' from qh;
alter table public.consulta_jobs enable trigger user;
set local role authenticated;
do $$
declare f qh; d jsonb;
begin
 select * into f from qh;perform set_config('request.jwt.claim.sub',f.adm::text,true);
 select x into d from jsonb_array_elements(public.admin_queue_health()->'servicos') x where x->>'servico'='digimais_saldo_parcela';
 if (d->>'parada')::boolean or (d->>'concluidas_hora')::int<>1 then raise exception 'Moving queue flagged: %',d;end if;
end $$;
reset role;
rollback;
