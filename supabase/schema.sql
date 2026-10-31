create table public.consulta_lotes (
id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
nome text not null, created_at timestamptz not null default now());
create index consulta_lotes_owner on public.consulta_lotes(user_id,created_at desc);
create table public.consulta_jobs (
id uuid primary key default gen_random_uuid(), lote_id uuid not null references public.consulta_lotes(id) on delete cascade,
user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
nome text not null check(length(nome) between 1 and 160),
cpf text not null check(cpf ~ '^[0-9]{11}$'), telefone text not null check(telefone ~ '^[0-9]{10,13}$'),
progress integer not null default 0 check(progress between 0 and 100),
stage text not null default 'Aguardando na fila',
status text not null default 'aguardando' check(status in ('aguardando','processando','concluida','nao_localizado','nao_cliente','erro','revisao')),
valor_parcela numeric(14,2) check(valor_parcela >= 0), resultado_saldo jsonb, resultado_parcela jsonb, saldo_liquidacao numeric(14,2), total_parcelas integer, message text,
created_at timestamptz not null default now(), consultado_em timestamptz,
locked_at timestamptz, attempts integer not null default 0);
create index consulta_jobs_owner on public.consulta_jobs(user_id,created_at desc);
create index consulta_jobs_lote on public.consulta_jobs(lote_id);
create index consulta_jobs_queue on public.consulta_jobs(created_at) where status='aguardando';
alter table public.consulta_lotes enable row level security;
alter table public.consulta_jobs enable row level security;
revoke all on public.consulta_lotes,public.consulta_jobs from anon,authenticated;
grant select,insert on public.consulta_lotes to authenticated;
grant select on public.consulta_jobs to authenticated;
grant insert (lote_id,user_id,nome,cpf,telefone) on public.consulta_jobs to authenticated;
grant all on public.consulta_lotes,public.consulta_jobs to service_role;
create policy lotes_read on public.consulta_lotes for select to authenticated using(user_id=(select auth.uid()));
create policy lotes_insert on public.consulta_lotes for insert to authenticated with check(user_id=(select auth.uid()));
create policy jobs_read on public.consulta_jobs for select to authenticated using(user_id=(select auth.uid()));
create policy jobs_insert on public.consulta_jobs for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.consulta_lotes l where l.id=lote_id and l.user_id=(select auth.uid())));
create function public.claim_consulta_job() returns setof public.consulta_jobs language sql security invoker set search_path='' as $$
update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1
where id=(select id from public.consulta_jobs where status='aguardando' order by created_at for update skip locked limit 1) returning *;
$$;
revoke all on function public.claim_consulta_job() from public,anon,authenticated;
grant execute on function public.claim_consulta_job() to service_role;

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
