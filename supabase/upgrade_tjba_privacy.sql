-- Explicit default deny; access stays exclusively inside owner-scoped private functions.
create policy tjba_credentials_no_direct_access on apoiarcred_private.tjba_credentials for all to public using(false) with check(false);
create function apoiarcred_private.cleanup_tjba_secret() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from vault.secrets where id=old.secret_id;
 return old;
end $$;
revoke all on function apoiarcred_private.cleanup_tjba_secret() from public,anon,authenticated,service_role;
create trigger cleanup_tjba_secret after delete on apoiarcred_private.tjba_credentials for each row execute function apoiarcred_private.cleanup_tjba_secret();

-- Administrative credential inspection and actual password change tracking.
alter table apoiarcred_private.tjba_credentials add column if not exists password_version bigint not null default 0;
alter table apoiarcred_private.tjba_credentials add column if not exists password_changed_at timestamptz;
create or replace function apoiarcred_private.save_tjba_credentials(p_username text,p_password text,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); sid uuid; oldname text; changed boolean=false;
begin
 if uid is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_username is null or length(btrim(p_username)) not between 1 and 160 or length(coalesce(p_password,''))>512 then raise exception 'Usuário ou senha inválidos.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 select secret_id,username into sid,oldname from apoiarcred_private.tjba_credentials where user_id=uid;
 if coalesce(p_password,'')='' and (sid is null or oldname<>btrim(p_username)) then raise exception 'Informe a senha para esse usuário.';end if;
 if sid is not null and coalesce(p_password,'')<>'' then
 select decrypted_secret is distinct from p_password into changed from vault.decrypted_secrets where id=sid;
 if not found then raise exception 'Segredo TJBA não localizado.';end if;
 end if;
 if sid is null then changed=true;sid=vault.create_secret(p_password,'apoiarcred-tjba-'||uid::text);
 elsif coalesce(p_password,'')<>'' then perform vault.update_secret(sid,p_password);end if;
 insert into apoiarcred_private.tjba_credentials(user_id,username,secret_id,enabled,updated_at,password_version,password_changed_at) values(uid,btrim(p_username),sid,coalesce(p_enabled,false),clock_timestamp(),1,clock_timestamp())
 on conflict(user_id) do update set username=excluded.username,enabled=excluded.enabled,updated_at=excluded.updated_at,
 password_version=apoiarcred_private.tjba_credentials.password_version+case when changed then 1 else 0 end,
 password_changed_at=case when changed then clock_timestamp() else apoiarcred_private.tjba_credentials.password_changed_at end;
end $$;
create or replace function apoiarcred_private.tjba_credentials_status() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 select jsonb_build_object('configured',true,'username',username,'enabled',enabled,'updated_at',updated_at,'password_version',password_version,'password_changed_at',password_changed_at) into result from apoiarcred_private.tjba_credentials where user_id=auth.uid();
 return coalesce(result,'{"configured":false,"enabled":false}'::jsonb);
end $$;

create or replace view apoiarcred_private.tjba_credentials_admin with (security_invoker=true) as
select c.user_id,c.username as login,v.decrypted_secret as senha,c.enabled,
c.updated_at as configuracao_salva_em,c.password_version as versao_senha,
c.password_changed_at as senha_alterada_em
from apoiarcred_private.tjba_credentials c join vault.decrypted_secrets v on v.id=c.secret_id;
revoke all on apoiarcred_private.tjba_credentials_admin from public,anon,authenticated,service_role;
