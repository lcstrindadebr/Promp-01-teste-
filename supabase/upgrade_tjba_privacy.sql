-- Explicit default deny; access stays exclusively inside owner-scoped private functions.
create policy tjba_credentials_no_direct_access on apoiarcred_private.tjba_credentials for all to public using(false) with check(false);
create function apoiarcred_private.cleanup_tjba_secret() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from vault.secrets where id=old.secret_id;
 return old;
end $$;
revoke all on function apoiarcred_private.cleanup_tjba_secret() from public,anon,authenticated,service_role;
create trigger cleanup_tjba_secret after delete on apoiarcred_private.tjba_credentials for each row execute function apoiarcred_private.cleanup_tjba_secret();
