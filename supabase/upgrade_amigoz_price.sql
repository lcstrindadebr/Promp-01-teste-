create or replace function apoiarcred_private.amigoz_price(p_margem numeric,p_taxa numeric,p_prazo integer,p_quitacao numeric,p_condicoes jsonb default '{}',p_comissao numeric default null) returns jsonb language plpgsql immutable set search_path='' as $$
declare i numeric; fator numeric; capacidade numeric; financiado numeric; liquido numeric; encargos numeric; fixo numeric=0; percentual numeric=0; teto numeric; parcela numeric; troco numeric; modo text; tipo_teto text; resultado jsonb;
begin
 if p_margem is null or p_margem<0 or p_taxa is null or p_taxa<0 or p_prazo is null or p_prazo not between 1 and 600 or p_quitacao is null or p_quitacao<0 or jsonb_typeof(p_condicoes)<>'object' or p_condicoes is null or p_comissao<0 or p_comissao>100 then raise exception 'Margem, taxa, prazo, quitação ou comissão inválidos.';end if;
 if p_margem::text in ('NaN','Infinity') or p_taxa::text in ('NaN','Infinity') or p_quitacao::text in ('NaN','Infinity') then raise exception 'Use valores finitos.';end if;
 i=p_taxa/100;
 if coalesce(p_condicoes->>'tipo_taxa','mensal')='anual_efetiva' then i=power(1+i,1::numeric/12)-1;
 elsif coalesce(p_condicoes->>'tipo_taxa','mensal')<>'mensal' then raise exception 'Tipo de taxa inválido.';end if;
 fator=case when i=0 then p_prazo else (1-power(1+i,-p_prazo))/i end;
 capacidade=floor(floor(p_margem*100)/100*fator*100)/100;
 modo=coalesce(p_condicoes->>'encargos_modo','nao_informados');
 teto=(p_condicoes->>'teto')::numeric;tipo_teto=coalesce(p_condicoes->>'tipo_teto','liquido');
 if teto is not null and (teto<0 or teto::text in ('NaN','Infinity')) then raise exception 'Teto inválido.';end if;
 if tipo_teto not in ('liquido','financiado') then raise exception 'Defina se o teto é líquido ou financiado.';end if;
 resultado=jsonb_build_object('taxa',p_taxa,'taxa_mensal',i*100,'prazo',p_prazo,'capacidade_financiada',capacidade,'quitacao',p_quitacao,'percentual',p_comissao,'condicoes',p_condicoes);
 if modo='nao_informados' then return resultado||jsonb_build_object('limite',null,'troco',null,'comissao',null,'insuficiente',false,'pendente_encargos',true,'observacao','Informe os encargos desta proposta para calcular limite líquido e troco.');end if;
 if modo='total_informado' then fixo=(p_condicoes->>'encargos_total')::numeric;
 elsif modo='percentual_e_fixo' then fixo=(p_condicoes->>'despesa_fixa')::numeric;percentual=(p_condicoes->>'encargos_percentual')::numeric/100;
 elsif modo<>'sem_encargos' then raise exception 'Modo de encargos inválido.';end if;
 if fixo is null or percentual is null or fixo<0 or percentual<0 or fixo::text in ('NaN','Infinity') or percentual::text in ('NaN','Infinity') then raise exception 'Encargos inválidos.';end if;
 financiado=case when teto is not null and tipo_teto='financiado' then least(capacidade,teto) else capacidade end;
 if financiado<fixo then return resultado||jsonb_build_object('limite',null,'troco',null,'comissao',null,'insuficiente',true,'pendente_encargos',false,'observacao','A capacidade financiada não cobre os encargos informados.');end if;
 liquido=floor((financiado-fixo)/(1+percentual)*100)/100;
 if teto is not null and tipo_teto='liquido' then liquido=least(liquido,floor(teto*100)/100);end if;
 encargos=round(fixo+liquido*percentual,2);financiado=liquido+encargos;
 parcela=round(financiado/fator,2);
 while parcela>p_margem or financiado>capacidade or (teto is not null and tipo_teto='financiado' and financiado>teto) loop
  liquido=liquido-.01;
  if liquido<0 then raise exception 'Não há limite compatível com a margem.';end if;
  encargos=round(fixo+liquido*percentual,2);financiado=liquido+encargos;parcela=round(financiado/fator,2);
 end loop;
 troco=liquido-p_quitacao;
 return resultado||jsonb_build_object('limite',liquido,'liberado',liquido,'troco',case when troco>=0 then troco else null end,'insuficiente',troco<0,'pendente_encargos',false,'encargos_financiados',encargos,'total_financiado',financiado,'parcela_conferida',parcela,'comissao',case when troco>=0 and p_comissao is not null then round((p_quitacao+troco)*p_comissao/100,2) else null end);
end $$;
revoke all on function apoiarcred_private.amigoz_price(numeric,numeric,integer,numeric,jsonb,numeric) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.amigoz_price(numeric,numeric,integer,numeric,jsonb,numeric) to authenticated;
create or replace function public.simular_amigoz_price(p_job_id uuid,p_prazo integer default 96,p_condicoes jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.consulta_jobs; v_taxa numeric; pct numeric; cond jsonb; parcela_simulada numeric; resultados jsonb='[]';saida jsonb;
begin
 if auth.uid() is null then raise exception 'Entre na sua conta.';end if;
 if p_prazo is null or p_prazo not between 1 and 600 or p_condicoes is null or jsonb_typeof(p_condicoes)<>'object' then raise exception 'Prazo ou condições inválidos.';end if;
 select * into j from public.consulta_jobs where id=p_job_id and user_id=auth.uid();
 if not found then raise exception 'Consulta não encontrada.';end if;
 if j.status in ('aguardando','processando','nao_cliente','nao_localizado') or coalesce(j.saldo_liquidacao,0)<=0 or coalesce(j.valor_parcela,0)<=0 then raise exception 'Aguarde saldo e parcela positivos da mesma consulta.';end if;
 parcela_simulada=coalesce((p_condicoes->>'_parcela_simulada')::numeric,j.valor_parcela);
 if parcela_simulada<=0 or parcela_simulada::text in ('NaN','Infinity','-Infinity') then raise exception 'Parcela simulada inválida.';end if;
 foreach v_taxa in array array[3,3.25,3.5,3.75,3.98,4.5,4.8]::numeric[] loop
  select percentual into pct from public.amigoz_comissoes where user_id=auth.uid() and amigoz_comissoes.taxa=v_taxa;
  cond=coalesce(p_condicoes->v_taxa::text,'{}'::jsonb);
  -- These seven tables have contractual monthly interest rates.
  cond=cond||jsonb_build_object('tipo_taxa','mensal');
  resultados=resultados||jsonb_build_array(apoiarcred_private.amigoz_price(parcela_simulada,v_taxa,p_prazo,j.saldo_liquidacao,cond,pct));
 end loop;
 saida=jsonb_build_object('job_id',j.id,'saldo',j.saldo_liquidacao,'parcela',j.valor_parcela,'parcela_simulada',parcela_simulada,'margem_adicional',greatest(parcela_simulada-j.valor_parcela,0),'prazo',p_prazo,'primeiro_vencimento_meses',1,'metodo','price_juros_contratuais_encargos_separados_v2','data_simulacao',now(),'tabelas',resultados);
 insert into public.amigoz_simulacoes(job_id,resultado) values(j.id,saida);return saida;
end $$;
revoke all on function public.simular_amigoz_price(uuid,integer,jsonb) from public,anon;
grant execute on function public.simular_amigoz_price(uuid,integer,jsonb) to authenticated;
create or replace function public.simular_amigoz(p_job_id uuid) returns jsonb language sql security invoker set search_path='' as $$select public.simular_amigoz_price(p_job_id,96,'{}'::jsonb);$$;
