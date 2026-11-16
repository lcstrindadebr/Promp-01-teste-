#!/usr/bin/env bash
# Builds a throwaway database from the repository schema and runs every tests/*_database.sql.
# Usage: PGHOST=... PGPORT=... PGUSER=postgres tests/sql/run.sh   (needs psql and a superuser)
set -euo pipefail
cd "$(dirname "$0")/../.."
DB=${TEST_DATABASE:-apoiarcred_test}
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
P=(psql -v ON_ERROR_STOP=1 -q -d "$DB")
"${P[@]}" -f tests/sql/supabase_stub.sql
# schema.sql is the cumulative schema; the vault extension is replaced by the stub.
sed 's/^create extension if not exists supabase_vault with schema vault.*$/-- vault provided by the stub/' supabase/schema.sql | "${P[@]}" >/dev/null
# Upgrades applied in production after schema.sql was last regenerated, in order.
for upgrade in upgrade_crm_campanhas_reuso upgrade_amigoz_reuso_status upgrade_amigoz_campanhas_avulsas \
  upgrade_digimais_campaign_batches upgrade_painel_sync_pro upgrade_api_campanha_convenio \
  upgrade_crm_preservar_etapa_importacao upgrade_fila_resiliente upgrade_tenants_foundation upgrade_tenants_access upgrade_tenants_crm upgrade_tenants_users; do
  "${P[@]}" -f "supabase/$upgrade.sql" >/dev/null
done
status=0
for test in ${ONLY_TESTS:-tests/*_database.sql}; do
  if "${P[@]}" -f "$test" >/dev/null 2>"/tmp/$(basename "$test").err"; then echo "PASS $(basename "$test")"
  else echo "FAIL $(basename "$test"): $(grep -m1 ERROR "/tmp/$(basename "$test").err")"; status=1; fi
done
exit $status
