create table if not exists public.vps_monitoramento (
 id text primary key check(id='principal'),
 updated_at timestamptz not null,
 payload jsonb not null check(jsonb_typeof(payload)='object')
);
alter table public.vps_monitoramento enable row level security;
revoke all on public.vps_monitoramento from public,anon,authenticated;
grant select on public.vps_monitoramento to authenticated;
grant select,insert,update,delete on public.vps_monitoramento to service_role;
drop policy if exists monitor_read on public.vps_monitoramento;
create policy monitor_read on public.vps_monitoramento for select to authenticated using(true);
notify pgrst,'reload schema';
