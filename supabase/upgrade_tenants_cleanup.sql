-- Multi-tenant · etapa 6b: limpeza do modelo antigo de parceiros.
-- APLICAR SÓ DEPOIS de uma semana com o multi-tenant em produção sem diferenças.
-- Remove as permissões e cotas por parceiro (substituídas por empresa, teto e cota da empresa).
-- Para antes de apagar se alguma função ou view do banco ainda usar as tabelas antigas
-- (por exemplo, uma função que só exista na produção).

do $$
declare users text;
begin
 select string_agg(p.oid::regprocedure::text,', ') into users from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname not in ('pg_catalog','information_schema') and p.prosrc ~ '(partner_permissions|partner_daily_usage)';
 if users is not null then raise exception 'Ainda usam as tabelas antigas: %',users;end if;
 select string_agg(c.oid::regclass::text,', ') into users from pg_class c
 where c.relkind in ('v','m') and pg_get_viewdef(c.oid) ~ '(partner_permissions|partner_daily_usage)';
 if users is not null then raise exception 'Views ainda usam as tabelas antigas: %',users;end if;
end $$;

drop table apoiarcred_private.partner_daily_usage;
drop table apoiarcred_private.partner_permissions;
