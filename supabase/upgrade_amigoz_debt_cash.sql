-- Run after upgrade_amigoz_coefficients.sql. Existing grants are preserved.
-- Debt is reserved before the 70% withdrawal; minimum gross withdrawal R$ 315.
begin;
create or replace function apoiarcred_private.amigoz_coefficient_calculate(p_base numeric,p_debt numeric,p_config jsonb,p_agreement text,p_bank_iof jsonb default '{}') returns jsonb
language plpgsql immutable set search_path='' as $$
declare t jsonb; rule jsonb; limit_value numeric; remaining numeric; gross numeric; tax numeric; cash numeric; state text; tables jsonb='[]';
begin
 if p_base is null or not(p_base between 0 and 10000000) or (p_debt is not null and not(p_debt between 0 and 1000000000)) then raise exception 'Valores inválidos';end if;
 select value into rule from jsonb_array_elements(p_config->'eligibilidade') where value->>'convenio'=p_agreement;
 for t in select value from jsonb_array_elements(p_config->'tabelas') order by (value->>'taxa')::numeric loop
  if not coalesce(rule->'taxas' @> jsonb_build_array((t->>'taxa')::numeric),false) then continue;end if;
  limit_value=round(p_base*(t->>'multiplicador')::numeric,2);
  remaining=case when p_debt is not null then greatest(limit_value-p_debt,0) end;
  gross=round(remaining*0.70,2);
  tax=round(gross*(t->>'iof_referencia')::numeric/((t->>'multiplicador')::numeric*200*0.70),2);
  if p_bank_iof ? (t->>'taxa') and gross>0 then
   tax=(p_bank_iof->>(t->>'taxa'))::numeric;
   if tax is null or not(tax between 0 and gross) then raise exception 'IOF informado inválido';end if;
  end if;
  state=case when p_debt is null then 'quitacao_pendente'
   when limit_value<p_debt then 'limite_insuficiente'
   when gross<315 or gross-tax<=0 then 'pre_aprovada_sem_troco'
   else 'pre_aprovada_com_troco' end;
  cash=case when state='quitacao_pendente' then null when state='pre_aprovada_com_troco' then gross-tax else 0 end;
  tables=tables||jsonb_build_array(jsonb_build_object('taxa',(t->>'taxa')::numeric,'cet',(t->>'cet')::numeric,
   'prazo',96,'limite',limit_value,'limite_restante',remaining,'saque_bruto',gross,
   'regra_calculo','limite_residual_v1','saque_minimo',315,'saque_liberado',state='pre_aprovada_com_troco',
   'iof_saque',case when state='pre_aprovada_com_troco' then tax when state='quitacao_pendente' then null else 0 end,
   'troco',cash,'quitacao',p_debt,'situacao',state,'insuficiente',state='limite_insuficiente',
   'motivo',case state when 'quitacao_pendente' then 'Informe a quitação para calcular o troco.'
    when 'limite_insuficiente' then 'O limite não cobre a quitação da dívida.'
    when 'pre_aprovada_sem_troco' then 'Pré-aprovada sem troco: cobre a dívida, mas não há saque disponível de pelo menos R$ 315,00.'
    else 'Pré-aprovada com troco estimado, sujeita à confirmação no banco.' end,
   'origem_iof',case when p_bank_iof ? (t->>'taxa') then 'informado_instituicao' else 'estimativa_historica' end,
   'multiplicador',(t->>'multiplicador')::numeric,
   'parcela_quitacao',null,'parcela_saque',null,'comprometimento_total',null,
   'iof_quitacao',null,'preliminar',true));
 end loop;
 return tables;
end $$;

commit;
