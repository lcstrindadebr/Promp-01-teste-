-- Multi-tenant: consultas e campanhas do painel pela empresa.
-- painel_consultas_sync roda com as permissões de quem está logado (security invoker): as regras
-- de acesso já limitam à empresa e ao que cada papel vê. O filtro extra "criado por mim" fazia o
-- Gestor e o Administrador não verem as consultas dos colegas. Sai o filtro; entram índices por
-- empresa para a sincronização incremental continuar rápida.

create index if not exists consulta_jobs_painel_sync_empresa on public.consulta_jobs(tenant_id,sync_xid);
create index if not exists tjba_jobs_painel_sync_empresa on public.tjba_jobs(tenant_id,sync_xid);
create index if not exists consulta_lotes_painel_sync_empresa on public.consulta_lotes(tenant_id,sync_xid);
create index if not exists tjba_lotes_painel_sync_empresa on public.tjba_lotes(tenant_id,sync_xid);

do $$
declare def text=pg_get_functiondef('public.painel_consultas_sync(text,text,text)'::regprocedure); n integer;
begin
 n=(length(def)-length(replace(def,'where r.user_id=uid','')))/length('where r.user_id=uid');
 if n<>4 or position('from public.painel_exclusoes d where d.user_id=uid and previous is not null' in def)=0 then
  raise exception 'painel_consultas_sync mudou (% filtros); revise a migração',n;end if;
 def=replace(def,'where r.user_id=uid','where r.tenant_id=(select apoiarcred_private.current_tenant())');
 def=replace(def,'from public.painel_exclusoes d where d.user_id=uid and previous is not null',
  'from public.painel_exclusoes d where d.tenant_id=(select apoiarcred_private.current_tenant()) and previous is not null');
 execute def;
end $$;
