-- Simuladores por convênio.
-- Cada simulador (Amigoz, AKI Capital · SIAPE e os que vierem) fica liberado para uma lista de convênios
-- do catálogo e, se marcado, para as consultas Digi+ (que não informam o convênio do cliente).
-- Simuladores por coeficiente (como a AKI Capital) guardam as tabelas no banco e calculam aqui:
--   base = parcela (+ margem); valor bruto = base ÷ coeficiente, arredondado ao centavo (meio para cima);
--   valor liberado = valor bruto − saldo devedor.
-- Só a equipe ApoiarCred altera simuladores, convênios e tabelas.

begin;

-- 1. Convênio federal SIAPE no catálogo (código Amigoz 13; sem matrícula nem senha obrigatórias).
insert into public.crm_catalogo_importacao(uf,codigo,nome,servicos,matricula_obrigatoria,senha_servidor)
values('BR','amigoz_13','SIAPE',array['amigoz_margem','amigoz_saque','digimais_saldo'],false,false)
on conflict (uf,codigo) do nothing;

-- 2. Simuladores, convênios liberados e tabelas de coeficientes.
create table public.simuladores(
 codigo text primary key check(codigo ~ '^[a-z0-9_]{2,40}$'),
 nome text not null check(length(btrim(nome)) between 1 and 80),
 banco text not null check(length(btrim(banco)) between 1 and 80),
 tipo text not null check(tipo in ('amigoz','coeficiente')),
 ativo boolean not null default true,
 consultas_digimais boolean not null default false,
 ordem integer not null default 0,
 atualizado_em timestamptz not null default now()
);
create table public.simulador_convenios(
 simulador text not null references public.simuladores(codigo) on delete cascade,
 uf text not null,
 convenio text not null,
 primary key(simulador,uf,convenio),
 foreign key(uf,convenio) references public.crm_catalogo_importacao(uf,codigo) on delete cascade
);
create index simulador_convenios_convenio on public.simulador_convenios(convenio);
create table public.simulador_tabelas(
 simulador text not null references public.simuladores(codigo) on delete cascade,
 codigo text not null check(length(btrim(codigo)) between 1 and 40),
 nome text not null check(length(btrim(nome)) between 1 and 120),
 produto text not null check(produto in ('cartao_beneficio','cartao_credito')),
 coeficiente numeric(14,9) not null check(coeficiente>0),
 ativa boolean not null default true,
 ordem integer not null default 0,
 atualizado_em timestamptz not null default now(),
 primary key(simulador,codigo)
);
alter table public.simuladores enable row level security;
alter table public.simulador_convenios enable row level security;
alter table public.simulador_tabelas enable row level security;
revoke all on public.simuladores,public.simulador_convenios,public.simulador_tabelas from public,anon,authenticated;
grant select on public.simuladores,public.simulador_convenios,public.simulador_tabelas to authenticated;
create policy leitura on public.simuladores for select to authenticated using (true);
create policy leitura on public.simulador_convenios for select to authenticated using (true);
create policy leitura on public.simulador_tabelas for select to authenticated using (true);

-- Situação inicial: Amigoz nos convênios em que opera (inclui SIAPE) e nas consultas Digi+;
-- AKI Capital no SIAPE e nas consultas Digi+ (a carteira SIAPE do Digi+).
insert into public.simuladores(codigo,nome,banco,tipo,consultas_digimais,ordem) values
 ('amigoz','Amigoz','Amigoz','amigoz',true,10),
 ('aki_siape','AKI Capital · SIAPE','AKI Capital','coeficiente',true,20);
insert into public.simulador_convenios(simulador,uf,convenio)
 select 'amigoz',uf,codigo from public.crm_catalogo_importacao where servicos && array['amigoz_saque','amigoz_margem'];
insert into public.simulador_convenios(simulador,uf,convenio) values('aki_siape','BR','amigoz_13');
insert into public.simulador_tabelas(simulador,codigo,nome,produto,coeficiente,ordem) values
 ('aki_siape','30077','CC_CP_SIAPE_PQ_F11_CO_CCC','cartao_credito',0.043297241,1),
 ('aki_siape','30078','CC_CP_SIAPE_PQ_F12_CO_CCC','cartao_credito',0.042292776,2),
 ('aki_siape','30079','CC_CP_SIAPE_PQ_F13_CO_CCC','cartao_credito',0.041187994,3),
 ('aki_siape','30080','CC_CP_SIAPE_PQ_F14_CO_CCC','cartao_credito',0.040083341,4),
 ('aki_siape','30081','CC_CP_SIAPE_PQ_F15_CO_CCC','cartao_credito',0.039079231,5),
 ('aki_siape','30082','CC_CP_SIAPE_PQ_F16_CO_CCC','cartao_credito',0.037974818,6),
 ('aki_siape','35445','CB_CP_SIAPE_PQ_F16_CO_CCC','cartao_beneficio',0.038850608,7);

-- 3. Regra única: simulador ativo e (consulta Digi+ liberada ou convênio liberado).
-- p_convenio é o código do catálogo; convênio fora do catálogo não libera nada.
create function apoiarcred_private.simulador_liberado(p_simulador text,p_digimais boolean,p_convenio text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.simuladores s where s.codigo=p_simulador and s.ativo
  and ((coalesce(p_digimais,false) and s.consultas_digimais)
   or exists(select 1 from public.simulador_convenios c where c.simulador=s.codigo and c.convenio=nullif(p_convenio,''))));
$$;
revoke all on function apoiarcred_private.simulador_liberado(text,boolean,text) from public,anon;
grant execute on function apoiarcred_private.simulador_liberado(text,boolean,text) to authenticated;

-- 4. O que o painel precisa para decidir onde mostrar cada simulador.
create function public.simuladores_config()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('codigo',s.codigo,'nome',s.nome,'banco',s.banco,'tipo',s.tipo,
   'ativo',s.ativo,'consultas_digimais',s.consultas_digimais,
   'convenios',coalesce((select jsonb_agg(c.convenio order by c.uf,c.convenio) from public.simulador_convenios c where c.simulador=s.codigo),'[]'),
   'tabelas',coalesce((select jsonb_agg(jsonb_build_object('codigo',t.codigo,'nome',t.nome,'produto',t.produto,
     'coeficiente',t.coeficiente,'ativa',t.ativa) order by t.ordem,t.codigo) from public.simulador_tabelas t where t.simulador=s.codigo),'[]'))
  order by s.ordem,s.codigo),'[]')
 from public.simuladores s where auth.uid() is not null;
$$;
revoke all on function public.simuladores_config() from public,anon;
grant execute on function public.simuladores_config() to authenticated;

-- 5. Cálculo dos simuladores por coeficiente.
-- p_job_id: consulta Digi+ de origem (libera pelo simulador nas consultas Digi+); senão, p_convenio do catálogo.
create function public.simular_coeficientes(p_simulador text,p_produto text,p_parcela numeric,
 p_margem numeric default 0,p_saldo numeric default 0,p_job_id uuid default null,p_convenio text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare base numeric; sim public.simuladores; result jsonb; digimais boolean:=false;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 select * into sim from public.simuladores where codigo=p_simulador and tipo='coeficiente';
 if not found then raise exception 'Simulador não encontrado.';end if;
 if p_job_id is not null then
  -- Consulta Digi+ que a pessoa pode ver (empresa e escopo).
  select true into digimais from public.consulta_jobs j
  where j.id=p_job_id and j.tenant_id=apoiarcred_private.current_tenant()
   and (j.user_id=auth.uid() or apoiarcred_private.current_sees_company());
  if not coalesce(digimais,false) then raise exception 'Consulta não encontrada na sua conta.';end if;
 end if;
 if not apoiarcred_private.simulador_liberado(p_simulador,digimais,p_convenio) then
  raise exception 'O simulador % não está disponível para este cliente.',sim.nome;
 end if;
 if p_produto not in ('cartao_beneficio','cartao_credito') then raise exception 'Escolha Cartão Benefício ou Cartão Crédito.';end if;
 if p_parcela is null or p_parcela<=0 then raise exception 'Informe o valor da parcela.';end if;
 if coalesce(p_margem,0)<0 or coalesce(p_saldo,0)<0 then raise exception 'Margem e saldo devedor não podem ser negativos.';end if;
 base:=round(p_parcela,2)+round(coalesce(p_margem,0),2);
 select coalesce(jsonb_agg(jsonb_build_object('codigo',t.codigo,'nome',t.nome,'produto',t.produto,'coeficiente',t.coeficiente,
   'bruto',x.bruto,'liberado',x.bruto-round(coalesce(p_saldo,0),2),'saldo_maior',round(coalesce(p_saldo,0),2)>x.bruto)
   order by t.ordem,t.codigo),'[]')
 into result
 from public.simulador_tabelas t cross join lateral (select round(base/t.coeficiente,2) bruto) x
 where t.simulador=p_simulador and t.produto=p_produto and t.ativa;
 return jsonb_build_object('simulador',sim.codigo,'nome',sim.nome,'banco',sim.banco,'produto',p_produto,
  'parcela',round(p_parcela,2),'margem',round(coalesce(p_margem,0),2),'saldo',round(coalesce(p_saldo,0),2),'base',base,'tabelas',result);
end $$;
revoke all on function public.simular_coeficientes(text,text,numeric,numeric,numeric,uuid,text) from public,anon;
grant execute on function public.simular_coeficientes(text,text,numeric,numeric,numeric,uuid,text) to authenticated;

-- 6. Administração (equipe ApoiarCred).
create function public.admin_simulador_salvar(p_codigo text,p_ativo boolean,p_consultas_digimais boolean,p_convenios text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare unknown text;
begin
 if not apoiarcred_private.is_admin(auth.uid()) then raise insufficient_privilege;end if;
 if not exists(select 1 from public.simuladores where codigo=p_codigo) then raise exception 'Simulador não encontrado.';end if;
 select string_agg(x,', ') into unknown from unnest(coalesce(p_convenios,'{}')) x
  where not exists(select 1 from public.crm_catalogo_importacao c where c.codigo=x);
 if unknown is not null then raise exception 'Convênio fora do catálogo: %',unknown;end if;
 update public.simuladores set ativo=p_ativo,consultas_digimais=p_consultas_digimais,atualizado_em=now() where codigo=p_codigo;
 delete from public.simulador_convenios where simulador=p_codigo and not (convenio=any(coalesce(p_convenios,'{}')));
 insert into public.simulador_convenios(simulador,uf,convenio)
  select p_codigo,c.uf,c.codigo from public.crm_catalogo_importacao c where c.codigo=any(coalesce(p_convenios,'{}'))
 on conflict do nothing;
 return (select x from jsonb_array_elements(public.simuladores_config()) x where x->>'codigo'=p_codigo);
end $$;
create function public.admin_simulador_tabela_salvar(p_simulador text,p_codigo text,p_nome text,p_produto text,
 p_coeficiente numeric,p_ativa boolean default true,p_ordem integer default 0)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not apoiarcred_private.is_admin(auth.uid()) then raise insufficient_privilege;end if;
 if not exists(select 1 from public.simuladores where codigo=p_simulador and tipo='coeficiente') then
  raise exception 'Este simulador não usa tabelas de coeficiente.';end if;
 insert into public.simulador_tabelas(simulador,codigo,nome,produto,coeficiente,ativa,ordem)
 values(p_simulador,btrim(p_codigo),btrim(p_nome),p_produto,p_coeficiente,coalesce(p_ativa,true),coalesce(p_ordem,0))
 on conflict(simulador,codigo) do update set nome=excluded.nome,produto=excluded.produto,coeficiente=excluded.coeficiente,
  ativa=excluded.ativa,ordem=excluded.ordem,atualizado_em=now();
end $$;
create function public.admin_simulador_tabela_excluir(p_simulador text,p_codigo text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not apoiarcred_private.is_admin(auth.uid()) then raise insufficient_privilege;end if;
 delete from public.simulador_tabelas where simulador=p_simulador and codigo=p_codigo;
end $$;
revoke all on function public.admin_simulador_salvar(text,boolean,boolean,text[]),
 public.admin_simulador_tabela_salvar(text,text,text,text,numeric,boolean,integer),
 public.admin_simulador_tabela_excluir(text,text) from public,anon;
grant execute on function public.admin_simulador_salvar(text,boolean,boolean,text[]),
 public.admin_simulador_tabela_salvar(text,text,text,text,numeric,boolean,integer),
 public.admin_simulador_tabela_excluir(text,text) to authenticated;

-- 7. Amigoz passa a respeitar a mesma regra.
-- Simulação pelo convênio (ficha do CRM, consultas ConsigX): o convênio do catálogo precisa estar liberado.
-- Simulação a partir de uma consulta Digi+: o Amigoz precisa estar liberado nas consultas Digi+.
do $$
declare def text; guard text; at integer;
begin
 def:=pg_get_functiondef('public.amigoz_simulation_context(text,text,uuid)'::regprocedure);
 if position('simulador_liberado' in def)=0 then
  guard:=E'\n if nullif(p_convenio,'''') is not null and exists(select 1 from public.crm_catalogo_importacao c where c.codigo=p_convenio)\n  and not apoiarcred_private.simulador_liberado(''amigoz'',false,p_convenio) then\n  raise exception ''O simulador Amigoz não está disponível para este convênio.'';\n end if;\n if p_job_id is not null and not apoiarcred_private.simulador_liberado(''amigoz'',true,null) then\n  raise exception ''O simulador Amigoz não está disponível para as consultas Digi+.'';\n end if;';
  at:=position(E'\nbegin\n' in def);
  if at=0 then raise exception 'Início de amigoz_simulation_context não encontrado';end if;
  def:=substr(def,1,at+6)||guard||substr(def,at+7);
  execute def;
 end if;
 def:=pg_get_functiondef('public.simular_amigoz_price(uuid,integer,jsonb)'::regprocedure);
 if position('simulador_liberado' in def)=0 then
  guard:=E'\n if not apoiarcred_private.simulador_liberado(''amigoz'',true,null) then\n  raise exception ''O simulador Amigoz não está disponível para as consultas Digi+.'';\n end if;';
  at:=position(E'\nbegin\n' in def);
  if at=0 then raise exception 'Início de simular_amigoz_price não encontrado';end if;
  def:=substr(def,1,at+6)||guard||substr(def,at+7);
  execute def;
 end if;
end $$;

commit;
