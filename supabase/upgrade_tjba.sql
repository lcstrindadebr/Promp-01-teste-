-- Additive TJBA integration: no ALTER/DROP/REPLACE of existing Digi+ objects.
create extension if not exists supabase_vault with schema vault;
create schema if not exists apoiarcred_private;
grant usage on schema apoiarcred_private to authenticated;
create table public.tjba_lotes (
 id uuid primary key default gen_random_uuid(),user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 nome text not null check(length(nome) between 1 and 160),tipo text not null check(tipo in ('individual','campanha')),
 servico text not null default 'tjba_margem' check(servico='tjba_margem'),created_at timestamptz not null default now()
);
create table public.tjba_jobs (
 id uuid primary key default gen_random_uuid(),lote_id uuid not null references public.tjba_lotes(id) on delete cascade,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 nome text not null default 'Cliente TJBA' check(length(nome) between 1 and 160),cpf text not null check(cpf ~ '^[0-9]{11}$'),
 telefone text not null default '' check(telefone='' or telefone ~ '^[0-9]{10,13}$'),
 servico text not null default 'tjba_margem' check(servico='tjba_margem'),
 tipo_higienizacao text not null default 'margem' check(tipo_higienizacao='margem'),provedor text not null default 'tjba' check(provedor='tjba'),
 status text not null default 'aguardando' check(status in ('aguardando','processando','concluida','nao_encontrado','erro','revisao')),
 progress integer not null default 0 check(progress between 0 and 100),stage text not null default 'Aguardando na fila',message text,
 matricula text,tipo_servidor text,situacao_atual text,emprestimo_disponivel numeric(14,2),cartao_disponivel numeric(14,2),
 tjba_status text,resultado_tjba jsonb,created_at timestamptz not null default now(),consultado_em timestamptz,locked_at timestamptz,attempts integer not null default 0
);
create index tjba_lotes_owner on public.tjba_lotes(user_id,created_at desc);
create index tjba_jobs_owner on public.tjba_jobs(user_id,created_at desc);
create index tjba_jobs_lote on public.tjba_jobs(lote_id);
create index tjba_jobs_queue on public.tjba_jobs(created_at) where status='aguardando';
alter table public.tjba_lotes enable row level security;
alter table public.tjba_jobs enable row level security;
revoke all on public.tjba_lotes,public.tjba_jobs from public,anon,authenticated;
grant select,insert,delete on public.tjba_lotes to authenticated;
grant select,delete on public.tjba_jobs to authenticated;
grant insert(lote_id,user_id,nome,cpf,telefone) on public.tjba_jobs to authenticated;
grant all on public.tjba_lotes,public.tjba_jobs to service_role;
create policy tjba_lotes_read on public.tjba_lotes for select to authenticated using(user_id=(select auth.uid()));
create policy tjba_lotes_insert on public.tjba_lotes for insert to authenticated with check(user_id=(select auth.uid()));
create policy tjba_lotes_delete on public.tjba_lotes for delete to authenticated using(user_id=(select auth.uid()));
create policy tjba_jobs_read on public.tjba_jobs for select to authenticated using(user_id=(select auth.uid()));
create policy tjba_jobs_delete on public.tjba_jobs for delete to authenticated using(user_id=(select auth.uid()));
create policy tjba_jobs_insert on public.tjba_jobs for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.tjba_lotes l where l.id=lote_id and l.user_id=(select auth.uid())));
create function public.create_tjba_campaign(p_nome text,p_items jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items) not between 1 and 1000 then raise exception 'Envie de 1 a 1.000 clientes.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.nome),''),'CPF '||x.cpf),x.cpf,coalesce(x.telefone,'') from jsonb_to_recordset(p_items) x(nome text,cpf text,telefone text);
 return cid;
end $$;
revoke all on function public.create_tjba_campaign(text,jsonb) from public,anon;
grant execute on function public.create_tjba_campaign(text,jsonb) to authenticated;
create function public.claim_tjba_job() returns setof public.tjba_jobs language sql security invoker set search_path='' as $$
 update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1 where id=(select id from public.tjba_jobs where status='aguardando' order by created_at for update skip locked limit 1) returning *;
$$;
revoke all on function public.claim_tjba_job() from public,anon,authenticated;
grant execute on function public.claim_tjba_job() to service_role;
create table public.consulta_tjba_historico (
 id uuid primary key default gen_random_uuid(),job_id uuid not null references public.tjba_jobs(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,created_at timestamptz not null default now(),resultado jsonb not null
);
create index tjba_historico_owner_job on public.consulta_tjba_historico(user_id,job_id,created_at desc);
create index tjba_historico_job on public.consulta_tjba_historico(job_id);
alter table public.consulta_tjba_historico enable row level security;
revoke all on public.consulta_tjba_historico from public,anon,authenticated;
grant select on public.consulta_tjba_historico to authenticated;
grant all on public.consulta_tjba_historico to service_role;
create policy tjba_history_read on public.consulta_tjba_historico for select to authenticated using(user_id=(select auth.uid()));
create function apoiarcred_private.tjba_history() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.resultado_tjba is not null and (new.resultado_tjba is distinct from old.resultado_tjba or new.consultado_em is distinct from old.consultado_em) then insert into public.consulta_tjba_historico(job_id,user_id,resultado) values(new.id,new.user_id,new.resultado_tjba);end if;return new;
end $$;
revoke all on function apoiarcred_private.tjba_history() from public,anon,authenticated;
create trigger save_tjba_history after update on public.tjba_jobs for each row execute function apoiarcred_private.tjba_history();
-- Encrypted password in Vault; no exposed table contains portal secrets.
create table if not exists apoiarcred_private.tjba_credentials (
 user_id uuid primary key references auth.users(id) on delete cascade,username text not null,
 secret_id uuid not null,enabled boolean not null default false,updated_at timestamptz not null default now()
);
alter table apoiarcred_private.tjba_credentials enable row level security;
revoke all on apoiarcred_private.tjba_credentials from public,anon,authenticated,service_role;
create or replace function apoiarcred_private.save_tjba_credentials(p_username text,p_password text,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); sid uuid; oldname text;
begin
 if uid is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_username is null or length(btrim(p_username)) not between 1 and 160 or length(coalesce(p_password,''))>512 then raise exception 'Usuário ou senha inválidos.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 select secret_id,username into sid,oldname from apoiarcred_private.tjba_credentials where user_id=uid;
 if coalesce(p_password,'')='' and (sid is null or oldname<>btrim(p_username)) then raise exception 'Informe a senha para esse usuário.';end if;
 if sid is null then sid=vault.create_secret(p_password,'apoiarcred-tjba-'||uid::text);
 elsif coalesce(p_password,'')<>'' then perform vault.update_secret(sid,p_password);end if;
 insert into apoiarcred_private.tjba_credentials(user_id,username,secret_id,enabled,updated_at) values(uid,btrim(p_username),sid,coalesce(p_enabled,false),clock_timestamp())
 on conflict(user_id) do update set username=excluded.username,enabled=excluded.enabled,updated_at=excluded.updated_at;
end $$;
create or replace function apoiarcred_private.tjba_credentials_status() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 select jsonb_build_object('configured',true,'username',username,'enabled',enabled,'updated_at',updated_at) into result from apoiarcred_private.tjba_credentials where user_id=auth.uid();
 return coalesce(result,'{"configured":false,"enabled":false}'::jsonb);
end $$;
create or replace function apoiarcred_private.get_tjba_credentials(p_user_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise insufficient_privilege using message='Acesso exclusivo do robô.';end if;
 return (select jsonb_build_object('username',c.username,'password',v.decrypted_secret,'enabled',c.enabled,'revision',c.updated_at) from apoiarcred_private.tjba_credentials c join vault.decrypted_secrets v on v.id=c.secret_id where c.user_id=p_user_id);
end $$;
revoke all on function apoiarcred_private.save_tjba_credentials(text,text,boolean),apoiarcred_private.tjba_credentials_status(),apoiarcred_private.get_tjba_credentials(uuid) from public,anon,authenticated,service_role;
grant usage on schema apoiarcred_private to service_role;
grant execute on function apoiarcred_private.save_tjba_credentials(text,text,boolean),apoiarcred_private.tjba_credentials_status() to authenticated;
grant execute on function apoiarcred_private.get_tjba_credentials(uuid) to service_role;
create or replace function public.save_tjba_credentials(p_username text,p_password text,p_enabled boolean) returns void language sql security invoker set search_path='' as $$select apoiarcred_private.save_tjba_credentials(p_username,p_password,p_enabled);$$;
create or replace function public.tjba_credentials_status() returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.tjba_credentials_status();$$;
create or replace function public.get_tjba_credentials(p_user_id uuid) returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.get_tjba_credentials(p_user_id);$$;
revoke all on function public.save_tjba_credentials(text,text,boolean),public.tjba_credentials_status(),public.get_tjba_credentials(uuid) from public,anon,authenticated,service_role;
grant execute on function public.save_tjba_credentials(text,text,boolean),public.tjba_credentials_status() to authenticated;
grant execute on function public.get_tjba_credentials(uuid) to service_role;

create function apoiarcred_private.retry_tjba_campaign(p_campaign_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); n integer;
begin
 if uid is null or not exists(select 1 from public.tjba_lotes where id=p_campaign_id and user_id=uid and tipo='campanha') then raise insufficient_privilege using message='Campanha não disponível para esta conta.';end if;
 update public.tjba_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,matricula=null,tipo_servidor=null,situacao_atual=null,emprestimo_disponivel=null,cartao_disponivel=null,tjba_status=null,resultado_tjba=null where lote_id=p_campaign_id and user_id=uid and status in ('erro','revisao');get diagnostics n=row_count;return n;
end $$;
revoke all on function apoiarcred_private.retry_tjba_campaign(uuid) from public,anon;
grant execute on function apoiarcred_private.retry_tjba_campaign(uuid) to authenticated;
create function public.retry_tjba_campaign(p_campaign_id uuid) returns integer language sql security invoker set search_path='' as $$select apoiarcred_private.retry_tjba_campaign(p_campaign_id);$$;
revoke all on function public.retry_tjba_campaign(uuid) from public,anon;
grant execute on function public.retry_tjba_campaign(uuid) to authenticated;
notify pgrst,'reload schema';
