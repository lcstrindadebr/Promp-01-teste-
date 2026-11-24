-- Início: total de clientes cadastrados no CRM e oportunidades por situação.
-- Mesmo escopo de painel_resumo: a empresa inteira para quem vê a empresa, senão só o próprio usuário.
-- O painel chama ao abrir o Início e no máximo a cada minuto (a contagem percorre o índice da empresa).

begin;

create or replace function public.painel_crm_totais()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tenant uuid; me uuid=auth.uid(); all_company boolean; clientes bigint; ops jsonb;
begin
 if me is null then raise insufficient_privilege;end if;
 tenant:=apoiarcred_private.current_tenant();
 all_company:=apoiarcred_private.current_sees_company();
 select count(*) into clientes from public.crm_cadastros c
  where c.tenant_id=tenant and (all_company or c.user_id=me);
 select jsonb_build_object(
   'abertas',count(*) filter (where s.tipo not in ('ganho','perdido')),
   'ganhas',count(*) filter (where s.tipo='ganho'),
   'perdidas',count(*) filter (where s.tipo='perdido'),
   'total',count(*)) into ops
 from (select coalesce(e.tipo,case when o.etapa in ('ganho','perdido') then o.etapa else 'aberta' end) tipo
   from public.crm_oportunidades o left join public.crm_etapas e on e.id=o.etapa_id
   where o.tenant_id=tenant and (all_company or o.user_id=me)) s;
 return jsonb_build_object('clientes',clientes,'oportunidades',ops);
end $$;
revoke all on function public.painel_crm_totais() from public,anon;
grant execute on function public.painel_crm_totais() to authenticated;

commit;
