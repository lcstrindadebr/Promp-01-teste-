-- Minimal stand-in for what Supabase provides (roles, auth, extensions, vault) so the
-- project schema and SQL tests run on a plain PostgreSQL 15+/16 server.
do $$ begin
 -- Roles are cluster-wide: create them once, reuse them for every test database.
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
 if not exists(select 1 from pg_roles where rolname='authenticator') then create role authenticator login noinherit; end if;
 if not exists(select 1 from pg_roles where rolname='supabase_admin') then create role supabase_admin superuser; end if;
end $$;
grant anon,authenticated,service_role to authenticator;
create schema extensions; create extension pgcrypto with schema extensions;
create schema auth;
create table auth.users(id uuid primary key default gen_random_uuid(), aud text, role text, email text, raw_user_meta_data jsonb default '{}', created_at timestamptz default now(), encrypted_password text, email_confirmed_at timestamptz, deleted_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(coalesce(current_setting('request.jwt.claim.sub',true),(current_setting('request.jwt.claims',true)::jsonb->>'sub')),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select coalesce(current_setting('request.jwt.claim.role',true),(current_setting('request.jwt.claims',true)::jsonb->>'role')) $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
grant usage on schema auth,extensions to anon,authenticated,service_role;
create schema vault;
create table vault.secrets(id uuid primary key default gen_random_uuid(), name text unique, secret text, description text);
create view vault.decrypted_secrets as select id,name,secret as decrypted_secret,description from vault.secrets;
create function vault.create_secret(new_secret text, new_name text default null, new_description text default '') returns uuid language sql as $$ insert into vault.secrets(name,secret,description) values(new_name,new_secret,new_description) returning id $$;
create function vault.update_secret(secret_id uuid, new_secret text default null, new_name text default null, new_description text default null) returns void language sql as $$ update vault.secrets set secret=coalesce(new_secret,secret),name=coalesce(new_name,name) where id=secret_id $$;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges in schema public grant all on functions to anon,authenticated,service_role;
