-- Preserve existing lots; old CSV imports become campaigns.
alter table public.consulta_lotes add column if not exists tipo text not null default 'individual' check(tipo in ('individual','campanha'));
update public.consulta_lotes set tipo='campanha' where tipo='individual' and nome like 'Importação CSV%';

-- One transaction: an invalid row cannot leave an empty campaign behind.
create or replace function public.create_consulta_campaign(p_nome text,p_items jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare campaign_id uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe um nome de campanha com até 160 caracteres.'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.'; end if;
 if jsonb_array_length(p_items) not between 1 and 1000 then raise exception 'Envie entre 1 e 1000 clientes.'; end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados na campanha.'; end if;
 insert into public.consulta_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into campaign_id;
 insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone)
 select campaign_id,auth.uid(),x.nome,x.cpf,x.telefone from jsonb_to_recordset(p_items) as x(nome text,cpf text,telefone text);
 return campaign_id;
end $$;
revoke all on function public.create_consulta_campaign(text,jsonb) from public,anon;
grant execute on function public.create_consulta_campaign(text,jsonb) to authenticated;

-- Narrow owner-scoped operation; authenticated users retain NO direct output UPDATE privilege.
create schema if not exists apoiarcred_private;
revoke all on schema apoiarcred_private from public,anon;
grant usage on schema apoiarcred_private to authenticated;
create or replace function apoiarcred_private.retry_consulta_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare owner_id uuid := auth.uid(); retried integer;
begin
 if owner_id is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if not exists(select 1 from public.consulta_lotes where id=p_campaign_id and user_id=owner_id and tipo='campanha') then
  raise insufficient_privilege using message='Campanha não disponível para esta conta.';
 end if;
 update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,
  saldo_liquidacao=null,total_parcelas=null,valor_parcela=null,resultado_saldo=null,resultado_parcela=null,consultado_em=null,locked_at=null
 where lote_id=p_campaign_id and user_id=owner_id and status in ('erro','revisao');
 get diagnostics retried = row_count;
 return retried;
end $$;
revoke all on function apoiarcred_private.retry_consulta_campaign(uuid) from public,anon;
grant execute on function apoiarcred_private.retry_consulta_campaign(uuid) to authenticated;
-- Only this invoker entry point is exposed by the Data API.
create or replace function public.retry_consulta_campaign(p_campaign_id uuid)
returns integer language sql security invoker set search_path='' as $$
 select apoiarcred_private.retry_consulta_campaign(p_campaign_id);
$$;
revoke all on function public.retry_consulta_campaign(uuid) from public,anon;
grant execute on function public.retry_consulta_campaign(uuid) to authenticated;
notify pgrst,'reload schema';
