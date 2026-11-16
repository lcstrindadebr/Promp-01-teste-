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
