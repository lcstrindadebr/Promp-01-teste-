create table public.amigoz_comissoes_tabela (
 user_id uuid not null references auth.users(id) on delete cascade,
 convenio text not null,
 tabela_id text not null,
 percentual numeric(7,4) check(percentual between 0 and 100),
 primary key(user_id,convenio,tabela_id)
);
alter table public.amigoz_comissoes_tabela enable row level security;
revoke all on public.amigoz_comissoes_tabela from public,anon,authenticated;
grant select on public.amigoz_comissoes_tabela to authenticated;
create policy amigoz_table_commission_read on public.amigoz_comissoes_tabela for select to authenticated
 using(user_id=(select auth.uid()));

create function apoiarcred_private.amigoz_save_tables(p_version bigint,p_config jsonb,p_comissoes jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); current_version bigint; cfg jsonb; rule jsonb; t jsonb; c jsonb; pct numeric;
begin
 if uid is null or not coalesce((apoiarcred_private.access_for(uid)->>'active')::boolean,false) then raise insufficient_privilege;end if;
 if p_config is not null and not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if jsonb_typeof(p_comissoes) is distinct from 'array' or jsonb_array_length(p_comissoes)>6000 then
  raise exception 'Lista de comissões inválida.';
 end if;
 perform pg_advisory_xact_lock(690134,1);
 select id,config into current_version,cfg from public.amigoz_model_versions order by id desc limit 1;
 if p_version is distinct from current_version then raise exception 'Existe uma versão mais recente. Reabra Tabelas antes de salvar.';end if;
 if p_config is not null then
  if jsonb_typeof(p_config) is distinct from 'object' or p_config->>'prazo' is distinct from '96'
   or jsonb_typeof(p_config->'eligibilidade') is distinct from 'array' or jsonb_array_length(p_config->'eligibilidade') not between 1 and 200
   or p_config->'tabelas' is distinct from cfg->'tabelas' then raise exception 'Configuração de tabelas inválida.';end if;
  if (select count(distinct x->>'convenio') from jsonb_array_elements(p_config->'eligibilidade') x)<>jsonb_array_length(p_config->'eligibilidade')
   or not exists(select 1 from jsonb_array_elements(p_config->'eligibilidade') x where x->>'convenio'=p_config->>'default_convenio')
   then raise exception 'Verifique os convênios e o convênio de referência.';end if;
  for rule in select value from jsonb_array_elements(p_config->'eligibilidade') loop
   if not exists(select 1 from public.crm_catalogo_importacao where codigo=rule->>'convenio')
    or jsonb_typeof(rule->'produtos') is distinct from 'array'
    or not (rule->'produtos' <@ '["emprestimo","cartao","beneficio","consignado"]'::jsonb)
    or jsonb_typeof(rule->'instituicoes') is distinct from 'array'
    or exists(select 1 from jsonb_array_elements(rule->'instituicoes') x where jsonb_typeof(x)<>'string' or length(x#>>'{}') not between 1 and 60)
    or jsonb_typeof(rule->'tabelas') is distinct from 'array' or jsonb_array_length(rule->'tabelas') not between 1 and 30
    then raise exception 'Convênio, elegibilidade ou quantidade de tabelas inválida.';end if;
   if (select count(distinct x->>'id') from jsonb_array_elements(rule->'tabelas') x)<>jsonb_array_length(rule->'tabelas')
    then raise exception 'Identificadores de tabela repetidos.';end if;
   for t in select value from jsonb_array_elements(rule->'tabelas') loop
    if not coalesce(t->>'id' ~ '^(legacy-[0-9]+([.][0-9]+)?|[0-9a-f-]{36})$',false)
     or not coalesce(length(btrim(t->>'nome')) between 1 and 100,false)
     or not coalesce((t->>'taxa')::numeric between 0.01 and 100,false)
     or not coalesce((t->>'cet')::numeric between 0 and 100,false)
     or not coalesce((t->>'multiplicador')::numeric between 0.01 and 1000,false)
     or not coalesce((t->>'iof_referencia')::numeric between 0 and (t->>'multiplicador')::numeric*140,false)
     or not coalesce((t->>'parcela_saque')::numeric between 0 and 10000,false)
     or not coalesce((t->>'parcela_quitacao')::numeric between 0 and 10000,false)
     then raise exception 'Confira o nome e os coeficientes da tabela.';end if;
   end loop;
  end loop;
  cfg=p_config;
 end if;
 for c in select value from jsonb_array_elements(p_comissoes) loop
  if not exists(
   select 1 from jsonb_array_elements(cfg->'eligibilidade') r
   cross join lateral jsonb_array_elements(coalesce(r->'tabelas',cfg->'tabelas')) x
   where r->>'convenio'=c->>'convenio'
    and (r->'tabelas' is not null or r->'taxas' @> jsonb_build_array((x->>'taxa')::numeric))
    and coalesce(x->>'id','legacy-'||trim_scale((x->>'taxa')::numeric)::text)=c->>'tabela_id'
  ) then raise exception 'Tabela de comissão não encontrada.';end if;
  pct=(c->>'percentual')::numeric;
  if pct is not null and not (pct between 0 and 100) then raise exception 'Comissão deve estar entre 0 e 100.';end if;
  insert into public.amigoz_comissoes_tabela(user_id,convenio,tabela_id,percentual)
  values(uid,c->>'convenio',c->>'tabela_id',pct)
  on conflict(user_id,convenio,tabela_id) do update set percentual=excluded.percentual;
 end loop;
 if p_config is not null then
  insert into public.amigoz_model_versions(config) values(cfg) returning id into current_version;
 end if;
 return current_version;
end $$;
revoke all on function apoiarcred_private.amigoz_save_tables(bigint,jsonb,jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.amigoz_save_tables(bigint,jsonb,jsonb) to authenticated;
create function public.amigoz_save_tables(p_version bigint,p_config jsonb,p_comissoes jsonb) returns bigint
language sql security invoker set search_path='' as $$
 select apoiarcred_private.amigoz_save_tables(p_version,p_config,p_comissoes);
$$;
revoke all on function public.amigoz_save_tables(bigint,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.amigoz_save_tables(bigint,jsonb,jsonb) to authenticated;

create or replace function apoiarcred_private.amigoz_coefficient_calculate(p_base numeric,p_debt numeric,p_config jsonb,p_agreement text,p_bank_iof jsonb default '{}') returns jsonb
language plpgsql immutable set search_path='' as $$
declare t jsonb; rule jsonb; limit_value numeric; remaining numeric; gross numeric; tax numeric; cash numeric; state text; tables jsonb='[]';
begin
 if p_base is null or not(p_base between 0 and 10000000) or (p_debt is not null and not(p_debt between 0 and 1000000000)) then raise exception 'Valores inválidos';end if;
 select value into rule from jsonb_array_elements(p_config->'eligibilidade') where value->>'convenio'=p_agreement;
 for t in select value from jsonb_array_elements(coalesce(rule->'tabelas',p_config->'tabelas')) with ordinality as r(value,ord) order by (value->>'taxa')::numeric,ord loop
  if rule->'tabelas' is null and not coalesce(rule->'taxas' @> jsonb_build_array((t->>'taxa')::numeric),false) then continue;end if;
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
  tables=tables||jsonb_build_array(jsonb_build_object('tabela_id',coalesce(t->>'id','legacy-'||trim_scale((t->>'taxa')::numeric)::text),'nome_tabela',t->>'nome','taxa',(t->>'taxa')::numeric,'cet',(t->>'cet')::numeric,
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

create or replace function public.amigoz_simular_coeficientes(p_input jsonb,p_save boolean default true) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare ctx jsonb; margin jsonb; mode text=coalesce(p_input->>'mode','original'); base numeric; debt numeric;
 fingerprint text; output jsonb; saved public.amigoz_coefficient_simulations; original numeric; stale boolean=false;
 candidates jsonb; input_value jsonb=p_input;
begin
 ctx=public.amigoz_simulation_context(p_input->>'cpf',coalesce(p_input->>'convenio',''),(p_input->>'job_id')::uuid);
 if not(ctx->>'elegivel')::boolean then
  return jsonb_build_object('tabelas','[]'::jsonb,'motivo','Selecione um convênio com produto Amigoz habilitado.','contexto',ctx);
 end if;
 if coalesce((p_input->>'prazo')::integer,96)<>96 then raise exception 'Coeficientes disponíveis para 96 parcelas';end if;
 if coalesce((p_input->>'use_saved')::boolean,false) then
  select * into saved from public.amigoz_coefficient_simulations
   where user_id=auth.uid() and cpf=ctx->>'cpf' and convenio=ctx->>'convenio'
   and (p_input->>'job_id' is null or resultado->>'job_id'=p_input->>'job_id')
   and (p_input->>'matricula' is null or resultado->'margem_selecionada'->>'matricula'=p_input->>'matricula')
   and (p_input->>'instituicao' is null or resultado->'margem_selecionada'->>'instituicao'=p_input->>'instituicao')
   and (p_input->>'produto' is null or resultado->'margem_selecionada'->>'produto'=p_input->>'produto')
   order by created_at desc,id desc limit 1;
  if saved.id is not null then input_value=saved.input;mode=input_value->>'mode';end if;
 end if;
 original=(ctx->'fonte'->>'parcela')::numeric;debt=(ctx->'fonte'->>'saldo')::numeric;
 if mode='auto' then
  mode=case when coalesce(p_input->>'source','')<>'margin' and original>0 then 'original' else 'margin' end;
  if mode='margin' then
   select jsonb_agg(value) into candidates from jsonb_array_elements(ctx->'margens')
    where (value->>'elegivel')::boolean
    and (p_input->>'matricula' is null or value->>'matricula'=p_input->>'matricula')
    and (p_input->>'instituicao' is null or value->>'instituicao'=p_input->>'instituicao')
    and (p_input->>'produto' is null or value->>'produto'=p_input->>'produto');
   if jsonb_array_length(candidates)=1 then input_value=input_value||jsonb_build_object('margin_key',candidates->0->>'key');end if;
  end if;
 end if;
 if mode in ('margin','aggregate') then
  select value into margin from jsonb_array_elements(ctx->'margens') where value->>'key'=input_value->>'margin_key' and (value->>'elegivel')::boolean;
  if margin is null then
   return jsonb_build_object('tabelas','[]'::jsonb,'motivo','Selecione uma margem elegível do vínculo correto.','contexto',ctx);
  end if;
 end if;
 case mode
  when 'original' then base=original;
  when 'margin' then base=(margin->>'valor')::numeric;
  when 'aggregate' then base=original+(margin->>'valor')::numeric;
  when 'manual' then base=(input_value->>'manual')::numeric;
  else raise exception 'Modo de simulação inválido';
 end case;
 if base is null or base<0 or ((mode in ('original','aggregate')) and coalesce(original,0)<=0) then
  return jsonb_build_object('tabelas','[]'::jsonb,'motivo','Parcela ou margem insuficiente para simular.','contexto',ctx);
 end if;
 fingerprint=md5(jsonb_build_object('fonte',ctx->'fonte','margem',margin,'base',base,'versao',ctx->'version_id','convenio',ctx->'convenio')::text);
 stale=saved.id is not null and saved.fingerprint<>fingerprint;
 if stale then
  return jsonb_build_object('tabelas','[]'::jsonb,'motivo','Simulação salva desatualizada. Recalcule antes de exportar.','contexto',ctx);
 end if;
 output=jsonb_build_object('cpf',ctx->'cpf','convenio',ctx->'convenio','convenio_assumido',ctx->'convenio_assumido',
  'job_id',ctx->'fonte'->'job_id','fonte',ctx->'fonte','parcela',original,'saldo',debt,'base',base,
  'margem_adicional',case when mode='aggregate' then (margin->>'valor')::numeric when mode='manual' then greatest(base-coalesce(original,0),0) else 0 end,
  'margem_selecionada',margin,'modo',mode,'version_id',ctx->'version_id','prazo',96,'data_simulacao',now(),
  'preliminar',true,'motivo',case when debt is null then 'Simulação preliminar · saldo de quitação pendente' else 'Simulação preliminar · confirmar condições no banco' end,
  'tabelas',apoiarcred_private.amigoz_coefficient_calculate(base,debt,ctx->'config',ctx->>'convenio',coalesce(input_value->'iof_banco','{}'::jsonb)));
 output=jsonb_set(output,'{tabelas}',(
  select coalesce(jsonb_agg(t.value||jsonb_build_object('percentual',rate.percentual,'comissao',
   case when t.value->>'situacao' in ('pre_aprovada_com_troco','pre_aprovada_sem_troco')
    then round(rate.percentual*((t.value->>'quitacao')::numeric+(t.value->>'troco')::numeric)/100,2) end) order by t.ord),'[]'::jsonb)
  from jsonb_array_elements(output->'tabelas') with ordinality t(value,ord)
  left join public.amigoz_comissoes_tabela c on c.user_id=auth.uid() and c.convenio=ctx->>'convenio' and c.tabela_id=t.value->>'tabela_id'
  left join public.amigoz_comissoes legacy on legacy.user_id=auth.uid()
   and ('legacy-'||trim_scale(legacy.taxa)::text)=t.value->>'tabela_id'
  cross join lateral (select case when c.user_id is not null then c.percentual else legacy.percentual end as percentual) rate
 ));
 if p_save then
  insert into public.amigoz_coefficient_simulations(cpf,convenio,version_id,input,fingerprint,resultado)
  values(ctx->>'cpf',ctx->>'convenio',(ctx->>'version_id')::bigint,
   input_value||jsonb_build_object('mode',mode,'convenio',ctx->>'convenio'),fingerprint,output);
 end if;
 return output;
end $$;
notify pgrst,'reload schema';
