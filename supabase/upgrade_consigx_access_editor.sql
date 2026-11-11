-- A single authenticated entry point for the shared and per-robot logins.
-- Existing routines retain validation, owner scoping and Vault secret IDs.
create or replace function public.manage_consigx_access(
 p_slot integer default null,
 p_username text default null,
 p_password text default null,
 p_enabled boolean default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 admin boolean;
 robot_access jsonb := '[]'::jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 admin := public.am_i_admin();
 if p_slot is not null then
  if p_slot not between 0 and 3 or p_enabled is null then
   raise exception 'Selecione um acesso válido.';
  end if;
  if p_slot=0 then
   perform public.save_tjba_credentials(p_username,p_password,p_enabled);
  else
   if not admin then raise insufficient_privilege;end if;
   robot_access := public.manage_tjba_robot_credentials(p_slot,p_username,p_password,p_enabled);
  end if;
 end if;
 if admin and (p_slot is null or p_slot=0) then
  robot_access := public.manage_tjba_robot_credentials();
 end if;
 return jsonb_build_object('shared',public.tjba_credentials_status(),'robots',robot_access);
end $$;
revoke all on function public.manage_consigx_access(integer,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.manage_consigx_access(integer,text,text,boolean) to authenticated;
notify pgrst,'reload schema';
