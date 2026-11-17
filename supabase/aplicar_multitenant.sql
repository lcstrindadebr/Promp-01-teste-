-- ApoiarCred · aplicar o multi-tenant (etapas 3 a 6a) de uma vez.
-- Colar inteiro no Supabase → SQL Editor e clicar em Run. Se o editor avisar de operação
-- destrutiva (troca das políticas de acesso), confirme.
-- Tudo roda numa transação: qualquer erro, ou qualquer parceiro que mudaria de acesso, desfaz
-- tudo e o banco continua como estava. No fim aparece "MULTITENANT_OK".
-- Pré-requisito já aplicado: fila resiliente e fundação (empresas criadas).
begin;
set local lock_timeout='15s';

-- ===================== upgrade_tenants_access
-- Multi-tenant · etapa 3a: regras de acesso (RLS) e autorização pela empresa.
-- Aplicar depois de upgrade_tenants_foundation.sql, na mesma janela.
-- Com cada usuário numa empresa própria, o resultado visível é idêntico ao de antes;
-- a diferença aparece quando a empresa ganha outros membros (etapa 4).

-- 1. Empresa e escopo do usuário logado. Usados nas políticas como (select …),
-- o Postgres calcula uma vez por consulta, e não uma vez por linha.
create function apoiarcred_private.current_tenant()
returns uuid language sql stable security definer set search_path='' as $$
 select coalesce(nullif(auth.jwt()->>'tenant_id','')::uuid,apoiarcred_private.user_tenant(auth.uid()));
$$;
create function apoiarcred_private.current_sees_company()
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((auth.jwt()->>'tenant_scope')='empresa',
  auth.uid() is not null and apoiarcred_private.has_permission(auth.uid(),'dados.ver_empresa'));
$$;
create function apoiarcred_private.current_can(p_key text)
returns boolean language sql stable security definer set search_path='' as
$$ select auth.uid() is not null and apoiarcred_private.has_permission(auth.uid(),p_key) $$;
revoke all on function apoiarcred_private.current_tenant() from public,anon;
revoke all on function apoiarcred_private.current_sees_company() from public,anon;
revoke all on function apoiarcred_private.current_can(text) from public,anon;
grant execute on function apoiarcred_private.current_tenant(),apoiarcred_private.current_sees_company(),
 apoiarcred_private.current_can(text) to authenticated;

-- 2. Políticas: ver = mesma empresa e (ver a empresa ou ter criado); criar = em seu nome, na sua empresa;
-- alterar/excluir = o que pode ver e a permissão da ação.
do $$
declare r record;
begin
 for r in select schemaname,tablename,policyname from pg_policies
  where schemaname='public' and tablename in ('amigoz_coefficient_simulations','amigoz_comissoes','amigoz_comissoes_tabela',
   'amigoz_jobs','amigoz_simulacoes','consulta_jobs','consulta_lotes','consulta_tjba_historico','crm_cadastros',
   'crm_campanhas_reuso','crm_card_settings','crm_classificacoes','crm_dados_cliente','crm_etapas','crm_exportacoes',
   'crm_margens_vinculo','crm_movimentacoes','crm_oportunidades','crm_vinculos','painel_exclusoes','tjba_jobs','tjba_lotes')
 loop
  execute format('drop policy %I on %I.%I',r.policyname,r.schemaname,r.tablename);
 end loop;
end $$;

do $$
declare t text;
begin
 -- Leitura em todas as tabelas de dados da empresa.
 foreach t in array array['amigoz_coefficient_simulations','amigoz_comissoes','amigoz_comissoes_tabela','amigoz_jobs',
  'amigoz_simulacoes','consulta_jobs','consulta_lotes','consulta_tjba_historico','crm_cadastros','crm_campanhas_reuso',
  'crm_card_settings','crm_classificacoes','crm_dados_cliente','crm_etapas','crm_exportacoes','crm_margens_vinculo',
  'crm_movimentacoes','crm_oportunidades','crm_vinculos','painel_exclusoes','tjba_jobs','tjba_lotes'] loop
  execute format($p$create policy tenant_read on public.%I for select to authenticated using (
   tenant_id=(select apoiarcred_private.current_tenant())
   and (user_id=(select auth.uid()) or (select apoiarcred_private.current_sees_company())))$p$,t);
 end loop;
 -- Configurações e simulações próprias: cada usuário altera as suas.
 foreach t in array array['amigoz_coefficient_simulations','amigoz_comissoes','crm_card_settings'] loop
  execute format($p$create policy tenant_own_write on public.%I for all to authenticated
   using (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant()))
   with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant()))$p$,t);
 end loop;
 -- Exclusões diretas pelo painel exigem dados.excluir.
 foreach t in array array['consulta_jobs','consulta_lotes','tjba_jobs','tjba_lotes'] loop
  execute format($p$create policy tenant_delete on public.%I for delete to authenticated using (
   tenant_id=(select apoiarcred_private.current_tenant())
   and (user_id=(select auth.uid()) or (select apoiarcred_private.current_sees_company()))
   and (select apoiarcred_private.current_can('dados.excluir')))$p$,t);
 end loop;
end $$;

-- Inserções diretas: em seu nome, na sua empresa, em lote/oportunidade que você pode ver.
create policy tenant_insert on public.consulta_lotes for insert to authenticated
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant()));
create policy tenant_insert on public.tjba_lotes for insert to authenticated
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant()));
create policy tenant_insert on public.consulta_jobs for insert to authenticated
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant())
  and exists(select 1 from public.consulta_lotes l where l.id=consulta_jobs.lote_id and l.user_id=(select auth.uid())));
create policy tenant_insert on public.tjba_jobs for insert to authenticated
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant())
  and exists(select 1 from public.tjba_lotes l where l.id=tjba_jobs.lote_id and l.user_id=(select auth.uid())));
create policy tenant_insert on public.amigoz_simulacoes for insert to authenticated
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant())
  and exists(select 1 from public.consulta_jobs j where j.id=amigoz_simulacoes.job_id
   and j.tenant_id=(select apoiarcred_private.current_tenant())
   and (j.user_id=(select auth.uid()) or (select apoiarcred_private.current_sees_company()))));
create policy tenant_own_update on public.amigoz_simulacoes for update to authenticated
 using (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant()))
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant()));
create policy tenant_own_delete on public.amigoz_simulacoes for delete to authenticated
 using (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant()));
create policy tenant_insert on public.crm_exportacoes for insert to authenticated
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant())
  and (select apoiarcred_private.current_can('clientes.exportar'))
  and exists(select 1 from public.crm_oportunidades o where o.id=crm_exportacoes.oportunidade_referencia
   and o.tenant_id=(select apoiarcred_private.current_tenant())
   and (o.user_id=(select auth.uid()) or (select apoiarcred_private.current_sees_company()))));
create policy tenant_insert on public.crm_oportunidades for insert to authenticated
 with check (user_id=(select auth.uid()) and tenant_id=(select apoiarcred_private.current_tenant())
  and exists(select 1 from public.crm_clientes c where c.user_id=crm_oportunidades.user_id and c.cpf=crm_oportunidades.cpf)
  and (convenio='' or exists(select 1 from public.crm_vinculos c where c.user_id=crm_oportunidades.user_id
   and c.cpf=crm_oportunidades.cpf and c.convenio=crm_oportunidades.convenio)));
create policy tenant_update on public.crm_oportunidades for update to authenticated
 using (tenant_id=(select apoiarcred_private.current_tenant())
  and (user_id=(select auth.uid()) or (select apoiarcred_private.current_sees_company()))
  and (select apoiarcred_private.current_can('oportunidade.mover')))
 with check (tenant_id=(select apoiarcred_private.current_tenant()));

-- 3. Autorização das consultas pela empresa (substitui perfil + partner_permissions).
create function apoiarcred_private.consult_key(p_service text,p_mode text)
returns text language sql immutable as $$
 select 'consulta.'||case p_service when 'digimais_saldo_parcela' then 'digimais' when 'tjba_margem' then 'consigx'
  when 'amigoz' then 'amigoz' end||'.'||case p_mode when 'campanha' then 'campanha' else 'individual' end;
$$;

create or replace function apoiarcred_private.check_partner_access(uid uuid,service_id text,mode text,consume boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare company apoiarcred_private.tenants; member apoiarcred_private.tenant_members; key text;
begin
 select * into member from apoiarcred_private.tenant_members where user_id=uid;
 select * into company from apoiarcred_private.tenants where id=member.tenant_id;
 if member.user_id is null or not member.active or not company.active then
  raise insufficient_privilege using message='Conta sem acesso ativo. Solicite liberação ao administrador.';
 end if;
 if company.trial_until<apoiarcred_private.today_sp() then
  raise insufficient_privilege using message='Seu período de teste terminou. Solicite a renovação ao administrador.';
 end if;
 if mode not in ('individual','campanha') then raise insufficient_privilege;end if;
 key:=apoiarcred_private.consult_key(service_id,mode);
 if key is null or not apoiarcred_private.has_permission(uid,key) then
  raise insufficient_privilege using message=case mode when 'campanha'
   then 'Campanhas não estão habilitadas para este tipo de higienização.'
   else 'Consultas individuais não estão habilitadas para este tipo de higienização.' end;
 end if;
 if consume then perform apoiarcred_private.tenant_consume(uid,key,1);end if;
end $$;

create or replace function public.authorize_amigoz(p_actor uuid,p_consume boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 begin
  perform apoiarcred_private.check_partner_access(p_actor,'amigoz','individual',p_consume);
 exception when insufficient_privilege then
  raise insufficient_privilege using message='Acesso Amigoz não liberado.';
 end;
 return true;
end $$;
revoke all on function public.authorize_amigoz(uuid,boolean) from public,anon,authenticated;
grant execute on function public.authorize_amigoz(uuid,boolean) to service_role;

-- Permissão configurada, sem olhar se a conta está ativa ou no teste: mostrada no painel
-- mesmo com a conta suspensa, e usada pela integração (o histórico continua legível após o teste).
create function apoiarcred_private.configured_permission(p_user uuid,p_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((
  select exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=m.tenant_id and g.permission_key=p_key)
   and coalesce((select o.allow from apoiarcred_private.member_overrides o
                 where o.tenant_id=m.tenant_id and o.user_id=m.user_id and o.permission_key=p_key),
                exists(select 1 from apoiarcred_private.role_permissions rp where rp.role_id=m.role_id and rp.permission_key=p_key))
  from apoiarcred_private.tenant_members m where m.user_id=p_user),false);
$$;
revoke all on function apoiarcred_private.configured_permission(uuid,text) from public,anon,authenticated;

-- Integração: conta e empresa ativas; criar consultas é barrado depois por check_partner_access.
create or replace function apoiarcred_private.can_integrate(uid uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select apoiarcred_private.configured_permission(uid,'integracoes') and exists(
  select 1 from apoiarcred_private.tenant_members m join apoiarcred_private.tenants t on t.id=m.tenant_id
  where m.user_id=uid and m.active and t.active);
$$;

-- Equipe ApoiarCred: tabela própria (o papel antigo continua valendo durante a transição).
create or replace function apoiarcred_private.is_admin(uid uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from apoiarcred_private.platform_admins a where a.user_id=uid)
  or exists(select 1 from apoiarcred_private.user_profiles p where p.user_id=uid and p.role='admin' and p.active);
$$;

-- 4. O que o painel recebe (mesmo formato de antes, calculado pela empresa).
-- A cota da empresa vale para todos os serviços, por isso aparece como cota compartilhada.
create or replace function apoiarcred_private.access_for(uid uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,
  'role',case when apoiarcred_private.is_admin(uid) then 'admin' else 'partner' end,
  'name',coalesce(p.name,t.name),'active',coalesce(t.active and m.active,false),
  'allow_amigoz',apoiarcred_private.configured_permission(uid,'consulta.amigoz.individual'),
  'allow_integrations',apoiarcred_private.configured_permission(uid,'integracoes'),
  'trial_until',t.trial_until,
  'trial_expired',coalesce(t.trial_until<apoiarcred_private.today_sp(),false),
  'trial_days_left',case when t.trial_until is not null then greatest(0,t.trial_until-apoiarcred_private.today_sp()+1) end,
  'shared_quota',true,'daily_limit',t.daily_limit,
  'remaining',case when t.daily_limit is not null then greatest(0,t.daily_limit-coalesce(u.used,0)) end,
  'day',apoiarcred_private.today_sp(),'timezone','America/Sao_Paulo',
  'services',(select jsonb_agg(jsonb_build_object('id',s,
    'enabled',apoiarcred_private.configured_permission(uid,apoiarcred_private.consult_key(s,'individual'))
      or apoiarcred_private.configured_permission(uid,apoiarcred_private.consult_key(s,'campanha')),
    'allow_individual',apoiarcred_private.configured_permission(uid,apoiarcred_private.consult_key(s,'individual')),
    'allow_campaign',apoiarcred_private.configured_permission(uid,apoiarcred_private.consult_key(s,'campanha')),
    'daily_limit',null,'used',coalesce(u.used,0),'remaining',null) order by s)
   from unnest(array['digimais_saldo_parcela','tjba_margem']) s),
  'tenant',public.tenant_context())
 from (select 1) seed
 left join apoiarcred_private.tenant_members m on m.user_id=uid
 left join apoiarcred_private.tenants t on t.id=m.tenant_id
 left join apoiarcred_private.user_profiles p on p.user_id=uid
 left join apoiarcred_private.tenant_daily_usage u on u.tenant_id=t.id and u.day=apoiarcred_private.today_sp();
$$;

-- ===================== upgrade_tenants_crm
-- Multi-tenant · etapa 3b: funil do CRM por empresa.
-- Etapas e configuração dos cartões passam a ser da empresa: todos os membros usam o mesmo
-- funil, e quem tem funil.configurar edita. Quadro, exportação e ações em lote enxergam o que
-- o usuário pode ver (a empresa ou só o que criou). Aplicar depois de upgrade_tenants_access.sql.
-- As funções muito longas recebem só a troca do filtro (conta → empresa); cada troca é conferida.

-- 1. Etapas da empresa: unicidade e vínculo das oportunidades pela empresa.
alter table public.crm_oportunidades drop constraint crm_oportunidades_etapa_conta_fk;
drop index public.crm_etapas_inicial;
drop index public.crm_etapas_exportacao;
alter table public.crm_etapas drop constraint crm_etapas_user_id_codigo_key;
alter table public.crm_etapas add constraint crm_etapas_tenant_id_key unique(tenant_id,id);
alter table public.crm_etapas add constraint crm_etapas_tenant_codigo_key unique(tenant_id,codigo);
create unique index crm_etapas_inicial on public.crm_etapas(tenant_id) where inicial;
create unique index crm_etapas_exportacao on public.crm_etapas(tenant_id) where destino_exportacao;
alter table public.crm_oportunidades add constraint crm_oportunidades_etapa_empresa_fk
 foreign key(tenant_id,etapa_id) references public.crm_etapas(tenant_id,id);
create unique index crm_card_settings_tenant_key on public.crm_card_settings(tenant_id);

-- Todos os membros leem o funil e a configuração da empresa; só funil.configurar altera.
drop policy tenant_read on public.crm_etapas;
create policy tenant_read on public.crm_etapas for select to authenticated
 using (tenant_id=(select apoiarcred_private.current_tenant()));
drop policy tenant_read on public.crm_card_settings;
drop policy tenant_own_write on public.crm_card_settings;
create policy tenant_read on public.crm_card_settings for select to authenticated
 using (tenant_id=(select apoiarcred_private.current_tenant()));
create policy tenant_config_write on public.crm_card_settings for all to authenticated
 using (tenant_id=(select apoiarcred_private.current_tenant()) and (select apoiarcred_private.current_can('funil.configurar')))
 with check (tenant_id=(select apoiarcred_private.current_tenant()) and (select apoiarcred_private.current_can('funil.configurar')));

-- 2. Funil padrão criado uma vez por empresa.
create or replace function apoiarcred_private.crm_semear_etapas(uid uuid)
returns void language sql security definer set search_path='' as $$
 insert into public.crm_etapas(user_id,codigo,nome,posicao,tipo,inicial,destino_exportacao)
 select uid,codigo,nome,posicao,tipo,codigo='novo',codigo='exportada'
 from (values ('novo','Novo',10,'aberta'),('exportada','Exportadas',20,'aberta'),
 ('contato','Em contato',30,'aberta'),('simulacao','Simulação enviada',40,'aberta'),
 ('negociacao','Em negociação',50,'aberta'),('ganho','Ganho',60,'ganho'),('perdido','Perdido',70,'perdido'))
 defaults(codigo,nome,posicao,tipo)
 where apoiarcred_private.user_tenant(uid) is not null
  and not exists(select 1 from public.crm_etapas where tenant_id=apoiarcred_private.user_tenant(uid))
 on conflict do nothing;
$$;

create or replace function public.crm_listar_etapas()
returns setof public.crm_etapas language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); company uuid=apoiarcred_private.user_tenant(auth.uid());
begin
 if uid is null or company is null then raise insufficient_privilege;end if;
 perform apoiarcred_private.crm_semear_etapas(uid);
 return query select * from public.crm_etapas e where e.tenant_id=company order by e.posicao,e.id;
end $$;

create or replace function public.crm_salvar_etapa(p_id uuid,p_input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); company uuid=apoiarcred_private.user_tenant(auth.uid());
 e public.crm_etapas; destino uuid; novo_nome text; nova_posicao integer; arquivar boolean;
begin
 if company is null or not (apoiarcred_private.has_permission(uid,'funil.configurar') or apoiarcred_private.is_admin(uid)) then
  raise insufficient_privilege;end if;
 perform pg_advisory_xact_lock(hashtextextended('crm_etapas:'||company::text,0));
 perform apoiarcred_private.crm_semear_etapas(uid);
 if p_id is not null then
  select * into e from public.crm_etapas where tenant_id=company and id=p_id for update;
  if not found then return null;end if;
 end if;
 novo_nome=btrim(coalesce(p_input->>'nome',e.nome));
 nova_posicao=coalesce((p_input->>'posicao')::integer,e.posicao,(select max(s.posicao)+10 from public.crm_etapas s where s.tenant_id=company));
 arquivar=coalesce((p_input->>'arquivada')::boolean,e.arquivada,false);
 if coalesce(length(novo_nome),0) not between 1 and 100 or nova_posicao<0 then raise exception using errcode='22023',message='Informe nome e posição válidos.';end if;
 if arquivar and (coalesce(e.inicial,false) or coalesce(e.destino_exportacao,false)
  or coalesce((p_input->>'inicial')::boolean,false) or coalesce((p_input->>'destino_exportacao')::boolean,false)) then
  raise exception using errcode='22023',message='Defina outra etapa inicial ou de exportação antes de arquivar esta.';
 end if;
 if p_id is null then
  p_id=gen_random_uuid();
  insert into public.crm_etapas(id,user_id,codigo,nome,posicao,arquivada) values(p_id,uid,p_id::text,novo_nome,nova_posicao,arquivar) returning * into e;
 elsif arquivar and not e.arquivada then
  destino=(p_input->>'destino_id')::uuid;
  if exists(select 1 from public.crm_oportunidades where tenant_id=company and etapa_id=e.id) then
   if destino is null or destino=e.id or not exists(select 1 from public.crm_etapas where tenant_id=company and id=destino and not arquivada)
    then raise exception using errcode='22023',message='Escolha uma etapa ativa de destino para os cartões.';
   end if;
   update public.crm_oportunidades set etapa_id=destino where tenant_id=company and etapa_id=e.id;
  end if;
 end if;
 if coalesce((p_input->>'inicial')::boolean,false) then update public.crm_etapas set inicial=false where tenant_id=company and inicial and id<>p_id;end if;
 if coalesce((p_input->>'destino_exportacao')::boolean,false) then update public.crm_etapas set destino_exportacao=false where tenant_id=company and destino_exportacao and id<>p_id;end if;
 update public.crm_etapas set nome=novo_nome,posicao=nova_posicao,arquivada=arquivar,
  inicial=inicial or coalesce((p_input->>'inicial')::boolean,false),
  destino_exportacao=destino_exportacao or coalesce((p_input->>'destino_exportacao')::boolean,false)
 where tenant_id=company and id=p_id returning * into e;
 return to_jsonb(e)-'user_id'-'tenant_id';
end $$;

-- 3. Mover cartões: o que o usuário vê, com oportunidade.mover.
create or replace function public.crm_mover_etapa(p_id uuid,p_etapa_id uuid,p_etapa_original_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); o public.crm_oportunidades;
begin
 if uid is null then raise insufficient_privilege;end if;
 if p_etapa_id is null or p_etapa_original_id is null then raise exception using errcode='22023',message='Informe os IDs das etapas de origem e destino.';end if;
 select * into o from public.crm_oportunidades where id=p_id and apoiarcred_private.can_see(tenant_id,user_id) for update;
 if not found then return null;end if;
 if not apoiarcred_private.has_permission(uid,'oportunidade.mover') then raise insufficient_privilege;end if;
 if o.etapa_id<>p_etapa_original_id then
  return jsonb_build_object('conflito',true,'id',o.id,'etapa_id',o.etapa_id,'etapa',o.etapa);
 end if;
 if o.etapa_id<>p_etapa_id then
  update public.crm_oportunidades set etapa_id=p_etapa_id where id=p_id returning * into o;
 end if;
 return jsonb_build_object('id',o.id,'etapa_id',o.etapa_id,'etapa',o.etapa);
end $$;

create or replace function public.crm_acao_lote(p_itens jsonb,p_destino uuid default null,p_excluir boolean default false)
returns integer language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); company uuid=apoiarcred_private.user_tenant(auth.uid()); total integer; validos integer; afetados integer;
begin
 if uid is null or not coalesce((apoiarcred_private.access_for(uid)->>'active')::boolean,false) then raise insufficient_privilege;end if;
 if (p_destino is null and not p_excluir) or (p_destino is not null and p_excluir)
  or jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens)<1 then
  raise exception using errcode='22023',message='Selecione as oportunidades e uma ação.';
 end if;
 if not apoiarcred_private.has_permission(uid,case when p_excluir then 'dados.excluir' else 'oportunidade.mover' end) then
  raise insufficient_privilege;end if;
 total=jsonb_array_length(p_itens);
 select count(*) into validos from (
  select o.id from public.crm_oportunidades o join jsonb_to_recordset(p_itens) i(id uuid,etapa_id uuid)
   on i.id=o.id and i.etapa_id=o.etapa_id
   where o.tenant_id=company and apoiarcred_private.can_see(o.tenant_id,o.user_id) order by o.id for update of o
 ) locked;
 if validos<>total or (select count(distinct x->>'id') from jsonb_array_elements(p_itens) x)<>total then
  raise exception using errcode='PT409',message='A seleção mudou. Atualize o quadro e selecione os cartões novamente.';
 end if;
 if p_excluir then
  delete from public.crm_oportunidades o using jsonb_to_recordset(p_itens) i(id uuid)
   where o.tenant_id=company and o.id=i.id;
 else
  if not exists(select 1 from public.crm_etapas where tenant_id=company and id=p_destino and not arquivada) then
   raise exception using errcode='22023',message='Etapa de destino indisponível.';
  end if;
  update public.crm_oportunidades o set etapa_id=p_destino from jsonb_to_recordset(p_itens) i(id uuid)
   where o.tenant_id=company and o.id=i.id and o.etapa_id<>p_destino;
 end if;
 get diagnostics afetados=row_count;
 return afetados;
end $$;

-- 4. Funções de leitura (rodam com as permissões do usuário: as políticas já limitam à empresa e
-- ao que cada um vê, e o cartão aponta para a etapa pelo id) e as
-- da API: troca do filtro de conta pelo da empresa, conferindo cada substituição.
create function apoiarcred_private.patch_function(p_fn regprocedure,p_pairs text[])
returns void language plpgsql set search_path='' as $$
declare def text=pg_get_functiondef(p_fn); i integer;
begin
 for i in 1..array_length(p_pairs,1) by 2 loop
  if position(p_pairs[i] in def)=0 then raise exception 'Trecho não encontrado em %: %',p_fn,p_pairs[i];end if;
  def=replace(def,p_pairs[i],p_pairs[i+1]);
 end loop;
 execute def;
end $$;

select apoiarcred_private.patch_function('apoiarcred_private.crm_sincronizar_etapa()',array[
 'from public.crm_etapas where user_id=new.user_id','from public.crm_etapas where tenant_id=new.tenant_id',
 'from public.crm_etapas where user_id=old.user_id','from public.crm_etapas where tenant_id=old.tenant_id']);
select apoiarcred_private.patch_function('apoiarcred_private.crm_validate_customization()',array[
 'from public.crm_card_settings where user_id=new.user_id','from public.crm_card_settings where tenant_id=new.tenant_id']);
select apoiarcred_private.patch_function('public.crm_kanban(text,text,text,uuid,integer)',array[
 'where o.user_id=auth.uid()','where o.tenant_id=(select apoiarcred_private.current_tenant())',
 'c.id=page.id and c.user_id=e.user_id','c.id=page.id',
 'where e.user_id=auth.uid()','where e.tenant_id=(select apoiarcred_private.current_tenant())']);
select apoiarcred_private.patch_function('public.crm_listar_exportacao(text,text,text[],text,uuid,boolean)',array[
 'where o.user_id=auth.uid()','where (select apoiarcred_private.current_can(''clientes.exportar''))',
 'e.user_id=o.user_id and ','']);
select apoiarcred_private.patch_function('public.crm_export_opportunities(text,text,text[],text,uuid)',array[
 'where o.user_id=auth.uid()','where (select apoiarcred_private.current_can(''clientes.exportar''))',
 'e.user_id=o.user_id and ','']);
select apoiarcred_private.patch_function('public.crm_marcar_exportadas(jsonb)',array[
 'from public.crm_etapas where user_id=auth.uid() and destino_exportacao','from public.crm_etapas where tenant_id=(select apoiarcred_private.current_tenant()) and destino_exportacao',
 'o.user_id=auth.uid()','o.tenant_id=(select apoiarcred_private.current_tenant())',
 'e.user_id=o.user_id','e.tenant_id=o.tenant_id']);
select apoiarcred_private.patch_function('apoiarcred_private.crm_cliente_perfil(uuid,text,uuid)',array[
 'e.user_id=o.user_id','e.tenant_id=o.tenant_id']);
select apoiarcred_private.patch_function('apoiarcred_private.api_route(uuid,text,text,jsonb)',array[
 'from public.crm_etapas where user_id=uid','from public.crm_etapas where tenant_id=apoiarcred_private.user_tenant(uid)']);
select apoiarcred_private.patch_function('apoiarcred_private.api_route_oportunidades(uuid,text,text,jsonb)',array[
 'from public.crm_etapas where user_id=uid','from public.crm_etapas where tenant_id=apoiarcred_private.user_tenant(uid)']);
-- O cartão mostra a etapa da empresa (antes, a etapa precisava ser do mesmo usuário do cartão).
do $$
declare def text=pg_get_viewdef('public.crm_opportunity_cards'::regclass);
begin
 if position('(e.user_id = o.user_id)' in def)=0 or position('(destino.user_id = m.user_id)' in def)=0 then
  raise exception 'crm_opportunity_cards mudou; revise a migração';end if;
 def=replace(replace(def,'(e.user_id = o.user_id)','(e.tenant_id = o.tenant_id)'),'(destino.user_id = m.user_id)','(destino.tenant_id = m.tenant_id)');
 execute 'create or replace view public.crm_opportunity_cards with (security_invoker=true) as '||def;
end $$;
drop function apoiarcred_private.patch_function(regprocedure,text[]);
-- A API (service_role) resolve a empresa do dono do token.
grant execute on function apoiarcred_private.user_tenant(uuid) to service_role;

-- ===================== upgrade_tenants_users
-- Multi-tenant · etapa 4: usuários da empresa.
-- Quem tem usuarios.gerenciar cria usuários com e-mail e senha provisória (a conta no Auth é
-- criada pela API da VPS), escolhe o papel e ajusta permissões dentro do que a empresa contratou.
-- O usuário troca a senha no primeiro acesso. Aplicar depois de upgrade_tenants_crm.sql.

alter table apoiarcred_private.tenant_members
 add column name text check(name is null or length(btrim(name)) between 1 and 160),
 add column email text check(email is null or length(email)<=254),
 add column must_change_password boolean not null default false;
update apoiarcred_private.tenant_members m set name=p.name,email=p.email
 from apoiarcred_private.user_profiles p where p.user_id=m.user_id;

-- Membro desativado deixa de ver os dados da empresa na hora (sem esperar o token vencer).
create or replace function apoiarcred_private.current_tenant()
returns uuid language sql stable security definer set search_path='' as
$$ select tenant_id from apoiarcred_private.tenant_members where user_id=auth.uid() and active $$;

-- 1. Painel: nome, papel e aviso de troca de senha.
create or replace function public.tenant_context()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'tenant_id',t.id,'tenant_name',t.name,'role',r.code,'role_name',r.name,
  'active',t.active and m.active,'trial_until',t.trial_until,
  'daily_limit',t.daily_limit,
  'used_today',coalesce((select u.used from apoiarcred_private.tenant_daily_usage u where u.tenant_id=t.id and u.day=apoiarcred_private.today_sp()),0),
  'platform_admin',exists(select 1 from apoiarcred_private.platform_admins a where a.user_id=m.user_id),
  'owner',t.legacy_owner_id=m.user_id,
  'must_change_password',m.must_change_password,
  'permissions',coalesce((select jsonb_agg(e.permission_key order by e.permission_key)
    from apoiarcred_private.effective_permissions e where e.user_id=m.user_id),'[]'))
 from apoiarcred_private.tenant_members m
 join apoiarcred_private.tenants t on t.id=m.tenant_id
 join apoiarcred_private.tenant_roles r on r.id=m.role_id
 where m.user_id=auth.uid();
$$;

do $$
declare def text=pg_get_functiondef('apoiarcred_private.access_for(uuid)'::regprocedure);
begin
 if position('''name'',coalesce(p.name,t.name)' in def)=0 or position('''tenant'',public.tenant_context())' in def)=0 then
  raise exception 'access_for mudou; revise a migração';end if;
 def=replace(def,'''name'',coalesce(p.name,t.name)','''name'',coalesce(p.name,m.name,t.name)');
 def=replace(def,'''tenant'',public.tenant_context())',
  '''tenant'',public.tenant_context(),''must_change_password'',coalesce(m.must_change_password,false))');
 execute def;
end $$;

-- 2. Gestão de usuários (chamada pela API da VPS com a sessão de quem administra).
create function apoiarcred_private.tenant_member_json(p_user uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',m.user_id,
  'name',coalesce(m.name,p.name,u.email),'email',coalesce(m.email,p.email,u.email),
  'role',r.code,'role_name',r.name,'active',m.active,'must_change_password',m.must_change_password,
  'owner',t.legacy_owner_id=m.user_id,'created_at',m.created_at,
  'overrides',coalesce((select jsonb_object_agg(o.permission_key,o.allow) from apoiarcred_private.member_overrides o
    where o.tenant_id=m.tenant_id and o.user_id=m.user_id),'{}'),
  'permissions',coalesce((select jsonb_agg(e.permission_key order by e.permission_key)
    from apoiarcred_private.effective_permissions e where e.user_id=m.user_id),'[]'))
 from apoiarcred_private.tenant_members m
 join apoiarcred_private.tenants t on t.id=m.tenant_id
 join apoiarcred_private.tenant_roles r on r.id=m.role_id
 left join apoiarcred_private.user_profiles p on p.user_id=m.user_id
 left join auth.users u on u.id=m.user_id
 where m.user_id=p_user;
$$;

create function public.tenant_users_manage(p_actor uuid,p_action text,p_input jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor apoiarcred_private.tenant_members; actor_role text; company apoiarcred_private.tenants;
 target apoiarcred_private.tenant_members; target_role text; new_role apoiarcred_private.tenant_roles;
 uid uuid; item record; result jsonb;
begin
 select * into actor from apoiarcred_private.tenant_members where user_id=p_actor;
 if actor.user_id is null or not actor.active or not apoiarcred_private.has_permission(p_actor,'usuarios.gerenciar') then
  raise insufficient_privilege using message='Apenas quem gerencia usuários da empresa pode fazer isso.';
 end if;
 select * into company from apoiarcred_private.tenants where id=actor.tenant_id;
 select code into actor_role from apoiarcred_private.tenant_roles where id=actor.role_id;

 if p_action='check' then
  return jsonb_build_object('tenant_id',company.id,'tenant_name',company.name,'actor_role',actor_role,
   'roles',(select jsonb_agg(jsonb_build_object('code',r.code,'name',r.name,
     'permissions',coalesce((select jsonb_agg(rp.permission_key order by rp.permission_key) from apoiarcred_private.role_permissions rp
      join apoiarcred_private.tenant_grants g on g.tenant_id=r.tenant_id and g.permission_key=rp.permission_key
      where rp.role_id=r.id),'[]'))
     order by array_position(array['administrador','gestor','operador','leitura'],r.code))
    from apoiarcred_private.tenant_roles r where r.tenant_id=company.id),
   'catalog',(select jsonb_agg(jsonb_build_object('key',p.key,'description',p.description) order by p.service nulls last,p.key)
    from apoiarcred_private.permissions p join apoiarcred_private.tenant_grants g on g.permission_key=p.key and g.tenant_id=company.id));
 end if;

 if p_action='list' then
  return coalesce((select jsonb_agg(apoiarcred_private.tenant_member_json(m.user_id) order by m.active desc,lower(coalesce(m.name,m.email,'')))
   from apoiarcred_private.tenant_members m where m.tenant_id=company.id),'[]');
 end if;

 if p_action not in ('create','update','reset_password') then raise exception using errcode='22023',message='Ação inválida.';end if;
 uid:=(p_input->>'user_id')::uuid;
 if uid is null then raise exception using errcode='22023',message='Usuário não informado.';end if;

 if p_action='create' then
  if exists(select 1 from apoiarcred_private.tenant_members where user_id=uid) then
   raise exception using errcode='23505',message='Este usuário já pertence a uma empresa.';end if;
  if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 then raise exception using errcode='22023',message='Informe o nome do usuário.';end if;
  select * into new_role from apoiarcred_private.tenant_roles where tenant_id=company.id and code=p_input->>'role';
  if new_role.id is null then raise exception using errcode='22023',message='Papel inválido.';end if;
  if new_role.code='administrador' and actor_role<>'administrador' then
   raise insufficient_privilege using message='Apenas administradores criam outros administradores.';end if;
  insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id,name,email,must_change_password)
   values(company.id,uid,new_role.id,btrim(p_input->>'name'),lower(btrim(p_input->>'email')),true);
 else
  select * into target from apoiarcred_private.tenant_members where user_id=uid and tenant_id=company.id for update;
  if target.user_id is null then raise exception using errcode='P0002',message='Usuário não encontrado nesta empresa.';end if;
  select code into target_role from apoiarcred_private.tenant_roles where id=target.role_id;
  if target_role='administrador' and actor_role<>'administrador' then
   raise insufficient_privilege using message='Apenas administradores alteram outros administradores.';end if;
  if uid=p_actor then raise insufficient_privilege using message='Use a sua conta para trocar a sua senha; papel e acesso são alterados por outro administrador.';end if;
 end if;

 if p_action='reset_password' then
  update apoiarcred_private.tenant_members set must_change_password=true where user_id=uid;
  insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action) values(company.id,p_actor,uid,'usuario.senha_provisoria');
  return apoiarcred_private.tenant_member_json(uid);
 end if;

 if p_action='update' then
  if p_input ? 'name' then
   if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 then raise exception using errcode='22023',message='Informe o nome do usuário.';end if;
   update apoiarcred_private.tenant_members set name=btrim(p_input->>'name') where user_id=uid;
  end if;
  if (p_input ? 'role' and p_input->>'role' is distinct from target_role) or (p_input ? 'active' and (p_input->>'active')::boolean is distinct from target.active) then
   if company.legacy_owner_id=uid then
    raise insufficient_privilege using message='O responsável pela empresa não pode ser desativado nem mudar de papel.';end if;
  end if;
  if p_input ? 'role' then
   select * into new_role from apoiarcred_private.tenant_roles where tenant_id=company.id and code=p_input->>'role';
   if new_role.id is null then raise exception using errcode='22023',message='Papel inválido.';end if;
   if new_role.code='administrador' and actor_role<>'administrador' then
    raise insufficient_privilege using message='Apenas administradores criam outros administradores.';end if;
   update apoiarcred_private.tenant_members set role_id=new_role.id where user_id=uid;
  end if;
  if p_input ? 'active' then
   if jsonb_typeof(p_input->'active')<>'boolean' then raise exception using errcode='22023',message='Situação inválida.';end if;
   update apoiarcred_private.tenant_members set active=(p_input->>'active')::boolean where user_id=uid;
  end if;
 end if;

 -- Ajustes por usuário: substituem os anteriores; só dentro do que a empresa contratou.
 if p_input ? 'overrides' then
  if jsonb_typeof(p_input->'overrides')<>'object' then raise exception using errcode='22023',message='Permissões inválidas.';end if;
  for item in select key,value from jsonb_each(p_input->'overrides') loop
   if jsonb_typeof(item.value)<>'boolean' or not exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=company.id and g.permission_key=item.key) then
    raise exception using errcode='22023',message='Permissão fora do que a empresa contratou: '||item.key;end if;
   if item.key='usuarios.gerenciar' and item.value='true'::jsonb and actor_role<>'administrador' then
    raise insufficient_privilege using message='Apenas administradores liberam a gestão de usuários.';end if;
  end loop;
  delete from apoiarcred_private.member_overrides where tenant_id=company.id and user_id=uid;
  insert into apoiarcred_private.member_overrides(tenant_id,user_id,permission_key,allow)
   select company.id,uid,key,value::boolean from jsonb_each_text(p_input->'overrides');
 end if;

 if not exists(select 1 from apoiarcred_private.tenant_members m join apoiarcred_private.tenant_roles r on r.id=m.role_id
  where m.tenant_id=company.id and m.active and r.code='administrador') then
  raise exception using errcode='22023',message='A empresa precisa de pelo menos um administrador ativo.';end if;

 result:=apoiarcred_private.tenant_member_json(uid);
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(company.id,p_actor,uid,'usuario.'||case p_action when 'create' then 'criado' else 'alterado' end,
   jsonb_build_object('role',result->>'role','active',result->'active','overrides',result->'overrides'));
 return result;
end $$;
revoke all on function public.tenant_users_manage(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.tenant_users_manage(uuid,text,jsonb) to service_role;

-- 3. Troca de senha concluída (a API da VPS só chama depois de o Auth confirmar a nova senha).
create function public.tenant_password_changed(p_actor uuid)
returns void language sql security definer set search_path='' as
$$ update apoiarcred_private.tenant_members set must_change_password=false where user_id=p_actor and must_change_password $$;
revoke all on function public.tenant_password_changed(uuid) from public,anon,authenticated;
grant execute on function public.tenant_password_changed(uuid) to service_role;

-- ===================== upgrade_tenants_resources
-- Multi-tenant · etapa 5: recursos da empresa.
-- • Acesso ConsigX: um por empresa, cadastrado por quem tem acesso.portais e usado nas consultas
--   de todos os membros.
-- • Digi+ pela API: liberação, modo, pausa e limite de execuções valem para a empresa.
-- • Integrações: tokens e webhooks da empresa, geridos por quem tem integracoes. O webhook recebe
--   os eventos de todos os membros; cada token age em nome de quem o criou.
-- Aplicar depois de upgrade_tenants_users.sql. As funções que podem estar diferentes na produção
-- recebem só a troca do filtro, conferindo cada trecho.

create unique index tjba_credentials_tenant_key on apoiarcred_private.tjba_credentials(tenant_id);
create unique index digimais_preferences_tenant_key on apoiarcred_private.digimais_preferences(tenant_id);
create index if not exists consulta_jobs_api_running on public.consulta_jobs(tenant_id) where execution_mode='api' and status='processando';

create function apoiarcred_private.patch_function(p_fn regprocedure,p_pairs text[])
returns void language plpgsql set search_path='' as $$
declare def text=pg_get_functiondef(p_fn); i integer;
begin
 for i in 1..array_length(p_pairs,1) by 2 loop
  if position(p_pairs[i] in def)=0 then raise exception 'Trecho não encontrado em %: %',p_fn,p_pairs[i];end if;
  def=replace(def,p_pairs[i],p_pairs[i+1]);
 end loop;
 execute def;
end $$;

-- 1. Acesso ConsigX da empresa.
create or replace function apoiarcred_private.save_tjba_credentials(p_username text,p_password text,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); company uuid=apoiarcred_private.user_tenant(auth.uid());
 current_row apoiarcred_private.tjba_credentials; changed boolean=false;
begin
 if uid is null or company is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if not (apoiarcred_private.has_permission(uid,'acesso.portais') or apoiarcred_private.is_admin(uid)) then
  raise insufficient_privilege using message='Apenas quem cuida dos acessos da empresa pode alterar o acesso ConsigX.';end if;
 if p_username is null or length(btrim(p_username)) not between 1 and 160 or length(coalesce(p_password,''))>512 then raise exception 'Usuário ou senha inválidos.';end if;
 perform pg_advisory_xact_lock(hashtextextended(company::text,0));
 select * into current_row from apoiarcred_private.tjba_credentials where tenant_id=company for update;
 if coalesce(p_password,'')='' and (current_row.secret_id is null or current_row.username<>btrim(p_username)) then raise exception 'Informe a senha para esse usuário.';end if;
 if current_row.secret_id is not null and coalesce(p_password,'')<>'' then
  select decrypted_secret is distinct from p_password into changed from vault.decrypted_secrets where id=current_row.secret_id;
  if not found then raise exception 'Segredo TJBA não localizado.';end if;
  perform vault.update_secret(current_row.secret_id,p_password);
 end if;
 if current_row.user_id is null then
  insert into apoiarcred_private.tjba_credentials(user_id,username,secret_id,enabled,updated_at,password_version,password_changed_at)
  values(uid,btrim(p_username),vault.create_secret(p_password,'apoiarcred-tjba-'||company::text),coalesce(p_enabled,false),clock_timestamp(),1,clock_timestamp());
 else
  update apoiarcred_private.tjba_credentials set username=btrim(p_username),enabled=coalesce(p_enabled,false),updated_at=clock_timestamp(),
   password_version=password_version+case when changed then 1 else 0 end,
   password_changed_at=case when changed then clock_timestamp() else password_changed_at end
  where user_id=current_row.user_id;
 end if;
end $$;

create or replace function apoiarcred_private.tjba_credentials_status()
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 select jsonb_build_object('configured',true,'username',username,'enabled',enabled,'updated_at',updated_at,
  'password_version',password_version,'password_changed_at',password_changed_at,
  'can_edit',apoiarcred_private.has_permission(auth.uid(),'acesso.portais') or apoiarcred_private.is_admin(auth.uid()))
 into result from apoiarcred_private.tjba_credentials where tenant_id=apoiarcred_private.user_tenant(auth.uid());
 return coalesce(result,jsonb_build_object('configured',false,'enabled',false,
  'can_edit',apoiarcred_private.has_permission(auth.uid(),'acesso.portais') or apoiarcred_private.is_admin(auth.uid())));
end $$;

-- O robô recebe o dono do job; usa o acesso da empresa dele.
select apoiarcred_private.patch_function('apoiarcred_private.get_tjba_credentials(uuid)',array[
 'where c.user_id=p_user_id','where c.tenant_id=apoiarcred_private.user_tenant(p_user_id)']);

create or replace function apoiarcred_private.tjba_robot_login(p_uid uuid,p_slot integer)
returns table(username text,secret_id uuid,enabled boolean,updated_at timestamptz)
language sql stable security definer set search_path='' as $$
 select r.username,r.secret_id,r.enabled,r.updated_at
 from apoiarcred_private.tjba_robot_credentials r
 where r.user_id=p_uid and r.slot=p_slot and r.enabled and apoiarcred_private.is_admin(p_uid)
 union all
 select c.username,c.secret_id,c.enabled,c.updated_at
 from apoiarcred_private.tjba_credentials c
 join apoiarcred_private.tenant_members m on m.tenant_id=c.tenant_id and m.user_id=p_uid and m.active
 join apoiarcred_private.tenants t on t.id=m.tenant_id and t.active
 where coalesce(p_slot,1)=1 and c.enabled and not apoiarcred_private.is_admin(p_uid);
$$;

-- 2. Digi+ pela API: preferências da empresa.
create or replace function apoiarcred_private.can_use_digimais_api(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select apoiarcred_private.is_admin(p_user) or (
  exists(select 1 from apoiarcred_private.digimais_preferences d
   where d.tenant_id=apoiarcred_private.user_tenant(p_user) and d.api_enabled)
  and (apoiarcred_private.has_permission(p_user,'consulta.digimais.individual')
   or apoiarcred_private.has_permission(p_user,'consulta.digimais.campanha')));
$$;
select apoiarcred_private.patch_function('apoiarcred_private.assign_digimais_execution()',array[
 'from apoiarcred_private.digimais_preferences where user_id=new.user_id',
 'from apoiarcred_private.digimais_preferences where tenant_id=apoiarcred_private.user_tenant(new.user_id)']);
select apoiarcred_private.patch_function('public.claim_consulta_job_for_api(integer)',array[
 'p.user_id=j.user_id','p.tenant_id=j.tenant_id',
 'r.user_id=j.user_id','r.tenant_id=j.tenant_id']);

create or replace function apoiarcred_private.admin_digimais_access(p_user uuid,p_enabled boolean,p_max integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; company uuid;
begin
 if not apoiarcred_private.is_admin(auth.uid()) then raise insufficient_privilege;end if;
 if p_user is not null then
  if p_enabled is null or p_max is null or p_max not between 1 and 100 then raise exception 'Informe um limite entre 1 e 100';end if;
  perform pg_advisory_xact_lock(763212,1);
  select tenant_id into company from apoiarcred_private.tenant_members where user_id=p_user;
  if company is null or apoiarcred_private.is_admin(p_user) then raise exception 'Parceiro não encontrado';end if;
  if p_enabled and not exists(select 1 from apoiarcred_private.digimais_api_config) then raise exception 'Configure a API Digi+ antes de liberar';end if;
  if p_enabled and not exists(select 1 from apoiarcred_private.tenant_grants where tenant_id=company and permission_key like 'consulta.digimais.%') then
   raise exception 'Libere o serviço Digi+ para este parceiro primeiro';end if;
  update apoiarcred_private.digimais_preferences set mode=case when p_enabled then 'api' else 'robot' end,paused=false,
   max_concurrency=p_max,api_enabled=p_enabled where tenant_id=company;
  if not found then
   insert into apoiarcred_private.digimais_preferences(user_id,mode,paused,max_concurrency,api_enabled)
   values(p_user,case when p_enabled then 'api' else 'robot' end,false,p_max,p_enabled);
  end if;
  update public.consulta_jobs set execution_mode=case when p_enabled then 'api' else 'robot' end,api_slot=null,robot_slot=null
  where tenant_id=company and status='aguardando' and api_handoff is null;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('user_id',u.user_id,'name',u.name,'email',u.email,'active',u.active,
  'enabled',coalesce(d.api_enabled,false),'max_concurrency',coalesce(d.max_concurrency,1),
  'members',(select count(*) from apoiarcred_private.tenant_members m where m.tenant_id=t.id and m.active)) order by u.name),'[]'::jsonb)
 into result from apoiarcred_private.user_profiles u
 left join apoiarcred_private.tenants t on t.legacy_owner_id=u.user_id
 left join apoiarcred_private.digimais_preferences d on d.tenant_id=t.id
 where u.role='partner';
 return result;
end $$;

-- 3. Integrações da empresa.
create function apoiarcred_private.tenant_integrates(p_tenant uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from apoiarcred_private.tenants t
  join apoiarcred_private.tenant_grants g on g.tenant_id=t.id and g.permission_key='integracoes'
  where t.id=p_tenant and t.active);
$$;
revoke all on function apoiarcred_private.tenant_integrates(uuid) from public,anon,authenticated;

select apoiarcred_private.patch_function('apoiarcred_private.wh_enqueue(uuid,text,text,jsonb,text,uuid,text,text,boolean,boolean)',array[
 'if not apoiarcred_private.can_integrate(uid) then return null;end if;',
 'if not apoiarcred_private.tenant_integrates(apoiarcred_private.user_tenant(uid)) then return null;end if;',
 'where w.user_id=uid and w.active','where w.tenant_id=apoiarcred_private.user_tenant(uid) and w.active']);
select apoiarcred_private.patch_function('apoiarcred_private.wh_claim()',array[
 'join apoiarcred_private.user_profiles p on p.user_id=w.user_id and p.active and (p.role=''admin'' or p.allow_integrations)',
 '']);
select apoiarcred_private.patch_function('apoiarcred_private.wh_claim()',array[
 'where w.active and q.attempts<8','where w.active and apoiarcred_private.tenant_integrates(w.tenant_id) and q.attempts<8']);
select apoiarcred_private.patch_function('apoiarcred_private.manage_webhooks(text,jsonb)',array[
 'from apoiarcred_private.webhooks x where user_id=uid','from apoiarcred_private.webhooks x where tenant_id=apoiarcred_private.user_tenant(uid)',
 'where h.user_id=uid and (hid is null','where h.tenant_id=apoiarcred_private.user_tenant(uid) and (hid is null',
 'from apoiarcred_private.webhooks where id=hid and user_id=uid for update','from apoiarcred_private.webhooks where id=hid and tenant_id=apoiarcred_private.user_tenant(uid) for update',
 'and h.user_id=uid for update of d','and h.tenant_id=apoiarcred_private.user_tenant(uid) for update of d',
 'from apoiarcred_private.webhooks where user_id=uid)>=20','from apoiarcred_private.webhooks where tenant_id=apoiarcred_private.user_tenant(uid))>=20',
 'hashtextextended(uid::text,11)','hashtextextended(apoiarcred_private.user_tenant(uid)::text,11)',
 'Limite de 20 webhooks por conta.','Limite de 20 webhooks por empresa.']);
select apoiarcred_private.patch_function('apoiarcred_private.manage_api_tokens(text,jsonb)',array[
 'from apoiarcred_private.api_tokens t where t.user_id=uid','from apoiarcred_private.api_tokens t where t.tenant_id=apoiarcred_private.user_tenant(uid)',
 '''last_used_at'',t.last_used_at)','''last_used_at'',t.last_used_at,''created_by'',(select coalesce(m.name,m.email) from apoiarcred_private.tenant_members m where m.user_id=t.user_id))',
 'where id=(p_input->>''id'')::uuid and user_id=uid','where id=(p_input->>''id'')::uuid and tenant_id=apoiarcred_private.user_tenant(uid)',
 'hashtextextended(uid::text,0)','hashtextextended(apoiarcred_private.user_tenant(uid)::text,0)',
 'where user_id=uid and revoked_at is null','where tenant_id=apoiarcred_private.user_tenant(uid) and revoked_at is null']);

drop function apoiarcred_private.patch_function(regprocedure,text[]);

-- ===================== upgrade_tenants_platform
-- Multi-tenant · etapa 6a: tela da equipe ApoiarCred gravando direto na empresa.
-- • A tela de Parceiros (admin_partner_manage) cria e altera empresas: teto, cota, teste e situação.
--   O mesmo formato de antes, para o painel e a API da VPS não mudarem.
-- • partner_permissions deixa de ser lido ou escrito (a limpeza da etapa 6b remove a tabela).
-- • Juntar parceiros: mover o responsável de uma empresa para outra, levando os dados dele.
-- Aplicar depois de upgrade_tenants_resources.sql.

-- 1. Teto da empresa a partir do que a tela envia.
create function apoiarcred_private.platform_set_grants(p_tenant uuid,p_rules jsonb,p_amigoz boolean,p_integrations boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from apoiarcred_private.tenant_grants where tenant_id=p_tenant
  and permission_key in (select key from apoiarcred_private.permissions where service in ('digimais_saldo_parcela','tjba_margem'));
 insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select p_tenant,p.key from apoiarcred_private.permissions p
 join jsonb_array_elements(coalesce(p_rules,'[]')) r on r->>'service'=p.service
 where coalesce((r->>'enabled')::boolean,false)
  and case p.mode when 'individual' then coalesce((r->>'allow_individual')::boolean,false) else coalesce((r->>'allow_campaign')::boolean,false) end;
 if p_amigoz is not null then
  delete from apoiarcred_private.tenant_grants where tenant_id=p_tenant and permission_key like 'consulta.amigoz.%';
  if p_amigoz then insert into apoiarcred_private.tenant_grants select p_tenant,key from apoiarcred_private.permissions where service='amigoz';end if;
 end if;
 if p_integrations is not null then
  delete from apoiarcred_private.tenant_grants where tenant_id=p_tenant and permission_key='integracoes';
  if p_integrations then insert into apoiarcred_private.tenant_grants values(p_tenant,'integracoes');end if;
 end if;
end $$;

-- 2. Empresa criada a partir do perfil (equipe ApoiarCred: todas as permissões, sem cota).
create or replace function apoiarcred_private.provision_tenant(p_user uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles; company uuid; admin_role uuid;
begin
 select tenant_id into company from apoiarcred_private.tenant_members where user_id=p_user;
 if company is not null then return company;end if;
 select * into profile from apoiarcred_private.user_profiles where user_id=p_user;
 if not found then return null;end if;
 insert into apoiarcred_private.tenants(name,legacy_owner_id,active,trial_until,daily_limit)
 values(coalesce(nullif(btrim(profile.name),''),profile.email,'Empresa'),p_user,profile.active,profile.trial_until,
  case when profile.role<>'admin' and profile.shared_quota then profile.shared_daily_limit end) returning id into company;
 perform apoiarcred_private.seed_tenant_roles(company);
 select id into admin_role from apoiarcred_private.tenant_roles where tenant_id=company and code='administrador';
 insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id,name,email) values(company,p_user,admin_role,profile.name,profile.email);
 insert into apoiarcred_private.tenant_grants(tenant_id,permission_key)
 select company,p.key from apoiarcred_private.permissions p
 where profile.role='admin' or (p.service is null and p.key<>'integracoes')
  or (p.key='integracoes' and coalesce(profile.allow_integrations,false))
  or (p.service='amigoz' and coalesce(profile.allow_amigoz,false));
 if profile.role='admin' then insert into apoiarcred_private.platform_admins(user_id) values(p_user) on conflict do nothing;end if;
 return company;
end $$;

-- O perfil só cria a empresa; depois disso a empresa é a fonte da verdade.
drop trigger legacy_tenant on apoiarcred_private.partner_permissions;
drop trigger legacy_tenant on apoiarcred_private.user_profiles;
create or replace function apoiarcred_private.legacy_tenant_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then perform apoiarcred_private.provision_tenant(new.user_id);end if;
 if tg_op='INSERT' or new.role is distinct from old.role then
  if new.role='admin' then insert into apoiarcred_private.platform_admins(user_id) values(new.user_id) on conflict do nothing;
  else delete from apoiarcred_private.platform_admins where user_id=new.user_id;end if;
 end if;
 return null;
end $$;
create trigger legacy_tenant after insert or update of role on apoiarcred_private.user_profiles
 for each row execute function apoiarcred_private.legacy_tenant_trigger();
drop function apoiarcred_private.sync_legacy_tenant(uuid);

-- Equipe ApoiarCred: só a tabela própria.
create or replace function apoiarcred_private.is_admin(uid uuid)
returns boolean language sql stable security definer set search_path='' as
$$ select exists(select 1 from apoiarcred_private.platform_admins a where a.user_id=uid) $$;

-- 3. Tela de Parceiros = empresas.
create function apoiarcred_private.platform_company_json(p_tenant uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',o.user_id,'tenant_id',t.id,'name',t.name,
  'email',coalesce(o.email,p.email,u.email),'active',t.active,'created_at',t.created_at,
  'allow_integrations',exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=t.id and g.permission_key='integracoes'),
  'allow_amigoz',exists(select 1 from apoiarcred_private.tenant_grants g where g.tenant_id=t.id and g.permission_key='consulta.amigoz.individual'),
  'shared_quota',true,'shared_daily_limit',t.daily_limit,'trial_until',t.trial_until,
  'members',(select count(*) from apoiarcred_private.tenant_members m where m.tenant_id=t.id and m.active),
  'access',apoiarcred_private.access_for(o.user_id))
 from apoiarcred_private.tenants t
 -- Responsável: quem criou a empresa, ou o administrador mais antigo se ele saiu.
 cross join lateral (select m.user_id,m.email from apoiarcred_private.tenant_members m
  join apoiarcred_private.tenant_roles r on r.id=m.role_id
  where m.tenant_id=t.id order by m.user_id=t.legacy_owner_id desc,r.code='administrador' desc,m.created_at limit 1) o
 left join apoiarcred_private.user_profiles p on p.user_id=o.user_id
 left join auth.users u on u.id=o.user_id
 where t.id=p_tenant;
$$;
revoke all on function apoiarcred_private.platform_company_json(uuid) from public,anon,authenticated;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid; item jsonb; rules jsonb; result jsonb; quota integer; trial date; company uuid;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(apoiarcred_private.platform_company_json(t.id) order by t.created_at desc),'[]') into result
  from apoiarcred_private.tenants t
  where exists(select 1 from apoiarcred_private.tenant_members m where m.tenant_id=t.id)
   and not exists(select 1 from apoiarcred_private.tenant_members m join apoiarcred_private.platform_admins a on a.user_id=m.user_id where m.tenant_id=t.id);
  return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null or apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_action='create' and (exists(select 1 from apoiarcred_private.user_profiles where user_id=uid)
  or exists(select 1 from apoiarcred_private.tenant_members where user_id=uid)) then raise exception 'Perfil já existe.';end if;
 if p_action='update' then
  company=apoiarcred_private.user_tenant(uid);
  if company is null then raise insufficient_privilege;end if;
 end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' is null or item->>'service' not in ('digimais_saldo_parcela','tjba_margem') then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_input ? 'allow_integrations' and jsonb_typeof(p_input->'allow_integrations') is distinct from 'boolean' then raise exception 'Permissão de integrações inválida.';end if;
 if p_input ? 'allow_amigoz' and jsonb_typeof(p_input->'allow_amigoz') is distinct from 'boolean' then raise exception 'Permissão Amigoz inválida.';end if;
 if p_input ? 'shared_daily_limit' then
  if jsonb_typeof(p_input->'shared_daily_limit') not in ('number','null') then raise exception 'Cota diária inválida.';end if;
  quota=(p_input->>'shared_daily_limit')::integer;
  if quota not between 1 and 100000 then raise exception 'Cota diária inválida.';end if;
 end if;
 if p_input ? 'trial_until' then trial=(p_input->>'trial_until')::date;end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,shared_quota,shared_daily_limit,trial_until,created_by)
  values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),true,quota,trial,p_actor);
  company=apoiarcred_private.user_tenant(uid);
 end if;
 perform 1 from apoiarcred_private.tenants where id=company for update;
 update apoiarcred_private.tenants set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),
  daily_limit=case when p_input ? 'shared_daily_limit' then quota else daily_limit end,
  trial_until=case when p_input ? 'trial_until' then trial else trial_until end
 where id=company;
 update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),updated_at=now() where user_id=uid;
 perform apoiarcred_private.platform_set_grants(company,rules,(p_input->>'allow_amigoz')::boolean,(p_input->>'allow_integrations')::boolean);
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(company,p_actor,uid,'empresa.'||case p_action when 'create' then 'criada' else 'alterada' end,p_input-'email');
 return apoiarcred_private.access_for(uid);
end $$;
revoke all on function public.admin_partner_manage(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_partner_manage(uuid,text,jsonb) to service_role;

-- 4. Juntar parceiros: o responsável de uma empresa passa para outra com os dados dele.
-- Etapas do funil seguem pelo código (as personalizadas vão para a etapa inicial do destino);
-- acessos ConsigX, preferências Digi+, webhooks e configuração dos cartões ficam na empresa de origem.
create function public.admin_move_member(p_user uuid,p_target_user uuid,p_role text default 'gestor')
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid(); source uuid; target uuid; new_role uuid; seed_user uuid; item text; s text; t text; moved integer=0; n integer;
begin
 if not apoiarcred_private.is_admin(actor) then raise insufficient_privilege;end if;
 source=apoiarcred_private.user_tenant(p_user);target=apoiarcred_private.user_tenant(p_target_user);
 if source is null or target is null or apoiarcred_private.is_admin(p_user) or apoiarcred_private.is_admin(p_target_user) then
  raise exception using errcode='22023',message='Escolha um parceiro e uma empresa de destino.';end if;
 if source=target then raise exception using errcode='22023',message='O parceiro já está nessa empresa.';end if;
 select id into new_role from apoiarcred_private.tenant_roles where tenant_id=target and code=p_role;
 if new_role is null then raise exception using errcode='22023',message='Papel inválido.';end if;
 if exists(select 1 from apoiarcred_private.tenant_members where tenant_id=source and user_id<>p_user and active) then
  raise exception using errcode='22023',message='A empresa de origem tem outros usuários ativos. Mova ou desative esses usuários antes.';end if;
 perform pg_advisory_xact_lock(hashtextextended('move:'||least(source,target)::text||greatest(source,target)::text,0));
 if exists(select 1 from public.consulta_jobs where user_id=p_user and status='processando')
  or exists(select 1 from public.tjba_jobs where user_id=p_user and status='processando') then
  raise exception using errcode='55006',message='Há consultas deste parceiro em andamento. Pause as campanhas e tente de novo em alguns minutos.';end if;

 -- Funil do destino pronto para receber os cartões.
 select user_id into seed_user from apoiarcred_private.tenant_members where tenant_id=target order by created_at limit 1;
 perform apoiarcred_private.crm_semear_etapas(seed_user);

 foreach item in array array[
  'public.amigoz_coefficient_simulations','public.amigoz_comissoes','public.amigoz_comissoes_tabela',
  'public.amigoz_jobs','public.amigoz_simulacoes','public.consulta_jobs','public.consulta_lotes',
  'public.consulta_tjba_historico','public.crm_cadastros','public.crm_campanhas_reuso',
  'public.crm_classificacoes','public.crm_dados_cliente','public.crm_exportacoes',
  'public.crm_import_requests','public.crm_margens_vinculo','public.crm_movimentacoes','public.crm_oportunidades',
  'public.crm_vinculos','public.painel_exclusoes','public.tjba_jobs','public.tjba_lotes',
  'apoiarcred_private.api_tokens','apoiarcred_private.webhook_events','apoiarcred_private.webhook_campaign_dirty'] loop
  s=split_part(item,'.',1);t=split_part(item,'.',2);
  -- Sem gatilhos: mudar a empresa não é uma nova consulta, movimentação ou evento de webhook.
  execute format('alter table %I.%I disable trigger user',s,t);
  if item='public.crm_oportunidades' then
   update public.crm_oportunidades o set tenant_id=target,
    etapa_id=coalesce(same.id,first.id),etapa=coalesce(same.codigo,first.codigo)
   from public.crm_etapas old
   left join public.crm_etapas same on same.tenant_id=target and same.codigo=old.codigo and not same.arquivada
   cross join lateral (select e.id,e.codigo from public.crm_etapas e where e.tenant_id=target and e.inicial limit 1) first
   where o.user_id=p_user and old.id=o.etapa_id;
  else
   execute format('update %I.%I set tenant_id=$1 where user_id=$2',s,t) using target,p_user;
  end if;
  get diagnostics n=row_count;moved=moved+n;
  execute format('alter table %I.%I enable trigger user',s,t);
 end loop;

 delete from apoiarcred_private.member_overrides where tenant_id=source and user_id=p_user;
 update apoiarcred_private.tenant_members set tenant_id=target,role_id=new_role where user_id=p_user;
 update apoiarcred_private.tenants set active=false where id=source
  and not exists(select 1 from apoiarcred_private.tenant_members m where m.tenant_id=source);
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(target,actor,p_user,'usuario.movido',jsonb_build_object('origem',source,'registros',moved,'papel',p_role));
 return jsonb_build_object('tenant_id',target,'registros',moved);
end $$;
revoke all on function public.admin_move_member(uuid,uuid,text) from public,anon;
grant execute on function public.admin_move_member(uuid,uuid,text) to authenticated;

-- 5. Conferência da importação do CRM (versão leve da produção) pela empresa: permissões do
-- usuário e cota única da empresa, sem ler as tabelas antigas.
create or replace function public.crm_preview_import(
 p_uf text,p_convenio text,p_servicos text[],p_rows jsonb
) returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='45s'
as $function$
declare
 uid uuid:=auth.uid();
 account_access jsonb;
 admin boolean;
 errors jsonb;
 clients integer;
 existing_clients integer;
 consultations integer:=0;
 company_limit integer;
 used_today integer;
 service_id text;
begin
 if uid is null then raise insufficient_privilege;end if;
 account_access:=apoiarcred_private.access_for(uid);
 if not coalesce((account_access->>'active')::boolean,false)
    or coalesce((account_access->>'trial_expired')::boolean,false) then
  raise insufficient_privilege using message='Importação indisponível para esta conta.';
 end if;
 admin:=apoiarcred_private.is_admin(uid);

 errors:=apoiarcred_private.crm_import_errors(p_uf,p_convenio,p_servicos,p_rows);
 if errors<>'[]' then return jsonb_build_object('valido',false,'erros',errors);end if;

 select count(*),count(c.cpf) into clients,existing_clients
 from (select distinct item->>'cpf' as cpf from jsonb_array_elements(p_rows) item) imported
 left join public.crm_cadastros c on c.user_id=uid and c.cpf=imported.cpf;

 for service_id in
  select service from (values ('digimais_saldo','digimais_saldo_parcela'),
                              ('consigx_margem','tjba_margem')) s(option_name,service)
  where option_name=any(p_servicos)
 loop
  consultations:=consultations+clients;
  if not admin and not apoiarcred_private.has_permission(uid,apoiarcred_private.consult_key(service_id,'campanha')) then
   raise insufficient_privilege using message='Campanhas não estão habilitadas para este tipo de higienização.';
  end if;
 end loop;

 if p_servicos && array['amigoz_margem','amigoz_saque'] then
  consultations:=consultations+jsonb_array_length(p_rows);
  if not admin and not apoiarcred_private.has_permission(uid,'consulta.amigoz.individual') then
   raise insufficient_privilege using message='Acesso Amigoz não liberado.';
  end if;
 end if;

 select t.daily_limit,coalesce(u.used,0) into company_limit,used_today
 from apoiarcred_private.tenants t
 left join apoiarcred_private.tenant_daily_usage u on u.tenant_id=t.id and u.day=apoiarcred_private.today_sp()
 where t.id=apoiarcred_private.user_tenant(uid);
 if not admin and consultations>0 and company_limit is not null and used_today+consultations>company_limit then
  raise sqlstate 'PT429' using message='A planilha excede o saldo de consultas da cota diária da empresa.';
 end if;

 return jsonb_build_object('valido',true,'uf',p_uf,'convenio',p_convenio,
  'registros',jsonb_array_length(p_rows),'clientes',clients,
  'clientes_novos',clients-existing_clients,'clientes_atualizados',existing_clients,
  'consultas',consultations);
exception when raise_exception or insufficient_privilege or sqlstate 'PT429' then
 return jsonb_build_object('valido',false,'erros',
  jsonb_build_array(jsonb_build_object('linha',0,'mensagem',sqlerrm)));
end
$function$;

-- ===================== conferência final
do $$
declare diffs jsonb; missing integer;
begin
 select coalesce(jsonb_agg(jsonb_build_object('perfil',b.user_id,'antes',b.a->'services','depois',n.a->'services')),'[]') into diffs
 from apoiarcred_private.zz_access_before b cross join lateral (select apoiarcred_private.access_for(b.user_id) a) n
 where b.role<>'admin' and ((b.a->'active') is distinct from (n.a->'active')
  or (select jsonb_agg(jsonb_build_array(s->>'id',s->'enabled',s->'allow_individual',s->'allow_campaign')) from jsonb_array_elements(b.a->'services') s)
   is distinct from (select jsonb_agg(jsonb_build_array(s->>'id',s->'enabled',s->'allow_individual',s->'allow_campaign')) from jsonb_array_elements(n.a->'services') s)
  or (b.a->'allow_amigoz') is distinct from (n.a->'allow_amigoz') or (b.a->'allow_integrations') is distinct from (n.a->'allow_integrations'));
 select (select count(*) from public.consulta_jobs where tenant_id is null)+(select count(*) from public.tjba_jobs where tenant_id is null)
  +(select count(*) from public.crm_oportunidades where tenant_id is null) into missing;
 if jsonb_array_length(diffs)>0 or missing>0 then
  raise exception 'ABORTADO, nada foi aplicado. Diferenças: % · registros sem empresa: %',diffs,missing;
 end if;
 raise notice 'MULTITENANT_OK';
end $$;
drop table apoiarcred_private.zz_access_before;
select 'MULTITENANT_OK' as resultado,(select count(*) from apoiarcred_private.tenants) empresas,(select count(*) from apoiarcred_private.tenant_members) usuarios;
commit;
