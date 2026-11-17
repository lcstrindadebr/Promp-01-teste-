-- Contadores do painel: nascem iguais à contagem real, acompanham inclusão, mudança de situação,
-- troca de dono e exclusão, respeitam empresa e visibilidade, e a conferência corrige diferenças.
begin;
create temporary table pc as select gen_random_uuid() owner,gen_random_uuid() op,gen_random_uuid() other_owner,
 gen_random_uuid() camp,gen_random_uuid() indiv,gen_random_uuid() op_lot,gen_random_uuid() tj_camp,gen_random_uuid() other_lot, gen_random_uuid() unused;
grant select on pc to authenticated;

-- A contagem real e o resumo batem com os dados que já existem neste banco de teste.
do $$ begin
 if (apoiarcred_private.painel_contadores_conferir(false)->>'diferencas')::int<>0 then raise exception 'Initial backfill differs';end if;
end $$;

insert into auth.users(id,aud,role,email) select x,'authenticated','authenticated',x::text||'@pc.invalid' from pc,unnest(array[owner,op,other_owner]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select x,'partner','P',x::text||'@pc.invalid' from pc,unnest(array[owner,other_owner]) x;
-- Cada parceiro ganha a sua empresa; o operador entra na empresa do dono.
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,pc.op,r.id from pc join apoiarcred_private.tenant_members m on m.user_id=pc.owner
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code='operador';
alter table public.consulta_jobs disable trigger guard_partner_job;
alter table public.consulta_lotes disable trigger guard_partner_lot;
alter table public.tjba_jobs disable trigger guard_partner_job;
alter table public.tjba_lotes disable trigger guard_partner_lot;
insert into public.consulta_lotes(id,user_id,nome,tipo) select camp,owner,'Campanha PC','campanha' from pc
 union all select indiv,owner,'Individual','individual' from pc
 union all select op_lot,op,'Do operador','campanha' from pc
 union all select other_lot,other_owner,'Outra empresa','campanha' from pc;
insert into public.tjba_lotes(id,user_id,nome,tipo) select tj_camp,owner,'ConsigX PC','campanha' from pc;
-- Um comando com 50 consultas: um ajuste só.
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status)
 select camp,owner,'C'||g,lpad(g::text,11,'0'),'11999999999','aguardando' from pc,generate_series(1,50) g;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status)
 select indiv,owner,'Individual','00000000191','11999999999','concluida' from pc
 union all select op_lot,op,'Do operador','00000000272','11999999999','erro' from pc
 union all select other_lot,other_owner,'Outra','00000000353','11999999999','aguardando' from pc;
insert into public.tjba_jobs(lote_id,user_id,nome,cpf,status) select tj_camp,owner,'T'||g,lpad((100+g)::text,11,'0'),'aguardando' from pc,generate_series(1,5) g;

do $$
declare f pc; v bigint;
begin
 select * into f from pc;
 select n into v from apoiarcred_private.painel_contadores where lote_id=f.camp and status='aguardando';
 if v<>50 then raise exception 'Insert count wrong: %',v;end if;
 -- Situação muda: tira de uma, soma na outra; mudança só de progresso não mexe.
 update public.consulta_jobs set status='processando' where lote_id=f.camp and nome in ('C1','C2','C3');
 update public.consulta_jobs set status='concluida',consultado_em=now() where lote_id=f.camp and nome='C1';
 update public.consulta_jobs set progress=40 where lote_id=f.camp and nome='C2';
 if (select n from apoiarcred_private.painel_contadores where lote_id=f.camp and status='aguardando')<>47
  or (select n from apoiarcred_private.painel_contadores where lote_id=f.camp and status='processando')<>2
  or (select n from apoiarcred_private.painel_contadores where lote_id=f.camp and status='concluida')<>1
 then raise exception 'Status move wrong';end if;
 -- Exclusão: some a linha quando chega a zero.
 delete from public.consulta_jobs where lote_id=f.camp and nome='C1';
 if exists(select 1 from apoiarcred_private.painel_contadores where lote_id=f.camp and status='concluida') then raise exception 'Zero row kept';end if;
 update public.tjba_jobs set status='revisao' where lote_id=f.tj_camp and nome='T1';
 if (apoiarcred_private.painel_contadores_conferir(false)->>'diferencas')::int<>0 then raise exception 'Counters drifted';end if;
end $$;

-- O que o painel vê.
set local role authenticated;
do $$
declare f pc; r jsonb; c jsonb;
begin
 select * into f from pc;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 r:=public.painel_resumo();
 -- Administrador vê a empresa toda (inclui o operador), e nada da outra empresa.
 if (select sum((x->>'n')::int) from jsonb_array_elements(r->'contagens') x)<>1+49+1+5 then raise exception 'Owner totals wrong: %',r->'contagens';end if;
 select x into c from jsonb_array_elements(r->'contagens') x where x->>'tipo'='individual' and x->>'status'='concluida';
 if (c->>'n')::int<>1 or c->>'servico'<>'digimais_saldo_parcela' then raise exception 'Individual count wrong: %',c;end if;
 if jsonb_array_length(r->'campanhas_ativas')<>2 then raise exception 'Active campaigns wrong: %',r->'campanhas_ativas';end if;
 select x into c from jsonb_array_elements(r->'campanhas_ativas') x where (x->>'id')::uuid=f.camp;
 if (c->>'total')::int<>49 or (c->>'pendentes')::int<>49 or c->>'nome'<>'Campanha PC' then raise exception 'Campaign summary wrong: %',c;end if;
 if (r->'concluidas_hoje'->>'digimais_saldo_parcela') is not null then raise exception 'Individual without consultado_em counted today: %',r->'concluidas_hoje';end if;
 if jsonb_array_length(r->'atencao')<>2 then raise exception 'Attention list wrong: %',r->'atencao';end if;
 -- Operador só vê o que é dele.
 perform set_config('request.jwt.claim.sub',f.op::text,true);
 r:=public.painel_resumo();
 if jsonb_array_length(r->'contagens')<>1 or r->'contagens'->0->>'status'<>'erro' then raise exception 'Operator saw others: %',r;end if;
 if jsonb_array_length(r->'campanhas_ativas')<>0 or jsonb_array_length(r->'atencao')<>1 then raise exception 'Operator lists wrong: %',r;end if;
 -- Contadores não ficam expostos diretamente.
 begin perform 1 from apoiarcred_private.painel_contadores;raise exception 'Counters table readable';
 exception when insufficient_privilege then null;end;
end $$;
reset role;

-- Concluída hoje entra no número do dia.
do $$
declare f pc; r jsonb;
begin
 select * into f from pc;
 update public.consulta_jobs set status='concluida',consultado_em=now() where lote_id=f.camp and nome='C2';
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 r:=public.painel_resumo();
 if (r->'concluidas_hoje'->>'digimais_saldo_parcela')::int<>1 then raise exception 'Done today wrong: %',r->'concluidas_hoje';end if;
end $$;

-- Excluir a campanha leva os contadores junto; a conferência acha e corrige um desvio.
do $$
declare f pc; r jsonb;
begin
 select * into f from pc;
 delete from public.consulta_lotes where id=f.camp;
 if exists(select 1 from apoiarcred_private.painel_contadores where lote_id=f.camp) then raise exception 'Deleted campaign kept counters';end if;
 update apoiarcred_private.painel_contadores set n=n+7 where lote_id=f.tj_camp and status='aguardando';
 r:=apoiarcred_private.painel_contadores_conferir(true);
 if (r->>'diferencas')::int<>1 then raise exception 'Drift not found: %',r;end if;
 if (apoiarcred_private.painel_contadores_conferir(false)->>'diferencas')::int<>0 then raise exception 'Drift not fixed';end if;
 if not exists(select 1 from apoiarcred_private.painel_contadores_conferencias) then raise exception 'Check not logged';end if;
end $$;
rollback;
