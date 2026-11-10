begin;
alter table public.crm_oportunidades drop constraint if exists crm_oportunidades_etapa_check;
alter table public.crm_oportunidades add constraint crm_oportunidades_etapa_check
 check (etapa in ('novo','contato','simulacao','negociacao','exportada','ganho','perdido'));

create function public.crm_marcar_exportadas(p_itens jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare total integer;
begin
 if auth.uid() is null then raise insufficient_privilege; end if;
 update public.crm_oportunidades o set etapa='exportada'
 from jsonb_to_recordset(p_itens) as item(id uuid, etapa text)
 where o.id=item.id and o.user_id=auth.uid() and o.etapa=item.etapa
 and o.etapa in ('novo','contato','simulacao','negociacao');
 get diagnostics total=row_count;
 return total;
end $$;
revoke all on function public.crm_marcar_exportadas(jsonb) from public,anon;
grant execute on function public.crm_marcar_exportadas(jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
