-- Simuladores por convênio: SIAPE no catálogo, regra de liberação, cálculo por coeficiente igual à
-- calculadora da AKI Capital, administração só pela equipe e Amigoz bloqueado fora dos seus convênios.
begin;
create temporary table sm as select gen_random_uuid() owner,gen_random_uuid() adm,gen_random_uuid() other,
 gen_random_uuid() lot,gen_random_uuid() job,gen_random_uuid() other_lot,gen_random_uuid() other_job;
grant select on sm to authenticated;
insert into auth.users(id,aud,role,email) select x,'authenticated','authenticated',x::text||'@sm.invalid' from sm,unnest(array[owner,adm,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select owner,'partner','P',owner::text||'@sm.invalid' from sm
 union all select adm,'admin','Equipe',adm::text||'@sm.invalid' from sm
 union all select other,'partner','O',other::text||'@sm.invalid' from sm;
alter table public.consulta_jobs disable trigger guard_partner_job;alter table public.consulta_lotes disable trigger guard_partner_lot;
insert into public.consulta_lotes(id,user_id,nome,tipo) select lot,owner,'Avulsa','individual' from sm union all select other_lot,other,'Outra','individual' from sm;
insert into public.consulta_jobs(id,lote_id,user_id,nome,cpf,telefone,status,saldo_liquidacao,valor_parcela)
 select job,lot,owner,'Cliente','00000000191','11999999999','concluida',5000,300 from sm
 union all select other_job,other_lot,other,'Outro','00000000272','11999999999','concluida',5000,300 from sm;

do $$ begin
 if not exists(select 1 from public.crm_catalogo_importacao where uf='BR' and codigo='amigoz_13' and nome='SIAPE') then raise exception 'SIAPE missing from catalog';end if;
 if not apoiarcred_private.simulador_liberado('aki_siape',false,'amigoz_13') then raise exception 'AKI not on SIAPE';end if;
 if apoiarcred_private.simulador_liberado('aki_siape',false,'tjba') then raise exception 'AKI on TJBA';end if;
 if not apoiarcred_private.simulador_liberado('amigoz',false,'amigoz_13') then raise exception 'Amigoz not on SIAPE';end if;
 if apoiarcred_private.simulador_liberado('amigoz',false,'tjba') then raise exception 'Amigoz on TJBA';end if;
 if not apoiarcred_private.simulador_liberado('amigoz',true,null) then raise exception 'Amigoz not on Digi+ consultations';end if;
end $$;

set local role authenticated;
do $$
declare f sm; r jsonb; t jsonb;
begin
 select * into f from sm;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 -- Configuração para o painel.
 r:=public.simuladores_config();
 if jsonb_array_length(r)<>2 or r->1->>'codigo'<>'aki_siape' or jsonb_array_length(r->1->'tabelas')<>7 then raise exception 'Config wrong: %',r;end if;
 -- Mesmos valores da calculadora da AKI Capital: parcela 300, sem margem.
 r:=public.simular_coeficientes('aki_siape','cartao_credito',300,0,0,null,'amigoz_13');
 if jsonb_array_length(r->'tabelas')<>6 then raise exception 'Credit tables wrong: %',r;end if;
 if (r->'tabelas'->0->>'bruto')::numeric<>6928.85 or (r->'tabelas'->5->>'bruto')::numeric<>7899.97 then raise exception 'Gross wrong: %',r->'tabelas';end if;
 r:=public.simular_coeficientes('aki_siape','cartao_beneficio',300,0,0,null,'amigoz_13');
 if jsonb_array_length(r->'tabelas')<>1 or (r->'tabelas'->0->>'bruto')::numeric<>7721.89 then raise exception 'Benefit wrong: %',r;end if;
 -- Com margem e saldo: base = 300 + 50; liberado = bruto − saldo; saldo maior que o bruto sinalizado.
 r:=public.simular_coeficientes('aki_siape','cartao_beneficio',300,50,1000,null,'amigoz_13');
 t:=r->'tabelas'->0;
 if (r->>'base')::numeric<>350 or (t->>'bruto')::numeric<>round(350/0.038850608,2)
  or (t->>'liberado')::numeric<>round(350/0.038850608,2)-1000 or (t->>'saldo_maior')::boolean then raise exception 'Margin/balance wrong: %',r;end if;
 r:=public.simular_coeficientes('aki_siape','cartao_beneficio',300,0,8000,null,'amigoz_13');
 if not (r->'tabelas'->0->>'saldo_maior')::boolean or (r->'tabelas'->0->>'liberado')::numeric>=0 then raise exception 'Negative release not flagged: %',r;end if;
 -- A partir da consulta Digi+ da própria conta.
 r:=public.simular_coeficientes('aki_siape','cartao_credito',300,0,5000,f.job);
 if (r->'tabelas'->0->>'liberado')::numeric<>1928.85 then raise exception 'Digi+ job wrong: %',r->'tabelas'->0;end if;
 -- Convênio sem o simulador, consulta de outra empresa e valores inválidos são recusados.
 begin perform public.simular_coeficientes('aki_siape','cartao_credito',300,0,0,null,'tjba');raise exception 'TJBA accepted';
 exception when raise_exception then if sqlerrm not like '%não está disponível%' then raise;end if;end;
 begin perform public.simular_coeficientes('aki_siape','cartao_credito',300,0,0,f.other_job);raise exception 'Other company job accepted';
 exception when raise_exception then if sqlerrm not like 'Consulta não encontrada%' then raise;end if;end;
 begin perform public.simular_coeficientes('aki_siape','cartao_credito',0,0,0,null,'amigoz_13');raise exception 'Zero installment accepted';
 exception when raise_exception then if sqlerrm not like 'Informe o valor%' then raise;end if;end;
 -- Parceiro não administra.
 begin perform public.admin_simulador_salvar('aki_siape',true,true,array['amigoz_13']);raise exception 'Partner changed simulator';
 exception when insufficient_privilege then null;end;
 -- Amigoz fora do convênio dele.
 begin perform public.amigoz_simulation_context('00000000191','tjba',null);raise exception 'Amigoz opened on TJBA';
 exception when raise_exception then if sqlerrm not like '%Amigoz não está disponível%' then raise;end if;end;

 -- Equipe: desliga a AKI nas consultas Digi+, troca um coeficiente e desativa uma tabela.
 perform set_config('request.jwt.claim.sub',f.adm::text,true);
 perform public.admin_simulador_salvar('aki_siape',true,false,array['amigoz_13']);
 perform public.admin_simulador_tabela_salvar('aki_siape','30077','CC_CP_SIAPE_PQ_F11_CO_CCC','cartao_credito',0.05,true,1);
 perform public.admin_simulador_tabela_salvar('aki_siape','30082','CC_CP_SIAPE_PQ_F16_CO_CCC','cartao_credito',0.037974818,false,6);
 begin perform public.admin_simulador_salvar('aki_siape',true,false,array['nao_existe']);raise exception 'Unknown agreement accepted';
 exception when raise_exception then if sqlerrm not like 'Convênio fora do catálogo%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 r:=public.simular_coeficientes('aki_siape','cartao_credito',300,0,0,null,'amigoz_13');
 if jsonb_array_length(r->'tabelas')<>5 or (r->'tabelas'->0->>'bruto')::numeric<>6000 then raise exception 'Admin changes not applied: %',r->'tabelas';end if;
 begin perform public.simular_coeficientes('aki_siape','cartao_credito',300,0,0,f.job);raise exception 'Digi+ still enabled';
 exception when raise_exception then if sqlerrm not like '%não está disponível%' then raise;end if;end;
end $$;
reset role;
rollback;
