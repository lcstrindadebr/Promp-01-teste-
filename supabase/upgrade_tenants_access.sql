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
