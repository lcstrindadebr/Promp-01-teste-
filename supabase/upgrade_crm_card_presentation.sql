begin;
alter table public.crm_card_settings add column if not exists density text not null default 'comfortable' check(density in ('compact','comfortable'));
grant insert(density),update(density) on public.crm_card_settings to authenticated;
grant update(nome) on public.crm_oportunidades to authenticated;
notify pgrst,'reload schema';
commit;
