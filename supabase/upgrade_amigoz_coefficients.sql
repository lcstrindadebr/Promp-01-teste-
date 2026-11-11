-- Versioned observed coefficients. Financial arithmetic stays in PostgreSQL numeric.
create table public.amigoz_model_versions (
 id bigint generated always as identity primary key,
 created_at timestamptz not null default now(),
 created_by uuid default auth.uid(),
 config jsonb not null
);
alter table public.amigoz_model_versions enable row level security;
revoke all on public.amigoz_model_versions from public,anon,authenticated;
grant select on public.amigoz_model_versions to authenticated;
create policy amigoz_model_read on public.amigoz_model_versions for select to authenticated using(true);

insert into public.amigoz_model_versions(config) values ('{
 "prazo":96,"default_convenio":"amigoz_23",
 "eligibilidade":[{"convenio":"amigoz_23","produtos":["beneficio","consignado"],"instituicoes":["amigoz"],"taxas":[3,3.25,3.5,3.75,3.98,4.5]}],
 "tabelas":[
 {"taxa":3,"cet":3.63,"multiplicador":29.99,"iof_referencia":139.30,"parcela_quitacao":6.55,"parcela_saque":133.00},
 {"taxa":3.25,"cet":3.88,"multiplicador":28.02,"iof_referencia":130.30,"parcela_quitacao":7.01,"parcela_saque":132.84},
 {"taxa":3.5,"cet":4.13,"multiplicador":26.26,"iof_referencia":122.23,"parcela_quitacao":7.47,"parcela_saque":132.67},
 {"taxa":3.75,"cet":4.38,"multiplicador":24.67,"iof_referencia":114.91,"parcela_quitacao":7.93,"parcela_saque":132.43},
 {"taxa":3.98,"cet":4.61,"multiplicador":23.36,"iof_referencia":108.87,"parcela_quitacao":8.37,"parcela_saque":132.27},
 {"taxa":4.5,"cet":5.13,"multiplicador":20.82,"iof_referencia":97.11,"parcela_quitacao":9.37,"parcela_saque":131.94}]
}'::jsonb);

create table public.amigoz_coefficient_simulations (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 cpf text not null,
 convenio text not null,
 created_at timestamptz not null default now(),
 version_id bigint not null references public.amigoz_model_versions(id),
 input jsonb not null,
 fingerprint text not null,
 resultado jsonb not null
);
create index amigoz_coefficient_history on public.amigoz_coefficient_simulations(user_id,cpf,convenio,created_at desc);
alter table public.amigoz_coefficient_simulations enable row level security;
revoke all on public.amigoz_coefficient_simulations from public,anon,authenticated;
grant select,insert on public.amigoz_coefficient_simulations to authenticated;
create policy amigoz_coefficient_owner on public.amigoz_coefficient_simulations for all to authenticated
 using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));

create function apoiarcred_private.amigoz_save_model(p_config jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare entry jsonb; result bigint;
begin
 if not apoiarcred_private.is_admin(auth.uid()) then raise insufficient_privilege;end if;
 if p_config is null or jsonb_typeof(p_config)<>'object' or (p_config->>'prazo')::integer is distinct from 96
 or jsonb_typeof(p_config->'tabelas') is distinct from 'array'
 or jsonb_array_length(p_config->'tabelas')<>6
 or jsonb_typeof(p_config->'eligibilidade') is distinct from 'array' then
  raise exception 'Informe as seis tabelas de 96 parcelas e os convênios elegíveis.';
 end if;
 if (select count(distinct (x->>'taxa')::numeric) from jsonb_array_elements(p_config->'tabelas') x)<>6 then raise exception 'Taxas repetidas';end if;
 for entry in select value from jsonb_array_elements(p_config->'tabelas') loop
  if coalesce((entry->>'taxa')::numeric,0) not in (3,3.25,3.5,3.75,3.98,4.5)
   or not coalesce((entry->>'multiplicador')::numeric between 0.01 and 1000,false)
   or not coalesce((entry->>'iof_referencia')::numeric between 0 and (entry->>'multiplicador')::numeric*140,false)
   or not coalesce((entry->>'cet')::numeric between 0 and 100,false)
   or not coalesce((entry->>'parcela_quitacao')::numeric between 0 and 10000,false)
   or not coalesce((entry->>'parcela_saque')::numeric between 0 and 10000,false) then raise exception 'Coeficiente inválido';end if;
 end loop;
 for entry in select value from jsonb_array_elements(p_config->'eligibilidade') loop
  if not exists(select 1 from public.crm_catalogo_importacao where codigo=entry->>'convenio')
   or jsonb_typeof(entry->'produtos') is distinct from 'array'
   or jsonb_typeof(entry->'instituicoes') is distinct from 'array'
   or jsonb_typeof(entry->'taxas') is distinct from 'array' then raise exception 'Regra de elegibilidade inválida';end if;
 end loop;
 if not exists(select 1 from jsonb_array_elements(p_config->'eligibilidade') x where x->>'convenio'=p_config->>'default_convenio') then raise exception 'Convênio padrão inválido';end if;
 insert into public.amigoz_model_versions(config) values(p_config) returning id into result;
 return result;
end $$;
revoke all on function apoiarcred_private.amigoz_save_model(jsonb) from public,anon;
grant execute on function apoiarcred_private.amigoz_save_model(jsonb) to authenticated;
create function public.amigoz_save_model(p_config jsonb) returns bigint language sql security invoker set search_path='' as $$select apoiarcred_private.amigoz_save_model(p_config);$$;
revoke all on function public.amigoz_save_model(jsonb) from public,anon;
grant execute on function public.amigoz_save_model(jsonb) to authenticated;

create function public.amigoz_simulation_context(p_cpf text,p_convenio text default '',p_job_id uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare uid uuid=auth.uid(); cpf_value text=regexp_replace(p_cpf,'\D','','g'); model public.amigoz_model_versions;
 j public.consulta_jobs; fact public.crm_dados_cliente; agreement text=nullif(p_convenio,''); agreements text[];
 margins jsonb; rules jsonb; source jsonb; known boolean; assumed boolean=false;
begin
 if uid is null then raise insufficient_privilege;end if;
 if cpf_value is null or cpf_value !~ '^[0-9]{11}$' then raise exception 'CPF inválido';end if;
 select * into model from public.amigoz_model_versions order by id desc limit 1;
 if p_job_id is not null then
  select * into j from public.consulta_jobs where id=p_job_id and user_id=uid and cpf=cpf_value;
  if not found then raise exception 'Consulta não encontrada na sua conta';end if;
 else
  select * into j from public.consulta_jobs where user_id=uid and cpf=cpf_value
  order by coalesce(consultado_em,created_at) desc,id desc limit 1;
 end if;
 select * into fact from public.crm_dados_cliente where user_id=uid and cpf=cpf_value and tipo='saldo_parcela'
 order by registrado_em desc limit 1;
 known=j.id is not null or exists(select 1 from public.crm_cadastros where user_id=uid and cpf=cpf_value);
 if not known then raise exception 'Cliente não encontrado na sua conta';end if;
 source=jsonb_build_object('job_id',j.id,'data',coalesce(j.consultado_em,j.created_at),'status',j.status,
  'saldo',case when j.status in ('concluida','revisao') then j.saldo_liquidacao end,
  'parcela',case when j.status in ('concluida','revisao') then j.valor_parcela end);
 if p_job_id is null and fact.registrado_em>coalesce(j.consultado_em,j.created_at,'-infinity'::timestamptz) then
  source=jsonb_build_object('job_id',null,'data',fact.registrado_em,'status',fact.dados->>'status',
   'saldo',fact.dados->'saldo','parcela',fact.dados->'parcela');
 end if;
 select array_agg(distinct convenio) into agreements from (
  select convenio from public.crm_vinculos where user_id=uid and cpf=cpf_value
  union select convenio from public.crm_margens_vinculo where user_id=uid and cpf=cpf_value
 ) links;
 if agreement is null then
  if coalesce(cardinality(agreements),0)=1 then agreement=agreements[1];
  elsif coalesce(cardinality(agreements),0)=0 and j.id is not null then agreement=model.config->>'default_convenio';assumed=true;
  end if;
 end if;
 select value into rules from jsonb_array_elements(model.config->'eligibilidade') where value->>'convenio'=agreement
  and (coalesce(cardinality(agreements),0)=0 or agreement=any(agreements));
 select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('key',md5(jsonb_build_array(m.convenio,m.matricula,m.instituicao,m.produto)::text),
  'elegivel',coalesce(rules->'produtos' ? m.produto and rules->'instituicoes' ? m.instituicao and m.valor>=0,false))
  order by m.observado_em desc,m.matricula,m.produto),'[]'::jsonb) into margins
 from public.crm_margens_vinculo m where m.user_id=uid and m.cpf=cpf_value and (agreement is null or m.convenio=agreement);
 return jsonb_build_object('cpf',cpf_value,'convenio',agreement,'convenio_assumido',assumed,'elegivel',rules is not null,
  'fonte',source,'margens',margins,'version_id',model.id,'config',model.config);
end $$;
revoke all on function public.amigoz_simulation_context(text,text,uuid) from public,anon;
grant execute on function public.amigoz_simulation_context(text,text,uuid) to authenticated;

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
revoke all on function apoiarcred_private.amigoz_coefficient_calculate(numeric,numeric,jsonb,text,jsonb) from public,anon;
grant execute on function apoiarcred_private.amigoz_coefficient_calculate(numeric,numeric,jsonb,text,jsonb) to authenticated;

create function public.amigoz_simular_coeficientes(p_input jsonb,p_save boolean default true) returns jsonb
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
 if p_save then
  insert into public.amigoz_coefficient_simulations(cpf,convenio,version_id,input,fingerprint,resultado)
  values(ctx->>'cpf',ctx->>'convenio',(ctx->>'version_id')::bigint,
   input_value||jsonb_build_object('mode',mode,'convenio',ctx->>'convenio'),fingerprint,output);
 end if;
 return output;
end $$;
revoke all on function public.amigoz_simular_coeficientes(jsonb,boolean) from public,anon;
grant execute on function public.amigoz_simular_coeficientes(jsonb,boolean) to authenticated;

create function public.amigoz_exportar_estimativas(p_items jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare item jsonb; result jsonb='[]'; output jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100 then raise exception 'Envie até 100 clientes por lote';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  begin
   output=public.amigoz_simular_coeficientes(item||jsonb_build_object('mode','auto','use_saved',true),false);
  exception when others then
   output=jsonb_build_object('tabelas','[]'::jsonb,'motivo','Dados indisponíveis ou incompatíveis para simular.');
  end;
  result=result||jsonb_build_array(output);
 end loop;
 return result;
end $$;
revoke all on function public.amigoz_exportar_estimativas(jsonb) from public,anon;
grant execute on function public.amigoz_exportar_estimativas(jsonb) to authenticated;
notify pgrst,'reload schema';

-- Preserve the existing RPC entry point for installed clients.
create or replace function public.simular_amigoz_price(p_job_id uuid,p_prazo integer default 96,p_condicoes jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare customer text; result jsonb;
begin
 select cpf into customer from public.consulta_jobs where id=p_job_id and user_id=auth.uid();
 if customer is null then raise exception 'Consulta não encontrada na sua conta';end if;
 result=public.amigoz_simular_coeficientes(jsonb_build_object('cpf',customer,'job_id',p_job_id,'prazo',p_prazo,
  'mode',case when p_condicoes ? '_parcela_simulada' then 'manual' else 'original' end,
  'manual',p_condicoes->'_parcela_simulada'));
 return result||jsonb_build_object('parcela_simulada',result->'base');
end $$;

-- Bring older Amigoz array snapshots into the per-registration margin catalogue.
insert into public.crm_margens_vinculo(user_id,cpf,convenio,matricula,instituicao,produto,valor,observado_em,origem)
select distinct on (d.user_id,d.cpf,d.convenio,coalesce(x->>'numeroMatricula',x->>'numero_matricula',''),x->>'idProduto')
 d.user_id,d.cpf,d.convenio,coalesce(x->>'numeroMatricula',x->>'numero_matricula',''),'amigoz',
 case x->>'idProduto' when '7' then 'beneficio' when '15' then 'consignado' else 'cartao' end,
 (x->>'margem_atual')::numeric,d.registrado_em,d.origem
from public.crm_dados_cliente d cross join lateral jsonb_array_elements(case when jsonb_typeof(d.dados)='array' then d.dados else '[]'::jsonb end) x
where d.tipo='margem' and d.instituicao='amigoz' and d.convenio is not null
 and jsonb_typeof(x->'margem_atual')='number' and x->>'idProduto' in ('7','15')
order by d.user_id,d.cpf,d.convenio,coalesce(x->>'numeroMatricula',x->>'numero_matricula',''),x->>'idProduto',d.registrado_em desc
on conflict(user_id,cpf,convenio,matricula,instituicao,produto) do update set
 valor=excluded.valor,observado_em=excluded.observado_em,origem=excluded.origem
where public.crm_margens_vinculo.observado_em<excluded.observado_em;
