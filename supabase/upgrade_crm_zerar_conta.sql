begin;

create or replace function apoiarcred_private.crm_reset_account(p_confirmation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  owner_id uuid := auth.uid();
  client_count integer;
  opportunity_count integer;
  job_count integer;
  count_tjba integer;
  lot_count integer;
  count_tjba_lots integer;
begin
  if owner_id is null or not exists (
    select 1 from apoiarcred_private.user_profiles
    where user_id=owner_id and role='admin' and active
    for share
  ) then raise exception 'Apenas administradores ativos podem zerar a própria conta.' using errcode='42501'; end if;
  if p_confirmation is distinct from 'ZERAR MINHA CONTA' then
    raise exception 'Digite ZERAR MINHA CONTA para confirmar.';
  end if;

  -- Avoid a race with queue claims, new jobs and webhook deliveries.
  begin
    lock table public.consulta_lotes, public.tjba_lotes, public.consulta_jobs, public.tjba_jobs,
      public.crm_cadastros, public.crm_oportunidades, public.crm_classificacoes,
      apoiarcred_private.webhook_deliveries, apoiarcred_private.api_idempotency
    in share row exclusive mode nowait;
  exception when lock_not_available then
    raise exception 'Há gravações em andamento. Aguarde alguns instantes e tente novamente.';
  end;
  if exists (select 1 from public.consulta_jobs where user_id=owner_id and status='processando')
    or exists (select 1 from public.tjba_jobs where user_id=owner_id and status='processando')
    or exists (
      select 1 from apoiarcred_private.webhook_deliveries d
      join apoiarcred_private.webhook_events e on e.id=d.event_id
      where e.user_id=owner_id and d.state='delivering' and d.locked_until>now()
    )
  then raise exception 'Aguarde as consultas e entregas de webhook em execução terminarem. Pause as campanhas antes de tentar novamente.'; end if;

  delete from public.crm_oportunidades where user_id=owner_id;
  get diagnostics opportunity_count=row_count;
  delete from public.consulta_jobs where user_id=owner_id;
  get diagnostics job_count=row_count;
  delete from public.tjba_jobs where user_id=owner_id;
  get diagnostics count_tjba=row_count;
  delete from public.consulta_lotes where user_id=owner_id;
  get diagnostics lot_count=row_count;
  delete from public.tjba_lotes where user_id=owner_id;
  get diagnostics count_tjba_lots=row_count;
  delete from public.crm_cadastros where user_id=owner_id;
  get diagnostics client_count=row_count;
  delete from apoiarcred_private.webhook_events where user_id=owner_id;
  delete from apoiarcred_private.webhook_campaign_dirty where user_id=owner_id;
  update apoiarcred_private.webhooks set active=false
    where user_id=owner_id and scope='campaign';

  -- Retain the request fingerprints for the existing replay window while
  -- removing cached payloads and preventing retries from recreating records.
  update apoiarcred_private.api_idempotency i
    set response=apoiarcred_private.api_error(410,'account_data_reset','Os registros desta operação foram apagados.')
    from apoiarcred_private.api_tokens t
    where i.token_id=t.id and t.user_id=owner_id;

  return jsonb_build_object('clientes',client_count,'oportunidades',opportunity_count,
    'consultas',job_count+count_tjba,'lotes',lot_count+count_tjba_lots);
end $$;
revoke all on function apoiarcred_private.crm_reset_account(text) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_reset_account(text) to authenticated;

create or replace function public.crm_reset_account(p_confirmation text)
returns jsonb language sql security invoker set search_path='' as $$
  select apoiarcred_private.crm_reset_account(p_confirmation);
$$;
revoke all on function public.crm_reset_account(text) from public,anon,authenticated;
grant execute on function public.crm_reset_account(text) to authenticated;

notify pgrst,'reload schema';
commit;
