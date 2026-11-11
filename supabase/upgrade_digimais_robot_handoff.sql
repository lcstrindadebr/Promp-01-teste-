begin;
alter table public.consulta_jobs add column if not exists api_handoff jsonb;

create or replace function apoiarcred_private.manage_digimais_pilot(p_mode text,p_paused boolean,p_max integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); result jsonb;
begin
 if not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_mode is not null then
  if p_mode not in ('robot','api') or p_paused is null or p_max is null or p_max not between 1 and 12 then raise exception 'Configuração inválida';end if;
  if p_mode='api' and not exists(select 1 from apoiarcred_private.digimais_api_config) then raise exception 'API ainda não configurada na VPS/banco';end if;
  insert into apoiarcred_private.digimais_preferences(user_id,mode,paused,max_concurrency) values(uid,p_mode,p_paused,p_max)
  on conflict(user_id) do update set mode=excluded.mode,paused=excluded.paused,max_concurrency=excluded.max_concurrency;
  -- Switch only waiting campaign jobs owned by this administrator.
  update public.consulta_jobs j
  set execution_mode=p_mode, api_slot=null, robot_slot=null
  from public.consulta_lotes l
  where j.lote_id=l.id and l.tipo='campanha'
    and j.user_id=uid and l.user_id=uid
    and j.status='aguardando' and j.execution_mode<>p_mode and j.api_handoff is null;
 end if;
 select jsonb_build_object('mode',mode,'paused',paused,'max_concurrency',max_concurrency) into result from apoiarcred_private.digimais_preferences where user_id=uid;
 return coalesce(result,'{"mode":"robot","paused":false,"max_concurrency":12}'::jsonb);
end $$;
notify pgrst,'reload schema';
commit;
