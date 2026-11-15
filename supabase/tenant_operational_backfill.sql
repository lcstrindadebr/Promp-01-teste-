-- Aplicar após tenant_foundation.sql na mesma transação da ativação.
-- O vínculo original continua disponível para as rotinas legadas durante a migração.
do $migration$
declare table_name text;
begin
 foreach table_name in array array[
  'consulta_lotes','consulta_jobs','tjba_lotes','tjba_jobs','amigoz_jobs',
  'consulta_tjba_historico','crm_cadastros','crm_classificacoes',
  'crm_vinculos','crm_dados_cliente','crm_margens_vinculo','crm_etapas',
  'crm_oportunidades','crm_movimentacoes','crm_import_requests',
  'crm_exportacoes','crm_campanhas_reuso'
 ] loop
  execute format('alter table public.%I add column tenant_id uuid references apoiarcred_private.tenants(id)',table_name);
  execute format(
   'update public.%I r set tenant_id=t.id from apoiarcred_private.tenants t where t.legacy_owner_id=r.user_id',
   table_name);
  execute format('alter table public.%I alter column tenant_id set not null',table_name);
  execute format('create index %I on public.%I(tenant_id)',table_name||'_tenant_idx',table_name);
 end loop;
end
$migration$;
