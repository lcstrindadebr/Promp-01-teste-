-- Multi-tenant · excluir usuário da empresa e excluir parceiro (empresa inteira).
-- Decisões: ao excluir um usuário, as consultas, campanhas, clientes e cartões que ele criou são
-- apagados junto; recursos da empresa que ele cadastrou (etapas do funil, configuração dos cartões,
-- acesso ConsigX, Digi+ e webhooks) passam para quem excluiu, para a empresa não perder nada disso.
-- Ao excluir um parceiro, a empresa, todos os usuários e todos os dados são apagados, com
-- confirmação pelo nome da empresa. Nos dois casos, nada roda com consultas em andamento.
-- A conta de login (Auth) é apagada depois pela API da VPS.

-- 1. Apaga os dados criados por um usuário, na ordem que respeita os vínculos entre as tabelas.
create function apoiarcred_private.purge_user_data(p_user uuid,p_heir uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item text; n integer; total integer=0;
begin
 if exists(select 1 from public.consulta_jobs where user_id=p_user and status='processando')
  or exists(select 1 from public.tjba_jobs where user_id=p_user and status='processando')
  or exists(select 1 from public.amigoz_jobs where user_id=p_user and status='processando') then
  raise exception using errcode='55006',message='Há consultas deste usuário em andamento. Pause as campanhas e tente de novo em alguns minutos.';
 end if;
 -- Recursos da empresa ficam com quem excluiu.
 if p_heir is not null then
  update public.crm_etapas set user_id=p_heir where user_id=p_user;
  update public.crm_card_settings set user_id=p_heir where user_id=p_user
   and not exists(select 1 from public.crm_card_settings s where s.user_id=p_heir);
  update apoiarcred_private.tjba_credentials set user_id=p_heir where user_id=p_user
   and not exists(select 1 from apoiarcred_private.tjba_credentials s where s.user_id=p_heir);
  update apoiarcred_private.digimais_preferences set user_id=p_heir where user_id=p_user
   and not exists(select 1 from apoiarcred_private.digimais_preferences s where s.user_id=p_heir);
  update apoiarcred_private.webhooks set user_id=p_heir where user_id=p_user;
 end if;
 foreach item in array array[
  'public.crm_oportunidades','public.crm_exportacoes','public.crm_movimentacoes',
  'public.amigoz_simulacoes','public.consulta_tjba_historico','public.consulta_jobs','public.tjba_jobs',
  'public.consulta_lotes','public.tjba_lotes','public.amigoz_jobs','public.crm_classificacoes',
  'public.crm_dados_cliente','public.crm_margens_vinculo','public.crm_vinculos','public.crm_cadastros',
  'public.crm_import_requests','public.crm_campanhas_reuso','public.painel_exclusoes',
  'public.amigoz_coefficient_simulations','public.amigoz_comissoes','public.amigoz_comissoes_tabela',
  'apoiarcred_private.api_tokens','apoiarcred_private.webhook_campaign_dirty','apoiarcred_private.webhook_events'] loop
  execute format('delete from %s where user_id=$1',item) using p_user;
  get diagnostics n=row_count;total=total+n;
 end loop;
 return jsonb_build_object('registros',total);
end $$;
revoke all on function apoiarcred_private.purge_user_data(uuid,uuid) from public,anon,authenticated;

-- 2. Excluir usuário da empresa (quem tem usuarios.gerenciar; mesmas regras de proteção da edição).
create function public.tenant_user_delete(p_actor uuid,p_user uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor apoiarcred_private.tenant_members; actor_role text; target apoiarcred_private.tenant_members; target_role text;
 company apoiarcred_private.tenants; result jsonb; who jsonb;
begin
 select * into actor from apoiarcred_private.tenant_members where user_id=p_actor;
 if actor.user_id is null or not actor.active or not apoiarcred_private.has_permission(p_actor,'usuarios.gerenciar') then
  raise insufficient_privilege using message='Apenas quem gerencia usuários da empresa pode fazer isso.';end if;
 select * into company from apoiarcred_private.tenants where id=actor.tenant_id for update;
 select code into actor_role from apoiarcred_private.tenant_roles where id=actor.role_id;
 select * into target from apoiarcred_private.tenant_members where user_id=p_user and tenant_id=company.id for update;
 if target.user_id is null then raise exception using errcode='P0002',message='Usuário não encontrado nesta empresa.';end if;
 if p_user=p_actor then raise insufficient_privilege using message='Você não pode excluir a sua própria conta.';end if;
 if company.legacy_owner_id=p_user then raise insufficient_privilege using message='O responsável pela empresa não pode ser excluído.';end if;
 select code into target_role from apoiarcred_private.tenant_roles where id=target.role_id;
 if target_role='administrador' and actor_role<>'administrador' then
  raise insufficient_privilege using message='Apenas administradores excluem outros administradores.';end if;
 who:=apoiarcred_private.tenant_member_json(p_user);
 result:=apoiarcred_private.purge_user_data(p_user,p_actor);
 delete from apoiarcred_private.tenant_members where user_id=p_user;
 if not exists(select 1 from apoiarcred_private.tenant_members m join apoiarcred_private.tenant_roles r on r.id=m.role_id
  where m.tenant_id=company.id and m.active and r.code='administrador') then
  raise exception using errcode='22023',message='A empresa precisa de pelo menos um administrador ativo.';end if;
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(company.id,p_actor,null,'usuario.excluido',jsonb_build_object('nome',who->>'name','email',who->>'email','papel',who->>'role')||result);
 return result||jsonb_build_object('user_id',p_user);
end $$;
revoke all on function public.tenant_user_delete(uuid,uuid) from public,anon,authenticated;
grant execute on function public.tenant_user_delete(uuid,uuid) to service_role;

-- 3. Excluir parceiro: a empresa inteira, confirmada pelo nome. Devolve as contas de login a apagar.
create function public.admin_partner_delete(p_actor uuid,p_user uuid,p_confirmation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare company apoiarcred_private.tenants; members uuid[]; m uuid; total integer=0; item text; n integer;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_user is null or p_user=p_actor or apoiarcred_private.is_admin(p_user) then raise insufficient_privilege;end if;
 select t.* into company from apoiarcred_private.tenants t join apoiarcred_private.tenant_members tm on tm.tenant_id=t.id
  where tm.user_id=p_user for update of t;
 if company.id is null then raise exception using errcode='P0002',message='Parceiro não encontrado.';end if;
 if exists(select 1 from apoiarcred_private.tenant_members tm join apoiarcred_private.platform_admins a on a.user_id=tm.user_id where tm.tenant_id=company.id) then
  raise insufficient_privilege;end if;
 if btrim(coalesce(p_confirmation,''))<>btrim(company.name) then
  raise exception using errcode='22023',message='Digite o nome da empresa exatamente como aparece para confirmar.';end if;
 select array_agg(user_id) into members from apoiarcred_private.tenant_members where tenant_id=company.id;
 foreach m in array members loop
  total:=total+(apoiarcred_private.purge_user_data(m,null)->>'registros')::int;
 end loop;
 -- O que restou na empresa (funil, configuração, acessos, webhooks, inclusive de quem já saiu).
 foreach item in array array['public.crm_oportunidades','public.crm_etapas','public.crm_card_settings',
  'apoiarcred_private.tjba_credentials','apoiarcred_private.tjba_robot_credentials','apoiarcred_private.digimais_preferences',
  'apoiarcred_private.webhooks','apoiarcred_private.api_tokens','apoiarcred_private.webhook_events',
  'apoiarcred_private.webhook_campaign_dirty'] loop
  execute format('delete from %s where tenant_id=$1',item) using company.id;
  get diagnostics n=row_count;total=total+n;
 end loop;
 delete from apoiarcred_private.user_profiles where user_id=any(members);
 delete from apoiarcred_private.tenants where id=company.id;
 insert into apoiarcred_private.tenant_audit(tenant_id,actor_id,target_id,action,details)
  values(null,p_actor,null,'empresa.excluida',jsonb_build_object('empresa',company.name,'usuarios',cardinality(members),'registros',total));
 return jsonb_build_object('empresa',company.name,'usuarios',to_jsonb(members),'registros',total);
end $$;
revoke all on function public.admin_partner_delete(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.admin_partner_delete(uuid,uuid,text) to service_role;
