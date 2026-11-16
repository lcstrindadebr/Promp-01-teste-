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
