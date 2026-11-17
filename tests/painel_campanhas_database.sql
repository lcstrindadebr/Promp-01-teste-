-- Campanhas paginadas: lista com totais, página de 50 na ordem da campanha, busca e filtro no banco,
-- números do detalhe, empresa e visibilidade.
begin;
create temporary table pk as select gen_random_uuid() owner,gen_random_uuid() op,gen_random_uuid() other,
 gen_random_uuid() camp,gen_random_uuid() tj,gen_random_uuid() op_camp,gen_random_uuid() other_camp;
grant select on pk to authenticated;
insert into auth.users(id,aud,role,email) select x,'authenticated','authenticated',x::text||'@pk.invalid' from pk,unnest(array[owner,op,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select x,'partner','P',x::text||'@pk.invalid' from pk,unnest(array[owner,other]) x;
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,pk.op,r.id from pk join apoiarcred_private.tenant_members m on m.user_id=pk.owner
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code='operador';

alter table public.consulta_jobs disable trigger guard_partner_job;alter table public.consulta_lotes disable trigger guard_partner_lot;
alter table public.tjba_jobs disable trigger guard_partner_job;alter table public.tjba_lotes disable trigger guard_partner_lot;
insert into public.consulta_lotes(id,user_id,nome,tipo,created_at) select camp,owner,'Servidores PK','campanha',now()-interval '1 day' from pk
 union all select op_camp,op,'Do operador','campanha',now() from pk
 union all select other_camp,other,'Outra empresa','campanha',now() from pk
 union all select gen_random_uuid(),owner,'Avulsa','individual',now() from pk;
insert into public.tjba_lotes(id,user_id,nome,tipo) select tj,owner,'ConsigX PK','campanha' from pk;
-- 120 clientes; a ordem da campanha vem de queue_order (decrescente aqui, para provar que não é a do id).
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status,queue_order,saldo_liquidacao,consultado_em) overriding system value
 select camp,owner,'Cliente '||g,lpad(g::text,11,'0'),'11999999999',
  case when g<=3 then 'processando' when g<=10 then 'aguardando' when g=120 then 'erro' when g=119 then 'revisao'
   when g<=60 then 'concluida' else 'nao_cliente' end,
  1000-g,case when g between 11 and 60 then 1500 end,
  case when g between 11 and 20 then now()-make_interval(secs=>g*10) when g>20 then now()-interval '2 hours' end
 from pk,generate_series(1,120) g;
insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone,status) select op_camp,op,'Op','00000000191','11999999999','aguardando' from pk
 union all select other_camp,other,'Outra','00000000272','11999999999','aguardando' from pk;
insert into public.tjba_jobs(lote_id,user_id,nome,cpf,status,matricula) select tj,owner,'T'||g,lpad((500+g)::text,11,'0'),
 case when g=1 then 'revisao' else 'concluida' end,case when g<=2 then 'M'||g end from pk,generate_series(1,4) g;

set local role authenticated;
do $$
declare f pk; r jsonb; c jsonb; first jsonb;
begin
 select * into f from pk;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 -- Lista: campanhas da empresa (não a avulsa nem a de outra empresa), com totais por situação.
 r:=public.painel_campanhas();
 if jsonb_array_length(r)<>3 then raise exception 'Campaign list wrong: %',r;end if;
 select x into c from jsonb_array_elements(r) x where (x->>'id')::uuid=f.camp;
 if (c->'contagens'->>'aguardando')::int<>7 or (c->'contagens'->>'processando')::int<>3 or (c->'contagens'->>'nao_cliente')::int<>58
 then raise exception 'Campaign counts wrong: %',c;end if;
 select x into c from jsonb_array_elements(r) x where (x->>'id')::uuid=f.tj;
 if c->>'servico'<>'tjba_margem' or (c->'contagens'->>'concluida')::int<>3 then raise exception 'ConsigX campaign wrong: %',c;end if;

 -- Página 1: 50 linhas, na ordem da campanha, com a posição de cada cliente.
 r:=public.painel_campanha(f.camp);
 if jsonb_array_length(r->'linhas')<>50 or (r->>'filtrados')::int<>120 then raise exception 'Page 1 wrong: %',r->'filtrados';end if;
 first:=r->'linhas'->0;
 if first->'dados'->>'nome'<>'Cliente 120' or (first->>'posicao')::int<>1 then raise exception 'Order wrong: %',first;end if;
 if first->'dados'->>'status'<>'erro' then raise exception 'Row data wrong: %',first;end if;
 if (r->'resumo'->>'total')::int<>120 or (r->'resumo'->>'waiting')::int<>10 or (r->'resumo'->>'running')::int<>3
  or (r->'resumo'->>'clients')::int<>50 or (r->'resumo'->>'nonclients')::int<>58 or (r->'resumo'->>'errors')::int<>1
  or (r->'resumo'->>'review')::int<>1 or (r->'resumo'->>'pace_count')::int<>10
 then raise exception 'Summary wrong: %',r->'resumo';end if;
 if jsonb_array_length(r->'consultando')<>3 then raise exception 'Running list wrong: %',r->'consultando';end if;
 -- Última página.
 r:=public.painel_campanha(f.camp,'','',3);
 if jsonb_array_length(r->'linhas')<>20 or (r->'linhas'->19->>'posicao')::int<>120 then raise exception 'Last page wrong';end if;
 -- Filtro "precisam de atenção" mantém a posição original.
 r:=public.painel_campanha(f.camp,'','attention');
 if (r->>'filtrados')::int<>2 or (r->'linhas'->1->>'posicao')::int<>2 then raise exception 'Attention filter wrong: %',r->'linhas';end if;
 -- Busca por nome e por CPF com pontuação.
 r:=public.painel_campanha(f.camp,'cliente 7','');
 if (r->>'filtrados')::int<>11 then raise exception 'Name search wrong: %',r->>'filtrados';end if;
 r:=public.painel_campanha(f.camp,'000.000.001-15','');
 if (r->>'filtrados')::int<>1 or r->'linhas'->0->'dados'->>'nome'<>'Cliente 115' then raise exception 'CPF search wrong: %',r->'linhas';end if;
 -- ConsigX: clientes localizados contam matrícula ou conclusão.
 r:=public.painel_campanha(f.tj);
 if (r->'resumo'->>'clients')::int<>4 or r->'linhas'->0->'dados'->>'matricula'<>'M1' then raise exception 'ConsigX detail wrong: %',r;end if;

 -- Operador: só a campanha dele; a do dono não abre.
 perform set_config('request.jwt.claim.sub',f.op::text,true);
 r:=public.painel_campanhas();
 if jsonb_array_length(r)<>1 or (r->0->>'id')::uuid<>f.op_camp then raise exception 'Operator list wrong: %',r;end if;
 begin perform public.painel_campanha(f.camp);raise exception 'Operator opened owner campaign';
 exception when no_data_found then null;end;
 -- Outra empresa não abre.
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 begin perform public.painel_campanha(f.camp);raise exception 'Other company opened campaign';
 exception when no_data_found then null;end;
end $$;
reset role;
rollback;
