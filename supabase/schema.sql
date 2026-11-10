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

-- Estimativa autorizada: CET, 96 pagamentos mensais; primeiro em um mês.
create table if not exists public.amigoz_comissoes (
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 taxa numeric(5,2) not null check(taxa in (3,3.25,3.5,3.75,3.98,4.5,4.8)),
 percentual numeric(7,4) check(percentual between 0 and 100),
 primary key(user_id,taxa)
);
alter table public.amigoz_comissoes enable row level security;
revoke all on public.amigoz_comissoes from anon,authenticated;
grant select,insert,update on public.amigoz_comissoes to authenticated;
drop policy if exists own_commissions on public.amigoz_comissoes;
create policy own_commissions on public.amigoz_comissoes for all to authenticated
 using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create table if not exists public.amigoz_simulacoes (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 job_id uuid not null references public.consulta_jobs(id) on delete cascade,
 created_at timestamptz not null default now(),
 resultado jsonb not null
);
create index if not exists amigoz_simulacoes_owner_job on public.amigoz_simulacoes(user_id,job_id,created_at desc);
create index if not exists amigoz_simulacoes_job on public.amigoz_simulacoes(job_id);
alter table public.amigoz_simulacoes enable row level security;
revoke all on public.amigoz_simulacoes from anon,authenticated;
grant select,insert on public.amigoz_simulacoes to authenticated;
drop policy if exists own_simulations on public.amigoz_simulacoes;
create policy own_simulations on public.amigoz_simulacoes for all to authenticated
 using ((select auth.uid())=user_id)
 with check ((select auth.uid())=user_id and exists(select 1 from public.consulta_jobs j where j.id=job_id and j.user_id=(select auth.uid())));
create or replace function public.simular_amigoz(p_job_id uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare j public.consulta_jobs; t record; pct numeric; liquido numeric; troco numeric; resultados jsonb='[]'; saida jsonb;
begin
 if auth.uid() is null then raise exception 'Entre na sua conta.'; end if;
 select * into j from public.consulta_jobs where id=p_job_id and user_id=auth.uid();
 if not found then raise exception 'Consulta não encontrada.'; end if;
 if j.status in ('aguardando','processando','nao_cliente','nao_localizado') or coalesce(j.saldo_liquidacao,0)<=0 or coalesce(j.valor_parcela,0)<=0 then
 raise exception 'Aguarde saldo e parcela positivos da mesma consulta.'; end if;
 for t in select * from (values (3.00,3.63),(3.25,3.88),(3.50,4.13),(3.75,4.38),(3.98,4.61),(4.50,5.13),(4.80,5.43)) as taxas(taxa,cet) loop
 select percentual into pct from public.amigoz_comissoes where user_id=auth.uid() and taxa=t.taxa;
 liquido=round(j.valor_parcela*(1-power(1+t.cet/100,-96))/(t.cet/100),2);
 troco=liquido-j.saldo_liquidacao;
 resultados=resultados||jsonb_build_array(jsonb_build_object('taxa',t.taxa,'cet',t.cet,'limite',null,'liberado',liquido,'quitacao',j.saldo_liquidacao,'troco',case when troco>=0 then troco else null end,'insuficiente',troco<0,'percentual',pct,'comissao',case when troco>=0 and pct is not null then round((j.saldo_liquidacao+troco)*pct/100,2) else null end));
 end loop;
 saida=jsonb_build_object('job_id',j.id,'saldo',j.saldo_liquidacao,'parcela',j.valor_parcela,'prazo',96,'primeiro_vencimento_meses',1,'metodo','estimativa_cet_mensal_v1','versao_condicoes','2026-10-31','data_simulacao',now(),'tabelas',resultados,'limite_pre_aprovado',null,'custos_individuais',null);
 insert into public.amigoz_simulacoes(job_id,resultado) values(j.id,saida);
 return saida;
end $$;
revoke all on function public.simular_amigoz(uuid) from public,anon;
grant execute on function public.simular_amigoz(uuid) to authenticated;
notify pgrst,'reload schema';

-- Owner-scoped deletion. Foreign keys cascade jobs and saved simulations.
grant delete on public.consulta_jobs,public.consulta_lotes to authenticated;
drop policy if exists jobs_delete on public.consulta_jobs;
create policy jobs_delete on public.consulta_jobs for delete to authenticated using(user_id=(select auth.uid()));
drop policy if exists lotes_delete on public.consulta_lotes;
create policy lotes_delete on public.consulta_lotes for delete to authenticated using(user_id=(select auth.uid()));
notify pgrst,'reload schema';

-- Existing data belongs to the only implemented service.
alter table public.consulta_lotes add column if not exists servico text not null default 'digimais_saldo_parcela' check(servico in ('digimais_saldo_parcela'));
alter table public.consulta_jobs add column if not exists servico text not null default 'digimais_saldo_parcela' check(servico in ('digimais_saldo_parcela'));
grant insert(servico) on public.consulta_jobs to authenticated;
-- Keep the legacy two-argument RPC compatible with installed clients.
create or replace function public.create_consulta_campaign(p_nome text,p_items jsonb,p_servico text)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
 if p_servico is distinct from 'digimais_saldo_parcela' then raise exception 'Este serviço de higienização ainda não está disponível.'; end if;
 return public.create_consulta_campaign(p_nome,p_items);
end $$;
revoke all on function public.create_consulta_campaign(text,jsonb,text) from public,anon;
grant execute on function public.create_consulta_campaign(text,jsonb,text) to authenticated;
create or replace function public.claim_consulta_job() returns setof public.consulta_jobs language sql security invoker set search_path='' as $$
update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1
where id=(select id from public.consulta_jobs where status='aguardando' and servico='digimais_saldo_parcela' order by created_at for update skip locked limit 1) returning *;
$$;
revoke all on function public.claim_consulta_job() from public,anon,authenticated;
grant execute on function public.claim_consulta_job() to service_role;
notify pgrst,'reload schema';

create table if not exists public.vps_monitoramento (
 id text primary key check(id='principal'),
 updated_at timestamptz not null,
 payload jsonb not null check(jsonb_typeof(payload)='object')
);
alter table public.vps_monitoramento enable row level security;
revoke all on public.vps_monitoramento from public,anon,authenticated;
grant select on public.vps_monitoramento to authenticated;
grant select,insert,update,delete on public.vps_monitoramento to service_role;
drop policy if exists monitor_read on public.vps_monitoramento;
create policy monitor_read on public.vps_monitoramento for select to authenticated using(true);
notify pgrst,'reload schema';

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

-- Explicit default deny; access stays exclusively inside owner-scoped private functions.
create policy tjba_credentials_no_direct_access on apoiarcred_private.tjba_credentials for all to public using(false) with check(false);
create function apoiarcred_private.cleanup_tjba_secret() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from vault.secrets where id=old.secret_id;
 return old;
end $$;
revoke all on function apoiarcred_private.cleanup_tjba_secret() from public,anon,authenticated,service_role;
create trigger cleanup_tjba_secret after delete on apoiarcred_private.tjba_credentials for each row execute function apoiarcred_private.cleanup_tjba_secret();

-- Administrative credential inspection and actual password change tracking.
alter table apoiarcred_private.tjba_credentials add column if not exists password_version bigint not null default 0;
alter table apoiarcred_private.tjba_credentials add column if not exists password_changed_at timestamptz;
create or replace function apoiarcred_private.save_tjba_credentials(p_username text,p_password text,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); sid uuid; oldname text; changed boolean=false;
begin
 if uid is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_username is null or length(btrim(p_username)) not between 1 and 160 or length(coalesce(p_password,''))>512 then raise exception 'Usuário ou senha inválidos.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 select secret_id,username into sid,oldname from apoiarcred_private.tjba_credentials where user_id=uid;
 if coalesce(p_password,'')='' and (sid is null or oldname<>btrim(p_username)) then raise exception 'Informe a senha para esse usuário.';end if;
 if sid is not null and coalesce(p_password,'')<>'' then
 select decrypted_secret is distinct from p_password into changed from vault.decrypted_secrets where id=sid;
 if not found then raise exception 'Segredo TJBA não localizado.';end if;
 end if;
 if sid is null then changed=true;sid=vault.create_secret(p_password,'apoiarcred-tjba-'||uid::text);
 elsif coalesce(p_password,'')<>'' then perform vault.update_secret(sid,p_password);end if;
 insert into apoiarcred_private.tjba_credentials(user_id,username,secret_id,enabled,updated_at,password_version,password_changed_at) values(uid,btrim(p_username),sid,coalesce(p_enabled,false),clock_timestamp(),1,clock_timestamp())
 on conflict(user_id) do update set username=excluded.username,enabled=excluded.enabled,updated_at=excluded.updated_at,
 password_version=apoiarcred_private.tjba_credentials.password_version+case when changed then 1 else 0 end,
 password_changed_at=case when changed then clock_timestamp() else apoiarcred_private.tjba_credentials.password_changed_at end;
end $$;
create or replace function apoiarcred_private.tjba_credentials_status() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 select jsonb_build_object('configured',true,'username',username,'enabled',enabled,'updated_at',updated_at,'password_version',password_version,'password_changed_at',password_changed_at) into result from apoiarcred_private.tjba_credentials where user_id=auth.uid();
 return coalesce(result,'{"configured":false,"enabled":false}'::jsonb);
end $$;

create or replace view apoiarcred_private.tjba_credentials_admin with (security_invoker=true) as
select c.user_id,c.username as login,v.decrypted_secret as senha,c.enabled,
c.updated_at as configuracao_salva_em,c.password_version as versao_senha,
c.password_changed_at as senha_alterada_em
from apoiarcred_private.tjba_credentials c join vault.decrypted_secrets v on v.id=c.secret_id;
revoke all on apoiarcred_private.tjba_credentials_admin from public,anon,authenticated,service_role;

-- Five owner-scoped ConsigX agreements.
alter table public.tjba_lotes add column convenio text not null default 'tjba' check(convenio in ('tjba','dpeba','embasa','saeb','suprev'));
alter table public.tjba_jobs add column convenio text not null default 'tjba' check(convenio in ('tjba','dpeba','embasa','saeb','suprev'));
create function apoiarcred_private.assign_consigx_convenio() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 select l.convenio into new.convenio from public.tjba_lotes l where l.id=new.lote_id and l.user_id=new.user_id;
 if new.convenio is null then raise exception 'Campanha ou proprietário inválido.';end if;
 return new;
end $$;
revoke all on function apoiarcred_private.assign_consigx_convenio() from public,anon,authenticated,service_role;
create trigger assign_consigx_convenio before insert on public.tjba_jobs for each row execute function apoiarcred_private.assign_consigx_convenio();
create function public.create_consigx_campaign(p_nome text,p_items jsonb,p_convenio text) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items) not between 1 and 1000 then raise exception 'Envie de 1 a 1.000 clientes.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo,convenio) values(btrim(p_nome),'campanha',p_convenio) returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.nome),''),'CPF '||x.cpf),x.cpf,coalesce(x.telefone,'') from jsonb_to_recordset(p_items) x(nome text,cpf text,telefone text);
 return cid;
end $$;
revoke all on function public.create_consigx_campaign(text,jsonb,text) from public,anon;
grant execute on function public.create_consigx_campaign(text,jsonb,text) to authenticated;

-- One CPF per campaign/lot, including direct insert paths. Existing jobs are retained.
create unique index consulta_jobs_lote_cpf_unique on public.consulta_jobs(lote_id,cpf);

create table apoiarcred_private.queue_maintenance(id boolean primary key default true check(id),token uuid,paused_until timestamptz);
insert into apoiarcred_private.queue_maintenance(id) values(true);
alter table apoiarcred_private.queue_maintenance enable row level security;
revoke all on apoiarcred_private.queue_maintenance from public,anon,authenticated;
grant usage on schema apoiarcred_private to service_role;
grant select,update on apoiarcred_private.queue_maintenance to service_role;
create policy queue_maintenance_service on apoiarcred_private.queue_maintenance for all to service_role using(true) with check(true);
create function public.consulta_queue_maintenance(p_token uuid,p_release boolean default false) returns integer language plpgsql security invoker set search_path='' as $$
declare current_token uuid; until_time timestamptz; active integer;
begin
 select token,paused_until into current_token,until_time from apoiarcred_private.queue_maintenance where id for update;
 if current_token is not null and until_time>clock_timestamp() and current_token<>p_token then raise exception 'Outra manutenção da fila está ativa.';end if;
 if p_release then
  update apoiarcred_private.queue_maintenance set token=null,paused_until=null where id and token=p_token;return 0;
 end if;
 if p_token is null then raise exception 'Token de manutenção obrigatório.';end if;
 update apoiarcred_private.queue_maintenance set token=p_token,paused_until=clock_timestamp()+interval '30 minutes' where id;
 select (select count(*) from public.consulta_jobs where status='processando')+(select count(*) from public.tjba_jobs where status='processando') into active;
 return active;
end $$;
revoke all on function public.consulta_queue_maintenance(uuid,boolean) from public,anon,authenticated;
grant execute on function public.consulta_queue_maintenance(uuid,boolean) to service_role;
create or replace function public.claim_consulta_job() returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp() for share;
 if found then return;end if;
 -- Always hold the guard through reservation, even while unpaused.
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1 where id=(select id from public.consulta_jobs where status='aguardando' and servico='digimais_saldo_parcela' order by created_at,id for update skip locked limit 1) returning *;
end $$;
create or replace function public.claim_tjba_job() returns setof public.tjba_jobs language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1 where id=(select id from public.tjba_jobs where status='aguardando' order by created_at,id for update skip locked limit 1) returning *;
end $$;

alter table public.consulta_lotes add column paused boolean not null default false;
alter table public.consulta_jobs add column queue_order bigint generated always as identity;
create index consulta_jobs_lot_order on public.consulta_jobs(lote_id,queue_order);
alter table public.tjba_lotes add column paused boolean not null default false;
alter table public.tjba_jobs add column queue_order bigint generated always as identity;
create index tjba_jobs_lot_order on public.tjba_jobs(lote_id,queue_order);
create function apoiarcred_private.set_campaign_paused(p_campaign_id uuid,p_service text,p_paused boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or p_paused is null then raise insufficient_privilege;end if;
 if p_service='digimais_saldo_parcela' then
  update public.consulta_lotes set paused=p_paused where id=p_campaign_id and user_id=auth.uid() and tipo='campanha';
 elsif p_service='tjba_margem' then
  update public.tjba_lotes set paused=p_paused where id=p_campaign_id and user_id=auth.uid() and tipo='campanha';
 else raise exception 'Serviço inválido.';end if;
 if not found then raise insufficient_privilege using message='Campanha não encontrada na sua conta.';end if;
end $$;
revoke all on function apoiarcred_private.set_campaign_paused(uuid,text,boolean) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.set_campaign_paused(uuid,text,boolean) to authenticated;
create function public.set_campaign_paused(p_campaign_id uuid,p_service text,p_paused boolean) returns void language sql security invoker set search_path='' as $$select apoiarcred_private.set_campaign_paused(p_campaign_id,p_service,p_paused);$$;
revoke all on function public.set_campaign_paused(uuid,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.set_campaign_paused(uuid,text,boolean) to authenticated;
create or replace function public.claim_consulta_job() returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando'))
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1) returning *;
end $$;
create or replace function public.claim_tjba_job() returns setof public.tjba_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.tjba_lotes l
 where not l.paused and exists(select 1 from public.tjba_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando'))
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1
 where id=(select j.id from public.tjba_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1) returning *;
end $$;

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
 select campaign_id,auth.uid(),x.item->>'nome',x.item->>'cpf',x.item->>'telefone' from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return campaign_id;
end $$;

create or replace function public.create_consigx_campaign(p_nome text,p_items jsonb,p_convenio text) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items) not between 1 and 1000 then raise exception 'Envie de 1 a 1.000 clientes.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo,convenio) values(btrim(p_nome),'campanha',p_convenio) returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.item->>'nome'),''),'CPF '||(x.item->>'cpf')),x.item->>'cpf',coalesce(x.item->>'telefone','') from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return cid;
end $$;

create or replace function apoiarcred_private.amigoz_price(p_margem numeric,p_taxa numeric,p_prazo integer,p_quitacao numeric,p_condicoes jsonb default '{}',p_comissao numeric default null) returns jsonb language plpgsql immutable set search_path='' as $$
declare i numeric; fator numeric; capacidade numeric; financiado numeric; liquido numeric; encargos numeric; fixo numeric=0; percentual numeric=0; teto numeric; parcela numeric; troco numeric; modo text; tipo_teto text; resultado jsonb;
begin
 if p_margem is null or p_margem<0 or p_taxa is null or p_taxa<0 or p_prazo is null or p_prazo not between 1 and 600 or p_quitacao is null or p_quitacao<0 or jsonb_typeof(p_condicoes)<>'object' or p_condicoes is null or p_comissao<0 or p_comissao>100 then raise exception 'Margem, taxa, prazo, quitação ou comissão inválidos.';end if;
 if p_margem::text in ('NaN','Infinity') or p_taxa::text in ('NaN','Infinity') or p_quitacao::text in ('NaN','Infinity') then raise exception 'Use valores finitos.';end if;
 i=p_taxa/100;
 if coalesce(p_condicoes->>'tipo_taxa','mensal')='anual_efetiva' then i=power(1+i,1::numeric/12)-1;
 elsif coalesce(p_condicoes->>'tipo_taxa','mensal')<>'mensal' then raise exception 'Tipo de taxa inválido.';end if;
 fator=case when i=0 then p_prazo else (1-power(1+i,-p_prazo))/i end;
 capacidade=floor(floor(p_margem*100)/100*fator*100)/100;
 modo=coalesce(p_condicoes->>'encargos_modo','nao_informados');
 teto=(p_condicoes->>'teto')::numeric;tipo_teto=coalesce(p_condicoes->>'tipo_teto','liquido');
 if teto is not null and (teto<0 or teto::text in ('NaN','Infinity')) then raise exception 'Teto inválido.';end if;
 if tipo_teto not in ('liquido','financiado') then raise exception 'Defina se o teto é líquido ou financiado.';end if;
 resultado=jsonb_build_object('taxa',p_taxa,'taxa_mensal',i*100,'prazo',p_prazo,'capacidade_financiada',capacidade,'quitacao',p_quitacao,'percentual',p_comissao,'condicoes',p_condicoes);
 if modo='nao_informados' then return resultado||jsonb_build_object('limite',null,'troco',null,'comissao',null,'insuficiente',false,'pendente_encargos',true,'observacao','Informe os encargos desta proposta para calcular limite líquido e troco.');end if;
 if modo='total_informado' then fixo=(p_condicoes->>'encargos_total')::numeric;
 elsif modo='percentual_e_fixo' then fixo=(p_condicoes->>'despesa_fixa')::numeric;percentual=(p_condicoes->>'encargos_percentual')::numeric/100;
 elsif modo<>'sem_encargos' then raise exception 'Modo de encargos inválido.';end if;
 if fixo is null or percentual is null or fixo<0 or percentual<0 or fixo::text in ('NaN','Infinity') or percentual::text in ('NaN','Infinity') then raise exception 'Encargos inválidos.';end if;
 financiado=case when teto is not null and tipo_teto='financiado' then least(capacidade,teto) else capacidade end;
 if financiado<fixo then return resultado||jsonb_build_object('limite',null,'troco',null,'comissao',null,'insuficiente',true,'pendente_encargos',false,'observacao','A capacidade financiada não cobre os encargos informados.');end if;
 liquido=floor((financiado-fixo)/(1+percentual)*100)/100;
 if teto is not null and tipo_teto='liquido' then liquido=least(liquido,floor(teto*100)/100);end if;
 encargos=round(fixo+liquido*percentual,2);financiado=liquido+encargos;
 parcela=round(financiado/fator,2);
 while parcela>p_margem or financiado>capacidade or (teto is not null and tipo_teto='financiado' and financiado>teto) loop
  liquido=liquido-.01;
  if liquido<0 then raise exception 'Não há limite compatível com a margem.';end if;
  encargos=round(fixo+liquido*percentual,2);financiado=liquido+encargos;parcela=round(financiado/fator,2);
 end loop;
 troco=liquido-p_quitacao;
 return resultado||jsonb_build_object('limite',liquido,'liberado',liquido,'troco',case when troco>=0 then troco else null end,'insuficiente',troco<0,'pendente_encargos',false,'encargos_financiados',encargos,'total_financiado',financiado,'parcela_conferida',parcela,'comissao',case when troco>=0 and p_comissao is not null then round((p_quitacao+troco)*p_comissao/100,2) else null end);
end $$;
revoke all on function apoiarcred_private.amigoz_price(numeric,numeric,integer,numeric,jsonb,numeric) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.amigoz_price(numeric,numeric,integer,numeric,jsonb,numeric) to authenticated;
create or replace function public.simular_amigoz_price(p_job_id uuid,p_prazo integer default 96,p_condicoes jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.consulta_jobs; v_taxa numeric; pct numeric; cond jsonb; parcela_simulada numeric; resultados jsonb='[]';saida jsonb;
begin
 if auth.uid() is null then raise exception 'Entre na sua conta.';end if;
 if p_prazo is null or p_prazo not between 1 and 600 or p_condicoes is null or jsonb_typeof(p_condicoes)<>'object' then raise exception 'Prazo ou condições inválidos.';end if;
 select * into j from public.consulta_jobs where id=p_job_id and user_id=auth.uid();
 if not found then raise exception 'Consulta não encontrada.';end if;
 if j.status in ('aguardando','processando','nao_cliente','nao_localizado') or coalesce(j.saldo_liquidacao,0)<=0 or coalesce(j.valor_parcela,0)<=0 then raise exception 'Aguarde saldo e parcela positivos da mesma consulta.';end if;
 parcela_simulada=coalesce((p_condicoes->>'_parcela_simulada')::numeric,j.valor_parcela);
 if parcela_simulada<=0 or parcela_simulada::text in ('NaN','Infinity','-Infinity') then raise exception 'Parcela simulada inválida.';end if;
 foreach v_taxa in array array[3,3.25,3.5,3.75,3.98,4.5,4.8]::numeric[] loop
  select percentual into pct from public.amigoz_comissoes where user_id=auth.uid() and amigoz_comissoes.taxa=v_taxa;
  cond=coalesce(p_condicoes->v_taxa::text,'{}'::jsonb);
  -- These seven tables have contractual monthly interest rates.
  cond=cond||jsonb_build_object('tipo_taxa','mensal');
  resultados=resultados||jsonb_build_array(apoiarcred_private.amigoz_price(parcela_simulada,v_taxa,p_prazo,j.saldo_liquidacao,cond,pct));
 end loop;
 saida=jsonb_build_object('job_id',j.id,'saldo',j.saldo_liquidacao,'parcela',j.valor_parcela,'parcela_simulada',parcela_simulada,'margem_adicional',greatest(parcela_simulada-j.valor_parcela,0),'prazo',p_prazo,'primeiro_vencimento_meses',1,'metodo','price_juros_contratuais_encargos_separados_v2','data_simulacao',now(),'tabelas',resultados);
 insert into public.amigoz_simulacoes(job_id,resultado) values(j.id,saida);return saida;
end $$;
revoke all on function public.simular_amigoz_price(uuid,integer,jsonb) from public,anon;
grant execute on function public.simular_amigoz_price(uuid,integer,jsonb) to authenticated;
create or replace function public.simular_amigoz(p_job_id uuid) returns jsonb language sql security invoker set search_path='' as $$select public.simular_amigoz_price(p_job_id,96,'{}'::jsonb);$$;

-- API v1: additive, owner-scoped, no changes to queue reservation or existing results.
alter table public.consulta_jobs add column if not exists referencia_externa text check(length(referencia_externa)<=160);
alter table public.tjba_jobs add column if not exists referencia_externa text check(length(referencia_externa)<=160);
create table apoiarcred_private.api_tokens(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 80),token_hash text unique not null,prefix text not null,
 scopes text[] not null,created_at timestamptz not null default now(),expires_at timestamptz,
 revoked_at timestamptz,last_used_at timestamptz,rate_window timestamptz,rate_count integer not null default 0
);
create index api_tokens_owner on apoiarcred_private.api_tokens(user_id);
create table apoiarcred_private.api_idempotency(
 token_id uuid not null references apoiarcred_private.api_tokens(id) on delete cascade,
 key text not null,fingerprint text not null,response jsonb not null,created_at timestamptz not null default now(),
 primary key(token_id,key)
);
alter table apoiarcred_private.api_tokens enable row level security;
alter table apoiarcred_private.api_idempotency enable row level security;
revoke all on apoiarcred_private.api_tokens,apoiarcred_private.api_idempotency from public,anon,authenticated;
grant usage on schema apoiarcred_private to service_role;
grant all on apoiarcred_private.api_tokens,apoiarcred_private.api_idempotency to service_role;
create policy api_tokens_service on apoiarcred_private.api_tokens for all to service_role using(true) with check(true);
create policy api_idempotency_service on apoiarcred_private.api_idempotency for all to service_role using(true) with check(true);
create function apoiarcred_private.manage_api_tokens(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); secret text; scopes text[]; expires timestamptz; result jsonb; tid uuid;
begin
 if uid is null then raise insufficient_privilege;end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'prefix',t.prefix,'scopes',t.scopes,'created_at',t.created_at,'expires_at',t.expires_at,'revoked_at',t.revoked_at,'last_used_at',t.last_used_at) order by t.created_at desc),'[]') into result from apoiarcred_private.api_tokens t where t.user_id=uid;return result;
 elsif p_action='revoke' then
  update apoiarcred_private.api_tokens set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=(p_input->>'id')::uuid and user_id=uid;
  if not found then raise insufficient_privilege;end if;return '{"revoked":true}';
 elsif p_action<>'create' then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 80 then raise exception 'Informe nome de até 80 caracteres.';end if;
 select coalesce(array_agg(distinct x),'{}') into scopes from jsonb_array_elements_text(p_input->'scopes') x;
 if cardinality(scopes)=0 or not scopes<@array['read','consultas:create','campanhas:write'] then raise exception 'Permissões inválidas.';end if;
 expires=nullif(p_input->>'expires_at','')::timestamptz;
 if expires is not null and (expires<=now() or expires>now()+interval '366 days') then raise exception 'Validade deve estar entre agora e um ano.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if (select count(*) from apoiarcred_private.api_tokens where user_id=uid and revoked_at is null and (expires_at is null or expires_at>now()))>=20 then raise exception 'Limite de 20 tokens ativos. Revogue um token antes.';end if;
 secret='apc_'||encode(extensions.gen_random_bytes(32),'hex');
 insert into apoiarcred_private.api_tokens(user_id,name,token_hash,prefix,scopes,expires_at)
 values(uid,btrim(p_input->>'name'),encode(extensions.digest(secret,'sha256'),'hex'),left(secret,12),scopes,expires) returning id into tid;
 return jsonb_build_object('id',tid,'token',secret,'expires_at',expires);
end $$;
revoke all on function apoiarcred_private.manage_api_tokens(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.manage_api_tokens(text,jsonb) to authenticated;
create function public.manage_api_tokens(p_action text,p_input jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.manage_api_tokens(p_action,p_input);$$;
revoke all on function public.manage_api_tokens(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.manage_api_tokens(text,jsonb) to authenticated;

create view apoiarcred_private.api_campaign_rows with(security_invoker=true) as
 select id,user_id,nome,tipo,servico,null::text convenio,paused,created_at from public.consulta_lotes
 union all select id,user_id,nome,tipo,servico,convenio,paused,created_at from public.tjba_lotes;
create view apoiarcred_private.api_lead_rows with(security_invoker=true) as
 select id,lote_id campanha_id,user_id,nome,cpf,telefone,servico,null::text convenio,status,progress,created_at,consultado_em,queue_order,referencia_externa,
 jsonb_build_object('saldo_liquidacao',saldo_liquidacao,'total_parcelas',total_parcelas,'valor_parcela',valor_parcela) resultado from public.consulta_jobs
 union all select id,lote_id,user_id,nome,cpf,telefone,servico,convenio,status,progress,created_at,consultado_em,queue_order,referencia_externa,
 jsonb_build_object('matricula',matricula,'tipo_servidor',tipo_servidor,'situacao_atual',situacao_atual,'emprestimo_disponivel',emprestimo_disponivel,'cartao_disponivel',cartao_disponivel) from public.tjba_jobs;
revoke all on apoiarcred_private.api_campaign_rows,apoiarcred_private.api_lead_rows from public,anon,authenticated;
grant select on apoiarcred_private.api_campaign_rows,apoiarcred_private.api_lead_rows to service_role;
-- Format CPF at the API boundary for both existing and new campaign rows.
create or replace function apoiarcred_private.api_format_cpf(row_data jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select case
  when jsonb_typeof(row_data->'cpf')='string' and row_data->>'cpf' ~ '^[0-9]{11}$' then
   jsonb_set(row_data,'{cpf}',to_jsonb(regexp_replace(
    row_data->>'cpf','^([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{2})$','\1.\2.\3-\4')))
  else row_data
 end;
$$;
revoke all on function apoiarcred_private.api_format_cpf(jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.api_format_cpf(jsonb) to service_role;

create or replace function apoiarcred_private.api_response(code integer,data jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare field text; formatted jsonb;
begin
 data=apoiarcred_private.api_format_cpf(data);
 foreach field in array array['data','accepted','duplicates'] loop
  if jsonb_typeof(data->field)='array' then
   select coalesce(jsonb_agg(apoiarcred_private.api_format_cpf(item) order by position),'[]'::jsonb)
   into formatted
   from jsonb_array_elements(data->field) with ordinality as entries(item,position);
   data=jsonb_set(data,array[field],formatted);
  end if;
 end loop;
 return jsonb_build_object('status',code,'body',data);
end;
$$;
create function apoiarcred_private.api_error(code integer,reason text,message text) returns jsonb language sql immutable set search_path='' as $$select apoiarcred_private.api_response(code,jsonb_build_object('error',jsonb_build_object('code',reason,'message',message)));$$;
revoke all on function apoiarcred_private.api_response(integer,jsonb),apoiarcred_private.api_error(integer,text,text) from public,anon,authenticated;
grant execute on function apoiarcred_private.api_response(integer,jsonb),apoiarcred_private.api_error(integer,text,text) to service_role;

create function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
<<vars>>
declare parts text[]=string_to_array(trim(both '/' from route),'/'); cid uuid; item_id uuid; c record;
 service text; convenio text; lots text; jobs text; item jsonb; idx integer=0; cpf text; nome text; phone text; ref text;
 accepted jsonb='[]';duplicates jsonb='[]';rejected jsonb='[]';data jsonb;counts jsonb; total integer; n integer;
 page integer=greatest(1,coalesce((p->>'page')::integer,1));size integer=least(100,greatest(1,coalesce((p->>'page_size')::integer,50)));
begin
 if method='GET' and route='/servicos' then return apoiarcred_private.api_response(200,'{"data":[{"id":"digimais_saldo_parcela","campos_obrigatorios":["nome","cpf","telefone"]},{"id":"tjba_margem","campos_obrigatorios":["cpf"],"convenios":["tjba","dpeba","embasa","saeb","suprev"]}]}');end if;
 if method='GET' and route='/campanhas' then
  select count(*) into total from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean);
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean) order by created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 if method='POST' and route in ('/campanhas','/consultas') then
  service=coalesce(p->>'servico','digimais_saldo_parcela');convenio=coalesce(p->>'convenio','tjba');
  if service not in ('digimais_saldo_parcela','tjba_margem') or (service='tjba_margem' and convenio not in ('tjba','dpeba','embasa','saeb','suprev')) then return apoiarcred_private.api_error(422,'invalid_service','Serviço ou convênio inválido.');end if;
  nome=case when route='/consultas' then 'Consulta individual via API' else btrim(p->>'nome') end;
  if coalesce(length(nome),0) not between 1 and 160 then return apoiarcred_private.api_error(422,'invalid_name','Informe nome de campanha com até 160 caracteres.');end if;
  lots=case when service='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;
  jobs=case when service='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  -- Individual input validated before creating its lot; all changes atomic.
  if route='/consultas' then
   item=p;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');
   if cpf!~'^[0-9]{11}$' or (service='digimais_saldo_parcela' and (coalesce(length(btrim(item->>'nome')),0) not between 1 and 160 or phone!~'^[0-9]{10,13}$')) or length(coalesce(item->>'referencia_externa',''))>160 then return apoiarcred_private.api_error(422,'invalid_lead','CPF de 11 dígitos; Digi+ exige nome e telefone com DDD.');end if;
  end if;
  if service='tjba_margem' then
   insert into public.tjba_lotes(user_id,nome,tipo,convenio,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,convenio,route='/campanhas') returning id into cid;
  else
   insert into public.consulta_lotes(user_id,nome,tipo,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,route='/campanhas') returning id into cid;
  end if;
  if route='/consultas' then
   execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(btrim(item->>'nome'),''),'CPF '||cpf),cpf,phone,item->>'referencia_externa';
   return apoiarcred_private.api_response(202,jsonb_build_object('id',item_id,'campanha_id',cid,'status','aguardando'));
  end if;
  return apoiarcred_private.api_response(201,jsonb_build_object('id',cid,'nome',nome,'servico',service,'convenio',case when service='tjba_margem' then convenio else null end,'paused',true));
 end if;
 if parts[1]='campanhas' and cardinality(parts) between 2 and 3 then
  cid=parts[2]::uuid;
  select * into c from apoiarcred_private.api_campaign_rows where id=cid and user_id=uid and tipo='campanha';
  if not found then return apoiarcred_private.api_error(404,'not_found','Campanha não encontrada.');end if;
  lots=case when c.servico='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;jobs=case when c.servico='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  if method='GET' and cardinality(parts)=2 then
   select jsonb_build_object('total',count(*),'clientes',count(*) filter(where status='concluida'),'nao_clientes',count(*) filter(where status in ('nao_cliente','nao_localizado','nao_encontrado')),'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'),'aguardando',count(*) filter(where status='aguardando'),'processando',count(*) filter(where status='processando')) into counts from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid;
   return apoiarcred_private.api_response(200,(to_jsonb(c)-'user_id')||jsonb_build_object('relatorio',counts));
  elsif method='POST' then
   execute format('select paused from public.%I where id=$1 and user_id=$2 for update',lots) into c.paused using cid,uid;
   if parts[3] in ('iniciar','pausar') then
    execute format('update public.%I set paused=$1 where id=$2 and user_id=$3',lots) using parts[3]='pausar',cid,uid;
    return apoiarcred_private.api_response(200,jsonb_build_object('id',cid,'paused',parts[3]='pausar'));
   elsif parts[3]='leads' then
    if not c.paused then return apoiarcred_private.api_error(409,'campaign_running','Pause a campanha antes de adicionar leads.');end if;
    if jsonb_typeof(p->'leads') is distinct from 'array' then return apoiarcred_private.api_error(422,'invalid_leads','Envie leads como uma lista.');end if;
    if jsonb_array_length(p->'leads') not between 1 and 1000 then return apoiarcred_private.api_error(422,'invalid_leads','Envie de 1 a 1000 leads.');end if;
    for item in select value from jsonb_array_elements(p->'leads') loop
     idx=idx+1;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');nome=btrim(item->>'nome');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');ref=item->>'referencia_externa';
     if jsonb_typeof(item) is distinct from 'object' or cpf!~'^[0-9]{11}$' or coalesce(length(nome),0)>160 or length(coalesce(ref,''))>160 or (c.servico='digimais_saldo_parcela' and (coalesce(length(nome),0)=0 or phone!~'^[0-9]{10,13}$')) then
      rejected=rejected||jsonb_build_array(jsonb_build_object('linha',idx,'code','invalid_lead','message','Confira CPF, nome, telefone e referência.'));continue;
     end if;
     -- Parent row lock serializes API inserts with API pause/start; no historical duplicates are deleted.
     if exists(select 1 from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid and api_lead_rows.cpf=vars.cpf) then
      duplicates=duplicates||jsonb_build_array(jsonb_build_object('linha',idx,'cpf',cpf));continue;
     end if;
     execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(nome,''),'CPF '||cpf),cpf,phone,ref;
     accepted=accepted||jsonb_build_array(jsonb_build_object('linha',idx,'id',item_id,'cpf',cpf));
    end loop;
    return apoiarcred_private.api_response(200,jsonb_build_object('accepted',accepted,'duplicates',duplicates,'rejected',rejected));
   elsif parts[3]='repetir-revisoes' then
    if c.servico='tjba_margem' then
     update public.tjba_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,matricula=null,tipo_servidor=null,situacao_atual=null,emprestimo_disponivel=null,cartao_disponivel=null,tjba_status=null,resultado_tjba=null where lote_id=cid and user_id=uid and status in ('erro','revisao');
    else
     update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,saldo_liquidacao=null,total_parcelas=null,valor_parcela=null,resultado_saldo=null,resultado_parcela=null where lote_id=cid and user_id=uid and status in ('erro','revisao');
    end if;
    get diagnostics n=row_count;return apoiarcred_private.api_response(202,jsonb_build_object('reenfileirados',n,'paused',c.paused));
   end if;
  end if;
 end if;
 if (method='GET' and parts[1] in ('leads','consultas') and cardinality(parts)=2) then
  select to_jsonb(x)-'user_id' into data from apoiarcred_private.api_lead_rows x where id=parts[2]::uuid and user_id=uid;
  if data is null then return apoiarcred_private.api_error(404,'not_found','Registro não encontrado.');end if;
  return apoiarcred_private.api_response(200,data);
 end if;
 if (method='POST' and route='/leads/buscar') or (method='GET' and parts[1]='campanhas' and parts[3]='leads' and cardinality(parts)=3) then
  cpf=case when method='POST' then regexp_replace(coalesce(p->>'cpf',''),'[^0-9]','','g') else null end;
  if method='POST' and cpf!~'^[0-9]{11}$' then return apoiarcred_private.api_error(422,'invalid_cpf','Informe CPF com 11 dígitos.');end if;
  cid=case when method='GET' then parts[2]::uuid else nullif(p->>'campanha_id','')::uuid end;
  select count(*) into total from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status');
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status') order by case when method='GET' then queue_order end,created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 return apoiarcred_private.api_error(404,'route_not_found','Rota não encontrada.');
end $$;
revoke all on function apoiarcred_private.api_route(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.api_route(uuid,text,text,jsonb) to service_role;

create function public.api_execute(p_hash text,p_method text,p_route text,p_payload jsonb default '{}',p_key text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t apoiarcred_private.api_tokens;scope text;fingerprint text;cached apoiarcred_private.api_idempotency;result jsonb;
begin
 select * into t from apoiarcred_private.api_tokens where token_hash=p_hash for update;
 if not found or t.revoked_at is not null or (t.expires_at is not null and t.expires_at<=now()) then return apoiarcred_private.api_error(401,'invalid_token','Token inválido, expirado ou revogado.');end if;
 scope=case when p_method='GET' or p_route='/leads/buscar' then 'read' when p_route='/consultas' then 'consultas:create' else 'campanhas:write' end;
 if not scope=any(t.scopes) then return apoiarcred_private.api_error(403,'insufficient_scope','O token não possui esta permissão.');end if;
 if t.rate_window is null or t.rate_window<now()-interval '1 minute' then t.rate_count=0;t.rate_window=now();end if;
 if t.rate_count>=120 then return apoiarcred_private.api_error(429,'rate_limit','Limite de 120 requisições por minuto.');end if;
 update apoiarcred_private.api_tokens set rate_count=t.rate_count+1,rate_window=t.rate_window,last_used_at=now() where id=t.id;
 if p_method not in ('GET','POST') or jsonb_typeof(p_payload) is distinct from 'object' then return apoiarcred_private.api_error(400,'invalid_request','Requisição inválida.');end if;
 if p_method='POST' and p_route<>'/leads/buscar' and (p_key is null or length(p_key) not between 1 and 128) then return apoiarcred_private.api_error(400,'idempotency_required','Envie Idempotency-Key de 1 a 128 caracteres.');end if;
 delete from apoiarcred_private.api_idempotency where token_id=t.id and created_at<now()-interval '24 hours';
 if p_method='POST' and p_route<>'/leads/buscar' then
  fingerprint=encode(extensions.digest(p_method||p_route||p_payload::text,'sha256'),'hex');
  select * into cached from apoiarcred_private.api_idempotency where token_id=t.id and key=p_key;
  if found then
   if cached.fingerprint<>fingerprint then return apoiarcred_private.api_error(409,'idempotency_conflict','Chave já usada com outra rota ou payload.');end if;
   return cached.response||'{"replayed":true}';
  end if;
 end if;
 begin
  result=apoiarcred_private.api_route(t.user_id,p_method,p_route,p_payload);
 exception when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value or check_violation or not_null_violation then
  result=apoiarcred_private.api_error(422,'validation_error','Dados inválidos. Confira UUIDs, paginação e campos obrigatórios.');
 end;
 if fingerprint is not null and (result->>'status')::integer<300 then insert into apoiarcred_private.api_idempotency(token_id,key,fingerprint,response) values(t.id,p_key,fingerprint,result);end if;
 return result;
end $$;
revoke all on function public.api_execute(text,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.api_execute(text,text,text,jsonb,text) to service_role;
notify pgrst,'reload schema';

-- Partner permissions are enforced on job writes, including REST and API service-role writes.
create table apoiarcred_private.user_profiles(
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('admin','partner')),name text not null,email text not null,
 active boolean not null default true,created_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table apoiarcred_private.partner_permissions(
 user_id uuid not null references apoiarcred_private.user_profiles(user_id) on delete cascade,
 service text not null check(service in ('digimais_saldo_parcela','tjba_margem')),
 enabled boolean not null default false,allow_individual boolean not null default false,
 daily_limit integer not null default 0 check(daily_limit between 0 and 100000),allow_campaign boolean not null default false,
 primary key(user_id,service)
);
create table apoiarcred_private.partner_daily_usage(
 user_id uuid not null references apoiarcred_private.user_profiles(user_id) on delete cascade,
 service text not null,day date not null,used integer not null default 0 check(used>=0),primary key(user_id,service,day)
);
alter table apoiarcred_private.user_profiles enable row level security;
alter table apoiarcred_private.partner_permissions enable row level security;
alter table apoiarcred_private.partner_daily_usage enable row level security;
revoke all on apoiarcred_private.user_profiles,apoiarcred_private.partner_permissions,apoiarcred_private.partner_daily_usage from public,anon,authenticated;
grant all on apoiarcred_private.user_profiles,apoiarcred_private.partner_permissions,apoiarcred_private.partner_daily_usage to service_role;
create policy profiles_service on apoiarcred_private.user_profiles for all to service_role using(true) with check(true);
create policy permissions_service on apoiarcred_private.partner_permissions for all to service_role using(true) with check(true);
create policy usage_service on apoiarcred_private.partner_daily_usage for all to service_role using(true) with check(true);
-- Safe bootstrap: only the sole existing account becomes admin. Multi-user projects
-- must explicitly assign their first admin via the SQL editor; never trust user_metadata.
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
 select id,'admin',split_part(email,'@',1),email from auth.users where deleted_at is null
 and (select count(*) from auth.users where deleted_at is null)=1;

create function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid;
$$;
revoke all on function apoiarcred_private.access_for(uuid) from public,anon,authenticated;
grant execute on function apoiarcred_private.access_for(uuid) to service_role;
create function apoiarcred_private.my_access() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin if auth.uid() is null then raise insufficient_privilege;end if;return apoiarcred_private.access_for(auth.uid());end $$;
revoke all on function apoiarcred_private.my_access() from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.my_access() to authenticated;
create function public.my_access() returns jsonb language sql stable security invoker set search_path='' as $$select apoiarcred_private.my_access();$$;
revoke all on function public.my_access() from public,anon,authenticated,service_role;
grant execute on function public.my_access() to authenticated;
create function apoiarcred_private.is_admin(uid uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='admin' and active);$$;
revoke all on function apoiarcred_private.is_admin(uuid) from public,anon,authenticated;
grant execute on function apoiarcred_private.is_admin(uuid) to service_role;
create function apoiarcred_private.my_admin() returns boolean language sql stable security definer set search_path='' as $$select apoiarcred_private.is_admin(auth.uid());$$;
revoke all on function apoiarcred_private.my_admin() from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.my_admin() to authenticated;
create function public.am_i_admin() returns boolean language sql stable security invoker set search_path='' as $$select apoiarcred_private.my_admin();$$;
revoke all on function public.am_i_admin() from public,anon,authenticated,service_role;
grant execute on function public.am_i_admin() to authenticated;
drop policy if exists monitor_read on public.vps_monitoramento;
create policy monitor_read on public.vps_monitoramento for select to authenticated using((select public.am_i_admin()));

create function apoiarcred_private.check_partner_access(uid uuid,service_id text,mode text,consume boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles;rule apoiarcred_private.partner_permissions;today date=(now() at time zone 'America/Sao_Paulo')::date;n integer;
begin
 select * into profile from apoiarcred_private.user_profiles where user_id=uid for share;
 if not found or not profile.active then raise insufficient_privilege using message='Conta sem acesso ativo. Solicite liberação ao administrador.';end if;
 if profile.role='admin' then return;end if;
 select * into rule from apoiarcred_private.partner_permissions where user_id=uid and service=service_id for share;
 if not found or not rule.enabled then raise insufficient_privilege using message='Tipo de higienização não autorizado para este parceiro.';end if;
 if mode='campanha' then
  if not rule.allow_campaign then raise insufficient_privilege using message='Campanhas não estão habilitadas para este tipo de higienização.';end if;
 elsif mode='individual' then
  if not rule.allow_individual or rule.daily_limit=0 then raise insufficient_privilege using message='Consultas individuais não estão habilitadas para este tipo de higienização.';end if;
  if consume then
   insert into apoiarcred_private.partner_daily_usage(user_id,service,day,used) values(uid,service_id,today,0) on conflict do nothing;
   update apoiarcred_private.partner_daily_usage set used=used+1 where user_id=uid and service=service_id and day=today and used<rule.daily_limit;
   get diagnostics n=row_count;
   if n=0 then raise sqlstate 'PT429' using message='Limite diário de consultas individuais atingido para este tipo. Renova à meia-noite no horário de Brasília.';end if;
  end if;
 else raise insufficient_privilege;end if;
end $$;
revoke all on function apoiarcred_private.check_partner_access(uuid,text,text,boolean) from public,anon,authenticated,service_role;
create function apoiarcred_private.guard_partner_lot() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if new.user_id<>old.user_id or new.servico<>old.servico or new.tipo<>old.tipo then raise insufficient_privilege;end if;
  if not (old.paused and not new.paused) then return new;end if;
 end if;
 perform apoiarcred_private.check_partner_access(new.user_id,new.servico,new.tipo,false);return new;end $$;
revoke all on function apoiarcred_private.guard_partner_lot() from public,anon,authenticated,service_role;
create trigger guard_partner_lot before insert or update on public.consulta_lotes for each row execute function apoiarcred_private.guard_partner_lot();
create trigger guard_partner_lot before insert or update on public.tjba_lotes for each row execute function apoiarcred_private.guard_partner_lot();
create function apoiarcred_private.guard_partner_job() returns trigger language plpgsql security definer set search_path='' as $$
declare lot record;
begin
 if tg_op='UPDATE' then
  if new.user_id<>old.user_id or new.lote_id<>old.lote_id or new.servico<>old.servico then raise insufficient_privilege;end if;
  if not (new.status='aguardando' and old.status in ('erro','revisao')) then return new;end if;
 end if;
 if tg_table_name='consulta_jobs' then select user_id,tipo,servico into lot from public.consulta_lotes where id=new.lote_id for share;
 else select user_id,tipo,servico into lot from public.tjba_lotes where id=new.lote_id for share;end if;
 if not found or lot.user_id<>new.user_id or lot.servico<>new.servico then raise insufficient_privilege;end if;
 perform apoiarcred_private.check_partner_access(new.user_id,lot.servico,lot.tipo,true);return new;
end $$;
revoke all on function apoiarcred_private.guard_partner_job() from public,anon,authenticated,service_role;
create trigger guard_partner_job before insert or update on public.consulta_jobs for each row execute function apoiarcred_private.guard_partner_job();
create trigger guard_partner_job before insert or update on public.tjba_jobs for each row execute function apoiarcred_private.guard_partner_job();

create function public.create_individual_consulta(p_item jsonb,p_servico text default 'digimais_saldo_parcela',p_convenio text default 'tjba') returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;jid uuid;begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 if p_servico='tjba_margem' then
  insert into public.tjba_lotes(nome,tipo,convenio) values('Consulta individual','individual',p_convenio) returning id into cid;
  insert into public.tjba_jobs(user_id,lote_id,nome,cpf,telefone) values(auth.uid(),cid,coalesce(nullif(btrim(p_item->>'nome'),''),'CPF '||(p_item->>'cpf')),p_item->>'cpf',coalesce(p_item->>'telefone','')) returning id into jid;
 elsif p_servico='digimais_saldo_parcela' then
  insert into public.consulta_lotes(nome,tipo) values('Consulta individual','individual') returning id into cid;
  insert into public.consulta_jobs(user_id,lote_id,nome,cpf,telefone) values(auth.uid(),cid,p_item->>'nome',p_item->>'cpf',p_item->>'telefone') returning id into jid;
 else raise exception 'Serviço inválido.';end if;return jid;
end $$;
revoke all on function public.create_individual_consulta(jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function public.create_individual_consulta(jsonb,text,text) to authenticated;

create function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg((to_jsonb(p)-'created_by')||jsonb_build_object('access',apoiarcred_private.access_for(p.user_id)) order by p.created_at desc),'[]') into result from apoiarcred_private.user_profiles p where role='partner';return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null then raise insufficient_privilege;end if;
 if p_action='create' and exists(select 1 from apoiarcred_private.user_profiles where user_id=uid) then raise exception 'Perfil já existe.';end if;
 if p_action='update' and not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='partner') then raise insufficient_privilege;end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' not in ('digimais_saldo_parcela','tjba_margem') or item->>'service' is null or (item->>'daily_limit')::int not between 0 and 100000 then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;
revoke all on function public.admin_partner_manage(uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_partner_manage(uuid,text,jsonb) to service_role;
-- API translates permission/quota errors while preserving request idempotency.
create or replace function public.api_execute(p_hash text,p_method text,p_route text,p_payload jsonb default '{}',p_key text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t apoiarcred_private.api_tokens;scope text;fingerprint text;cached apoiarcred_private.api_idempotency;result jsonb;
begin
 select * into t from apoiarcred_private.api_tokens where token_hash=p_hash for update;
 if not found or t.revoked_at is not null or (t.expires_at is not null and t.expires_at<=now()) then return apoiarcred_private.api_error(401,'invalid_token','Token inválido, expirado ou revogado.');end if;
 scope=case when p_method='GET' or p_route='/leads/buscar' then 'read' when p_route='/consultas' then 'consultas:create' else 'campanhas:write' end;
 if not scope=any(t.scopes) then return apoiarcred_private.api_error(403,'insufficient_scope','O token não possui esta permissão.');end if;
 if t.rate_window is null or t.rate_window<now()-interval '1 minute' then t.rate_count=0;t.rate_window=now();end if;
 if t.rate_count>=120 then return apoiarcred_private.api_error(429,'rate_limit','Limite de 120 requisições por minuto.');end if;
 update apoiarcred_private.api_tokens set rate_count=t.rate_count+1,rate_window=t.rate_window,last_used_at=now() where id=t.id;
 if p_method not in ('GET','POST') or jsonb_typeof(p_payload) is distinct from 'object' then return apoiarcred_private.api_error(400,'invalid_request','Requisição inválida.');end if;
 if p_method='POST' and p_route<>'/leads/buscar' and (p_key is null or length(p_key) not between 1 and 128) then return apoiarcred_private.api_error(400,'idempotency_required','Envie Idempotency-Key de 1 a 128 caracteres.');end if;
 delete from apoiarcred_private.api_idempotency where token_id=t.id and created_at<now()-interval '24 hours';
 if p_method='POST' and p_route<>'/leads/buscar' then
  fingerprint=encode(extensions.digest(p_method||p_route||p_payload::text,'sha256'),'hex');
  select * into cached from apoiarcred_private.api_idempotency where token_id=t.id and key=p_key;
  if found then
   if cached.fingerprint<>fingerprint then return apoiarcred_private.api_error(409,'idempotency_conflict','Chave já usada com outra rota ou payload.');end if;
   return cached.response||'{"replayed":true}';
  end if;
 end if;
 begin
  result=apoiarcred_private.api_route(t.user_id,p_method,p_route,p_payload);
 exception when insufficient_privilege then
  result=apoiarcred_private.api_error(403,'partner_permission',sqlerrm);
 when sqlstate 'PT429' then
  result=apoiarcred_private.api_error(429,'daily_limit',sqlerrm);
 when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value or check_violation or not_null_violation then
  result=apoiarcred_private.api_error(422,'validation_error','Dados inválidos. Confira UUIDs, paginação e campos obrigatórios.');
 end;
 if fingerprint is not null and (result->>'status')::integer<300 then insert into apoiarcred_private.api_idempotency(token_id,key,fingerprint,response) values(t.id,p_key,fingerprint,result);end if;
 return result;
end $$;
revoke all on function public.api_execute(text,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.api_execute(text,text,text,jsonb,text) to service_role;
notify pgrst,'reload schema';

-- Webhooks
-- Transactional outbox: result persistence never waits on an HTTP endpoint.
create table apoiarcred_private.webhooks(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 100),url text not null check(length(url)<=2048 and url~'^https://'),
 active boolean not null default true,scope text not null check(scope in ('all','individual','campaign')),
 service text check(service in ('digimais_saldo_parcela','tjba_margem')),campaign_id uuid,
 events text[] not null,statuses text[] not null,client_filter text not null check(client_filter in ('all','client','nonclient','unknown')),
 include_partial boolean not null default true,secret_id uuid not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 manual_window timestamptz,manual_count integer not null default 0
);
create index webhooks_owner on apoiarcred_private.webhooks(user_id);
create table apoiarcred_private.webhook_events(
 id uuid primary key,event_key text not null unique,user_id uuid not null references auth.users(id) on delete cascade,
 event text not null,payload jsonb not null,created_at timestamptz not null default now()
);
create index webhook_events_owner on apoiarcred_private.webhook_events(user_id,created_at desc);
create table apoiarcred_private.webhook_deliveries(
 id uuid primary key default gen_random_uuid(),hook_id uuid not null references apoiarcred_private.webhooks(id) on delete cascade,
 event_id uuid not null references apoiarcred_private.webhook_events(id) on delete cascade,
 state text not null default 'pending' check(state in ('pending','delivering','retry','delivered','failed')),
 attempts integer not null default 0,total_attempts integer not null default 0,next_at timestamptz not null default now(),
 locked_until timestamptz,claim_token uuid,last_http integer,last_error text,delivered_at timestamptz,created_at timestamptz not null default now(),unique(hook_id,event_id)
);
create index webhook_delivery_queue on apoiarcred_private.webhook_deliveries(next_at) where state in ('pending','retry','delivering');
create index webhook_delivery_hook on apoiarcred_private.webhook_deliveries(hook_id,created_at desc);
create table apoiarcred_private.webhook_attempts(
 delivery_id uuid not null references apoiarcred_private.webhook_deliveries(id) on delete cascade,attempt integer not null,
 claim_token uuid not null,started_at timestamptz not null default now(),finished_at timestamptz,http_status integer,error text,
 primary key(delivery_id,attempt)
);
create table apoiarcred_private.webhook_campaign_dirty(
 service text not null,campaign_id uuid not null,user_id uuid not null,touched_at timestamptz not null default now(),checked_at timestamptz,
 primary key(service,campaign_id)
);
alter table apoiarcred_private.webhooks enable row level security;
alter table apoiarcred_private.webhook_events enable row level security;
alter table apoiarcred_private.webhook_deliveries enable row level security;
alter table apoiarcred_private.webhook_attempts enable row level security;
alter table apoiarcred_private.webhook_campaign_dirty enable row level security;
revoke all on apoiarcred_private.webhooks,apoiarcred_private.webhook_events,apoiarcred_private.webhook_deliveries,apoiarcred_private.webhook_attempts,apoiarcred_private.webhook_campaign_dirty from public,anon,authenticated,service_role;

create function apoiarcred_private.wh_client(service text,status text,r jsonb) returns boolean language sql immutable set search_path='' as $$
 select case when status in ('nao_cliente','nao_localizado','nao_encontrado') then false
 when status='concluida' then true
 when service='digimais_saldo_parcela' and (r->>'saldo_liquidacao' is not null or r->>'valor_parcela' is not null) then true
 when service='tjba_margem' and (nullif(r->>'matricula','') is not null or r->>'emprestimo_disponivel' is not null or r->>'cartao_disponivel' is not null) then true
 else null end;
$$;
create function apoiarcred_private.wh_result(service text,r jsonb) returns jsonb language sql immutable set search_path='' as $$
 select case when service='digimais_saldo_parcela' then jsonb_build_object('saldo_liquidacao',r->'saldo_liquidacao','valor_parcela',r->'valor_parcela','total_parcelas',r->'total_parcelas')
 else jsonb_build_object('emprestimo_disponivel',r->'emprestimo_disponivel','cartao_disponivel',r->'cartao_disponivel','matricula',r->'matricula','tipo_servidor',r->'tipo_servidor','situacao_atual',r->'situacao_atual') end;
$$;
create function apoiarcred_private.wh_enqueue(uid uuid,event_key text,event_name text,body jsonb,service_id text,lot_id uuid,lot_type text,status text,client boolean,partial_result boolean) returns uuid
language plpgsql security definer set search_path='' as $$
<<vars>>
declare eid uuid=gen_random_uuid();h record;inserted_id uuid;begin
 for h in select * from apoiarcred_private.webhooks w where w.user_id=uid and w.active and event_name=any(w.events)
 and (w.service is null or w.service=service_id)
 and (w.scope='all' or w.scope='individual' and lot_type='individual' or w.scope='campaign' and w.campaign_id=lot_id)
 and (event_name='campanha.finalizada' or (status=any(w.statuses) and (w.include_partial or not partial_result)
 and (w.client_filter='all' or w.client_filter='client' and client is true or w.client_filter='nonclient' and client is false or w.client_filter='unknown' and client is null))) loop
  insert into apoiarcred_private.webhook_events(id,event_key,user_id,event,payload)
  values(eid,event_key,uid,event_name,body||jsonb_build_object('event_id',eid,'event',event_name))
  on conflict on constraint webhook_events_event_key_key do update set event_key=excluded.event_key returning id into inserted_id;
  eid=inserted_id;
  insert into apoiarcred_private.webhook_deliveries(hook_id,event_id) values(h.id,eid) on conflict do nothing;
 end loop;return eid;
end $$;

create function apoiarcred_private.wh_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb;lot record;result jsonb;client boolean;partial_result boolean;service_id text;begin
 r=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;service_id=r->>'servico';
 if tg_op='UPDATE' and new.status=old.status and new.consultado_em is not distinct from old.consultado_em then return new;end if;
 if tg_table_name='consulta_jobs' then select id,user_id,nome,tipo into lot from public.consulta_lotes where id=(r->>'lote_id')::uuid;
 else select id,user_id,nome,tipo into lot from public.tjba_lotes where id=(r->>'lote_id')::uuid;end if;
 if not found then return null;end if;
 if tg_op='UPDATE' and old.status='processando' and new.status in ('concluida','nao_cliente','nao_localizado','nao_encontrado','erro','revisao') and new.consultado_em is not null then
  result=apoiarcred_private.wh_result(service_id,r);client=apoiarcred_private.wh_client(service_id,new.status,result);partial_result=client is true and new.status<>'concluida';
  perform apoiarcred_private.wh_enqueue(new.user_id,'consulta:'||tg_table_name||':'||new.id||':'||new.attempts||':'||new.consultado_em::text,'consulta.finalizada',
   jsonb_build_object('occurred_at',new.consultado_em,'campanha',case when lot.tipo='campanha' then jsonb_build_object('id',lot.id,'nome',lot.nome) else null end,
   'consulta',jsonb_build_object('id',new.id,'referencia_externa',r->'referencia_externa','servico',service_id,'convenio',r->'convenio','cpf',new.cpf,'nome',new.nome,'telefone',new.telefone,'status',new.status,'cliente_identificado',client,'resultado_parcial',partial_result,'mensagem',left(new.message,1000),'resultado',result)),
   service_id,lot.id,lot.tipo,new.status,client,partial_result);
 end if;
 if lot.tipo='campanha' and exists(select 1 from apoiarcred_private.webhooks w where w.user_id=lot.user_id and w.active and 'campanha.finalizada'=any(w.events) and w.scope<>'individual' and (w.service is null or w.service=service_id) and (w.scope='all' or w.campaign_id=lot.id)) then
  insert into apoiarcred_private.webhook_campaign_dirty(service,campaign_id,user_id) values(service_id,lot.id,lot.user_id)
  on conflict(service,campaign_id) do update set touched_at=clock_timestamp(),checked_at=null;
 end if;
 return null;
end $$;
create trigger capture_webhook after insert or delete or update of status,consultado_em on public.consulta_jobs for each row execute function apoiarcred_private.wh_capture();
create trigger capture_webhook after insert or delete or update of status,consultado_em on public.tjba_jobs for each row execute function apoiarcred_private.wh_capture();

create function apoiarcred_private.wh_campaigns() returns void language plpgsql security definer set search_path='' as $$
declare dirty record;lot record;r jsonb;pending integer;total integer;last_result timestamptz;begin
 for dirty in select * from apoiarcred_private.webhook_campaign_dirty order by checked_at nulls first,touched_at limit 20 for update skip locked loop
  select * into lot from apoiarcred_private.api_campaign_rows where id=dirty.campaign_id and user_id=dirty.user_id and tipo='campanha';
  if not found then delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=dirty.campaign_id;continue;end if;
  select count(*),count(*) filter(where status in ('aguardando','processando')),max(consultado_em),
   jsonb_build_object('total',count(*),'clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is true),
    'nao_clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is false),'indeterminados',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is null),
    'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'))
   into total,pending,last_result,r from apoiarcred_private.api_lead_rows where campanha_id=lot.id and user_id=lot.user_id;
  if total>0 and pending=0 and last_result is not null then
   perform apoiarcred_private.wh_enqueue(lot.user_id,'campanha:'||dirty.service||':'||lot.id||':'||encode(extensions.digest(r::text||last_result::text,'sha256'),'hex'),'campanha.finalizada',
    jsonb_build_object('occurred_at',clock_timestamp(),'campanha',jsonb_build_object('id',lot.id,'nome',lot.nome,'servico',lot.servico,'convenio',lot.convenio),'relatorio',r),lot.servico,lot.id,'campanha',null,null,false);
   delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=lot.id;
  else update apoiarcred_private.webhook_campaign_dirty set checked_at=clock_timestamp() where service=dirty.service and campaign_id=lot.id;end if;
 end loop;
end $$;

create function apoiarcred_private.manage_webhooks(action text,input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
<<vars>>
declare uid uuid=auth.uid();hid uuid;w apoiarcred_private.webhooks;secret text;sid uuid;data jsonb;lot record;ev text[];st text[];scope text;service_id text;campaign_id uuid;delivery record;eid uuid;
begin
 if uid is null or not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and active) then raise insufficient_privilege;end if;
 if action='list' then
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'-'secret_id'-'manual_window'-'manual_count' order by x.created_at desc),'[]') into data from apoiarcred_private.webhooks x where user_id=uid;return data;
 end if;
 if action='history' then
  hid=nullif(input->>'hook_id','')::uuid;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into data from (
   select d.id,d.hook_id,h.name hook_name,e.id event_id,e.event,e.payload->'consulta'->>'cpf' cpf,e.payload->'campanha'->>'nome' campaign_name,
    d.state,d.attempts,d.total_attempts,d.last_http,d.last_error,d.next_at,d.created_at,d.delivered_at,
    (select coalesce(jsonb_agg(to_jsonb(a)-'claim_token'-'delivery_id' order by attempt desc),'[]') from apoiarcred_private.webhook_attempts a where a.delivery_id=d.id) attempts_log
   from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id join apoiarcred_private.webhook_events e on e.id=d.event_id
   where h.user_id=uid and (hid is null or h.id=hid) order by d.created_at desc limit 50
  ) x;return data;
 end if;
 if action in ('update','toggle','rotate','test') then
  hid=(input->>'id')::uuid;select * into w from apoiarcred_private.webhooks where id=hid and user_id=uid for update;
  if not found then raise insufficient_privilege;end if;
 end if;
 if action='toggle' then
  update apoiarcred_private.webhooks set active=(input->>'active')::boolean,updated_at=clock_timestamp() where id=hid;return '{"ok":true}';
 elsif action='rotate' then
  secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');perform vault.update_secret(w.secret_id,secret);return jsonb_build_object('secret',secret);
 elsif action in ('test','retry') then
  if action='retry' then
   select d.* into delivery from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id where d.id=(input->>'delivery_id')::uuid and h.user_id=uid for update of d;
   if not found then raise insufficient_privilege;end if;
   if delivery.state not in ('delivered','failed') then raise exception 'A entrega já está na fila ou em andamento.';end if;
   select * into w from apoiarcred_private.webhooks where id=delivery.hook_id for update;hid=w.id;
  end if;
  if not w.active then raise exception 'Ative o webhook para testar ou reenviar.';end if;
  if w.manual_window is null or w.manual_window<now()-interval '1 hour' then w.manual_count=0;w.manual_window=now();end if;
  if w.manual_count>=10 then raise exception 'Limite de 10 testes/reenvios manuais por hora neste webhook.';end if;
  update apoiarcred_private.webhooks set manual_window=w.manual_window,manual_count=w.manual_count+1 where id=hid;
  if action='retry' then
   update apoiarcred_private.webhook_deliveries set state='pending',attempts=0,next_at=clock_timestamp(),claim_token=null,locked_until=null,last_error=null where id=delivery.id;
   return jsonb_build_object('delivery_id',delivery.id);
  end if;
  eid=gen_random_uuid();insert into apoiarcred_private.webhook_events(id,event_key,user_id,event,payload) values(eid,'test:'||eid,uid,'webhook.teste',
   jsonb_build_object('event_id',eid,'event','webhook.teste','occurred_at',clock_timestamp(),'test',true,'campanha',null,'consulta',jsonb_build_object('id',gen_random_uuid(),'servico',coalesce(w.service,'digimais_saldo_parcela'),'cpf','00000000000','nome','Cliente fictício de teste','telefone','00000000000','status','concluida','cliente_identificado',true,'resultado_parcial',false,'resultado',case when w.service='tjba_margem' then jsonb_build_object('emprestimo_disponivel',100,'cartao_disponivel',50,'matricula','TESTE-FICTICIO','tipo_servidor',null,'situacao_atual',null) else jsonb_build_object('saldo_liquidacao',1000,'valor_parcela',100,'total_parcelas',96) end)));
  insert into apoiarcred_private.webhook_deliveries(hook_id,event_id) values(hid,eid) returning id into hid;return jsonb_build_object('delivery_id',hid);
 elsif action not in ('create','update') then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(input->>'name')),0) not between 1 and 100 or coalesce(length(input->>'url'),0) not between 9 and 2048 or input->>'url'!~'^https://[^/@#[:space:]]+(/[^#[:space:]]*)?$' then raise exception 'Informe nome e URL HTTPS pública válida, sem usuário, senha ou fragmento.';end if;
 scope=input->>'scope';service_id=nullif(input->>'service','');campaign_id=nullif(input->>'campaign_id','')::uuid;
 if scope is null or scope not in ('all','individual','campaign') or (service_id is not null and service_id not in ('digimais_saldo_parcela','tjba_margem')) then raise exception 'Origem ou serviço inválido.';end if;
 if scope='campaign' then
  select * into lot from apoiarcred_private.api_campaign_rows c where c.id=vars.campaign_id and c.user_id=uid and c.tipo='campanha';
  if not found then raise insufficient_privilege;end if;service_id=lot.servico;
 else campaign_id=null;end if;
 select array_agg(distinct x) into ev from jsonb_array_elements_text(input->'events') x;
 select array_agg(distinct x) into st from jsonb_array_elements_text(input->'statuses') x;
 if coalesce(cardinality(ev),0)=0 or not ev<@array['consulta.finalizada','campanha.finalizada'] or (scope='individual' and 'campanha.finalizada'=any(ev)) then raise exception 'Escolha eventos válidos.';end if;
 if coalesce(cardinality(st),0)=0 or not st<@array['concluida','erro','revisao','nao_cliente','nao_localizado','nao_encontrado'] or coalesce(input->>'client_filter','') not in ('all','client','nonclient','unknown') then raise exception 'Filtros de resultado inválidos.';end if;
 if action='create' then
  perform pg_advisory_xact_lock(hashtextextended(uid::text,11));
  if (select count(*) from apoiarcred_private.webhooks where user_id=uid)>=20 then raise exception 'Limite de 20 webhooks por conta.';end if;
  hid=gen_random_uuid();secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');sid=vault.create_secret(secret,'apoiarcred-webhook-'||hid);
  insert into apoiarcred_private.webhooks(id,user_id,name,url,active,scope,service,campaign_id,events,statuses,client_filter,include_partial,secret_id)
  values(hid,uid,btrim(input->>'name'),input->>'url',coalesce((input->>'active')::boolean,true),scope,service_id,campaign_id,ev,st,input->>'client_filter',coalesce((input->>'include_partial')::boolean,true),sid);
 else
  update apoiarcred_private.webhooks set name=btrim(input->>'name'),url=input->>'url',active=coalesce((input->>'active')::boolean,true),scope=vars.scope,service=service_id,campaign_id=vars.campaign_id,events=ev,statuses=st,client_filter=input->>'client_filter',include_partial=coalesce((input->>'include_partial')::boolean,true),updated_at=clock_timestamp() where id=hid;
 end if;
 return jsonb_build_object('id',hid,'secret',secret);
end $$;

create function apoiarcred_private.wh_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare d record;result jsonb='[]';token uuid;begin
 perform apoiarcred_private.wh_campaigns();
 update apoiarcred_private.webhook_deliveries set state='failed',last_error='Confirmação da entrega não recebida após o limite de tentativas.' where state='delivering' and locked_until<now() and attempts>=8;
 for d in select q.id from apoiarcred_private.webhook_deliveries q join apoiarcred_private.webhooks w on w.id=q.hook_id
 join apoiarcred_private.user_profiles p on p.user_id=w.user_id and p.active
 where w.active and q.attempts<8 and q.next_at<=now() and (q.state in ('pending','retry') or q.state='delivering' and q.locked_until<now())
 order by q.next_at,q.created_at limit 2 for update of q skip locked loop
  update apoiarcred_private.webhook_attempts set finished_at=clock_timestamp(),error='Confirmação da tentativa anterior não recebida.' where delivery_id=d.id and finished_at is null;
  token=gen_random_uuid();
  update apoiarcred_private.webhook_deliveries set state='delivering',attempts=attempts+1,total_attempts=total_attempts+1,claim_token=token,locked_until=now()+interval '2 minutes' where id=d.id;
  insert into apoiarcred_private.webhook_attempts(delivery_id,attempt,claim_token) select id,total_attempts,token from apoiarcred_private.webhook_deliveries where id=d.id;
  select result||jsonb_build_array(jsonb_build_object('id',q.id,'claim_token',token,'event_id',e.id,'payload',e.payload,'url',w.url,'secret',s.decrypted_secret)) into result
  from apoiarcred_private.webhook_deliveries q join apoiarcred_private.webhooks w on w.id=q.hook_id join apoiarcred_private.webhook_events e on e.id=q.event_id left join vault.decrypted_secrets s on s.id=w.secret_id where q.id=d.id;
 end loop;return result;
end $$;
create function apoiarcred_private.wh_ack(p_id uuid,p_token uuid,p_success boolean,p_http integer,p_error text,p_retry boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare d apoiarcred_private.webhook_deliveries;delay integer;begin
 select * into d from apoiarcred_private.webhook_deliveries where id=p_id and claim_token=p_token and state='delivering' for update;
 if not found then return false;end if;
 delay=(array[30,120,600,1800,7200,21600,43200,43200])[least(d.attempts,8)];
 update apoiarcred_private.webhook_deliveries set state=case when p_success then 'delivered' when p_retry and d.attempts<8 then 'retry' else 'failed' end,
  last_http=p_http,last_error=left(p_error,500),next_at=clock_timestamp()+make_interval(secs=>delay),locked_until=null,
  delivered_at=case when p_success then clock_timestamp() else delivered_at end where id=d.id;
 update apoiarcred_private.webhook_attempts set finished_at=clock_timestamp(),http_status=p_http,error=left(p_error,500) where delivery_id=d.id and claim_token=p_token;return true;
end $$;
-- Private definer implementations; only narrow invoker entry points are exposed.
revoke all on function apoiarcred_private.wh_client(text,text,jsonb),apoiarcred_private.wh_result(text,jsonb),apoiarcred_private.wh_enqueue(uuid,text,text,jsonb,text,uuid,text,text,boolean,boolean),apoiarcred_private.wh_capture(),apoiarcred_private.wh_campaigns(),apoiarcred_private.manage_webhooks(text,jsonb),apoiarcred_private.wh_claim(),apoiarcred_private.wh_ack(uuid,uuid,boolean,integer,text,boolean) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.manage_webhooks(text,jsonb) to authenticated;
grant execute on function apoiarcred_private.wh_claim(),apoiarcred_private.wh_ack(uuid,uuid,boolean,integer,text,boolean) to service_role;
create function public.manage_webhooks(p_action text,p_input jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.manage_webhooks(p_action,p_input);$$;
create function public.claim_webhook_deliveries() returns jsonb language sql security invoker set search_path='' as $$select apoiarcred_private.wh_claim();$$;
create function public.ack_webhook_delivery(p_id uuid,p_token uuid,p_success boolean,p_http integer,p_error text,p_retry boolean) returns boolean language sql security invoker set search_path='' as $$select apoiarcred_private.wh_ack(p_id,p_token,p_success,p_http,p_error,p_retry);$$;
revoke all on function public.manage_webhooks(text,jsonb),public.claim_webhook_deliveries(),public.ack_webhook_delivery(uuid,uuid,boolean,integer,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.manage_webhooks(text,jsonb) to authenticated;
grant execute on function public.claim_webhook_deliveries(),public.ack_webhook_delivery(uuid,uuid,boolean,integer,text,boolean) to service_role;
notify pgrst,'reload schema';

-- Removing an account also removes its signing secrets from Vault.
create function apoiarcred_private.wh_cleanup() returns trigger language plpgsql security definer set search_path='' as $$begin delete from vault.secrets where id=old.secret_id;return null;end $$;
revoke all on function apoiarcred_private.wh_cleanup() from public,anon,authenticated,service_role;
create trigger cleanup_webhook_secret after delete on apoiarcred_private.webhooks for each row execute function apoiarcred_private.wh_cleanup();

-- Partner integration capability (after partner and webhook setup)
-- Integration access is an explicit administrator-managed account capability.
alter table apoiarcred_private.user_profiles add column if not exists allow_integrations boolean not null default false;
create or replace function apoiarcred_private.can_integrate(uid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from apoiarcred_private.user_profiles p where p.user_id=uid and p.active and (p.role='admin' or p.allow_integrations));
$$;
revoke all on function apoiarcred_private.can_integrate(uuid) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.can_integrate(uuid) to service_role;
create or replace function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'allow_integrations',coalesce(p.active and (p.role='admin' or p.allow_integrations),false),
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid;
$$;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg((to_jsonb(p)-'created_by')||jsonb_build_object('access',apoiarcred_private.access_for(p.user_id)) order by p.created_at desc),'[]') into result from apoiarcred_private.user_profiles p where role='partner';return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null then raise insufficient_privilege;end if;
 if p_action='create' and exists(select 1 from apoiarcred_private.user_profiles where user_id=uid) then raise exception 'Perfil já existe.';end if;
 if p_action='update' and not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='partner') then raise insufficient_privilege;end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' not in ('digimais_saldo_parcela','tjba_margem') or item->>'service' is null or (item->>'daily_limit')::int not between 0 and 100000 then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_input ? 'allow_integrations' and jsonb_typeof(p_input->'allow_integrations') is distinct from 'boolean' then raise exception 'Permissão de integrações inválida.';end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,allow_integrations,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),coalesce((p_input->>'allow_integrations')::boolean,false),p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),allow_integrations=coalesce((p_input->>'allow_integrations')::boolean,allow_integrations),updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;

create or replace function apoiarcred_private.manage_api_tokens(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); secret text; scopes text[]; expires timestamptz; result jsonb; tid uuid;
begin
 if uid is null or not apoiarcred_private.can_integrate(uid) then raise insufficient_privilege using message='Integrações não estão liberadas para esta conta.';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'prefix',t.prefix,'scopes',t.scopes,'created_at',t.created_at,'expires_at',t.expires_at,'revoked_at',t.revoked_at,'last_used_at',t.last_used_at) order by t.created_at desc),'[]') into result from apoiarcred_private.api_tokens t where t.user_id=uid;return result;
 elsif p_action='revoke' then
  update apoiarcred_private.api_tokens set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=(p_input->>'id')::uuid and user_id=uid;
  if not found then raise insufficient_privilege;end if;return '{"revoked":true}';
 elsif p_action<>'create' then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 80 then raise exception 'Informe nome de até 80 caracteres.';end if;
 select coalesce(array_agg(distinct x),'{}') into scopes from jsonb_array_elements_text(p_input->'scopes') x;
 if cardinality(scopes)=0 or not scopes<@array['read','consultas:create','campanhas:write'] then raise exception 'Permissões inválidas.';end if;
 expires=nullif(p_input->>'expires_at','')::timestamptz;
 if expires is not null and (expires<=now() or expires>now()+interval '366 days') then raise exception 'Validade deve estar entre agora e um ano.';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if (select count(*) from apoiarcred_private.api_tokens where user_id=uid and revoked_at is null and (expires_at is null or expires_at>now()))>=20 then raise exception 'Limite de 20 tokens ativos. Revogue um token antes.';end if;
 secret='apc_'||encode(extensions.gen_random_bytes(32),'hex');
 insert into apoiarcred_private.api_tokens(user_id,name,token_hash,prefix,scopes,expires_at)
 values(uid,btrim(p_input->>'name'),encode(extensions.digest(secret,'sha256'),'hex'),left(secret,12),scopes,expires) returning id into tid;
 return jsonb_build_object('id',tid,'token',secret,'expires_at',expires);
end $$;

create or replace function public.api_execute(p_hash text,p_method text,p_route text,p_payload jsonb default '{}',p_key text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare t apoiarcred_private.api_tokens;scope text;fingerprint text;cached apoiarcred_private.api_idempotency;result jsonb;
begin
 select * into t from apoiarcred_private.api_tokens where token_hash=p_hash for update;
 if not found or t.revoked_at is not null or (t.expires_at is not null and t.expires_at<=now()) then return apoiarcred_private.api_error(401,'invalid_token','Token inválido, expirado ou revogado.');end if;
 if not apoiarcred_private.can_integrate(t.user_id) then return apoiarcred_private.api_error(403,'integrations_disabled','Integrações não estão liberadas para esta conta.');end if;
 scope=case when p_method='GET' or p_route='/leads/buscar' then 'read' when p_route='/consultas' then 'consultas:create' else 'campanhas:write' end;
 if not scope=any(t.scopes) then return apoiarcred_private.api_error(403,'insufficient_scope','O token não possui esta permissão.');end if;
 if t.rate_window is null or t.rate_window<now()-interval '1 minute' then t.rate_count=0;t.rate_window=now();end if;
 if t.rate_count>=120 then return apoiarcred_private.api_error(429,'rate_limit','Limite de 120 requisições por minuto.');end if;
 update apoiarcred_private.api_tokens set rate_count=t.rate_count+1,rate_window=t.rate_window,last_used_at=now() where id=t.id;
 if p_method not in ('GET','POST') or jsonb_typeof(p_payload) is distinct from 'object' then return apoiarcred_private.api_error(400,'invalid_request','Requisição inválida.');end if;
 if p_method='POST' and p_route<>'/leads/buscar' and (p_key is null or length(p_key) not between 1 and 128) then return apoiarcred_private.api_error(400,'idempotency_required','Envie Idempotency-Key de 1 a 128 caracteres.');end if;
 delete from apoiarcred_private.api_idempotency where token_id=t.id and created_at<now()-interval '24 hours';
 if p_method='POST' and p_route<>'/leads/buscar' then
  fingerprint=encode(extensions.digest(p_method||p_route||p_payload::text,'sha256'),'hex');
  select * into cached from apoiarcred_private.api_idempotency where token_id=t.id and key=p_key;
  if found then
   if cached.fingerprint<>fingerprint then return apoiarcred_private.api_error(409,'idempotency_conflict','Chave já usada com outra rota ou payload.');end if;
   return cached.response||'{"replayed":true}';
  end if;
 end if;
 begin
  result=apoiarcred_private.api_route(t.user_id,p_method,p_route,p_payload);
 exception when insufficient_privilege then
  result=apoiarcred_private.api_error(403,'partner_permission',sqlerrm);
 when sqlstate 'PT429' then
  result=apoiarcred_private.api_error(429,'daily_limit',sqlerrm);
 when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value or check_violation or not_null_violation then
  result=apoiarcred_private.api_error(422,'validation_error','Dados inválidos. Confira UUIDs, paginação e campos obrigatórios.');
 end;
 if fingerprint is not null and (result->>'status')::integer<300 then insert into apoiarcred_private.api_idempotency(token_id,key,fingerprint,response) values(t.id,p_key,fingerprint,result);end if;
 return result;
end $$;

create or replace function apoiarcred_private.manage_webhooks(action text,input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
<<vars>>
declare uid uuid=auth.uid();hid uuid;w apoiarcred_private.webhooks;secret text;sid uuid;data jsonb;lot record;ev text[];st text[];scope text;service_id text;campaign_id uuid;delivery record;eid uuid;
begin
 if uid is null or not apoiarcred_private.can_integrate(uid) then raise insufficient_privilege;end if;
 if action='list' then
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'-'secret_id'-'manual_window'-'manual_count' order by x.created_at desc),'[]') into data from apoiarcred_private.webhooks x where user_id=uid;return data;
 end if;
 if action='history' then
  hid=nullif(input->>'hook_id','')::uuid;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into data from (
   select d.id,d.hook_id,h.name hook_name,e.id event_id,e.event,e.payload->'consulta'->>'cpf' cpf,e.payload->'campanha'->>'nome' campaign_name,
    d.state,d.attempts,d.total_attempts,d.last_http,d.last_error,d.next_at,d.created_at,d.delivered_at,
    (select coalesce(jsonb_agg(to_jsonb(a)-'claim_token'-'delivery_id' order by attempt desc),'[]') from apoiarcred_private.webhook_attempts a where a.delivery_id=d.id) attempts_log
   from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id join apoiarcred_private.webhook_events e on e.id=d.event_id
   where h.user_id=uid and (hid is null or h.id=hid) order by d.created_at desc limit 50
  ) x;return data;
 end if;
 if action in ('update','toggle','rotate','test') then
  hid=(input->>'id')::uuid;select * into w from apoiarcred_private.webhooks where id=hid and user_id=uid for update;
  if not found then raise insufficient_privilege;end if;
 end if;
 if action='toggle' then
  update apoiarcred_private.webhooks set active=(input->>'active')::boolean,updated_at=clock_timestamp() where id=hid;return '{"ok":true}';
 elsif action='rotate' then
  secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');perform vault.update_secret(w.secret_id,secret);return jsonb_build_object('secret',secret);
 elsif action in ('test','retry') then
  if action='retry' then
   select d.* into delivery from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id where d.id=(input->>'delivery_id')::uuid and h.user_id=uid for update of d;
   if not found then raise insufficient_privilege;end if;
   if delivery.state not in ('delivered','failed') then raise exception 'A entrega já está na fila ou em andamento.';end if;
   select * into w from apoiarcred_private.webhooks where id=delivery.hook_id for update;hid=w.id;
  end if;
  if not w.active then raise exception 'Ative o webhook para testar ou reenviar.';end if;
  if w.manual_window is null or w.manual_window<now()-interval '1 hour' then w.manual_count=0;w.manual_window=now();end if;
  if w.manual_count>=10 then raise exception 'Limite de 10 testes/reenvios manuais por hora neste webhook.';end if;
  update apoiarcred_private.webhooks set manual_window=w.manual_window,manual_count=w.manual_count+1 where id=hid;
  if action='retry' then
   update apoiarcred_private.webhook_deliveries set state='pending',attempts=0,next_at=clock_timestamp(),claim_token=null,locked_until=null,last_error=null where id=delivery.id;
   return jsonb_build_object('delivery_id',delivery.id);
  end if;
  eid=gen_random_uuid();insert into apoiarcred_private.webhook_events(id,event_key,user_id,event,payload) values(eid,'test:'||eid,uid,'webhook.teste',
   jsonb_build_object('event_id',eid,'event','webhook.teste','occurred_at',clock_timestamp(),'test',true,'campanha',null,'consulta',jsonb_build_object('id',gen_random_uuid(),'servico',coalesce(w.service,'digimais_saldo_parcela'),'cpf','00000000000','nome','Cliente fictício de teste','telefone','00000000000','status','concluida','cliente_identificado',true,'resultado_parcial',false,'resultado',case when w.service='tjba_margem' then jsonb_build_object('emprestimo_disponivel',100,'cartao_disponivel',50,'matricula','TESTE-FICTICIO','tipo_servidor',null,'situacao_atual',null) else jsonb_build_object('saldo_liquidacao',1000,'valor_parcela',100,'total_parcelas',96) end)));
  insert into apoiarcred_private.webhook_deliveries(hook_id,event_id) values(hid,eid) returning id into hid;return jsonb_build_object('delivery_id',hid);
 elsif action not in ('create','update') then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(input->>'name')),0) not between 1 and 100 or coalesce(length(input->>'url'),0) not between 9 and 2048 or input->>'url'!~'^https://[^/@#[:space:]]+(/[^#[:space:]]*)?$' then raise exception 'Informe nome e URL HTTPS pública válida, sem usuário, senha ou fragmento.';end if;
 scope=input->>'scope';service_id=nullif(input->>'service','');campaign_id=nullif(input->>'campaign_id','')::uuid;
 if scope is null or scope not in ('all','individual','campaign') or (service_id is not null and service_id not in ('digimais_saldo_parcela','tjba_margem')) then raise exception 'Origem ou serviço inválido.';end if;
 if scope='campaign' then
  select * into lot from apoiarcred_private.api_campaign_rows c where c.id=vars.campaign_id and c.user_id=uid and c.tipo='campanha';
  if not found then raise insufficient_privilege;end if;service_id=lot.servico;
 else campaign_id=null;end if;
 select array_agg(distinct x) into ev from jsonb_array_elements_text(input->'events') x;
 select array_agg(distinct x) into st from jsonb_array_elements_text(input->'statuses') x;
 if coalesce(cardinality(ev),0)=0 or not ev<@array['consulta.finalizada','campanha.finalizada'] or (scope='individual' and 'campanha.finalizada'=any(ev)) then raise exception 'Escolha eventos válidos.';end if;
 if coalesce(cardinality(st),0)=0 or not st<@array['concluida','erro','revisao','nao_cliente','nao_localizado','nao_encontrado'] or coalesce(input->>'client_filter','') not in ('all','client','nonclient','unknown') then raise exception 'Filtros de resultado inválidos.';end if;
 if action='create' then
  perform pg_advisory_xact_lock(hashtextextended(uid::text,11));
  if (select count(*) from apoiarcred_private.webhooks where user_id=uid)>=20 then raise exception 'Limite de 20 webhooks por conta.';end if;
  hid=gen_random_uuid();secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');sid=vault.create_secret(secret,'apoiarcred-webhook-'||hid);
  insert into apoiarcred_private.webhooks(id,user_id,name,url,active,scope,service,campaign_id,events,statuses,client_filter,include_partial,secret_id)
  values(hid,uid,btrim(input->>'name'),input->>'url',coalesce((input->>'active')::boolean,true),scope,service_id,campaign_id,ev,st,input->>'client_filter',coalesce((input->>'include_partial')::boolean,true),sid);
 else
  update apoiarcred_private.webhooks set name=btrim(input->>'name'),url=input->>'url',active=coalesce((input->>'active')::boolean,true),scope=vars.scope,service=service_id,campaign_id=vars.campaign_id,events=ev,statuses=st,client_filter=input->>'client_filter',include_partial=coalesce((input->>'include_partial')::boolean,true),updated_at=clock_timestamp() where id=hid;
 end if;
 return jsonb_build_object('id',hid,'secret',secret);
end $$;

create or replace function apoiarcred_private.wh_enqueue(uid uuid,event_key text,event_name text,body jsonb,service_id text,lot_id uuid,lot_type text,status text,client boolean,partial_result boolean) returns uuid
language plpgsql security definer set search_path='' as $$
<<vars>>
declare eid uuid=gen_random_uuid();h record;inserted_id uuid;begin
 if not apoiarcred_private.can_integrate(uid) then return null;end if;
 for h in select * from apoiarcred_private.webhooks w where w.user_id=uid and w.active and event_name=any(w.events)
 and (w.service is null or w.service=service_id)
 and (w.scope='all' or w.scope='individual' and lot_type='individual' or w.scope='campaign' and w.campaign_id=lot_id)
 and (event_name='campanha.finalizada' or (status=any(w.statuses) and (w.include_partial or not partial_result)
 and (w.client_filter='all' or w.client_filter='client' and client is true or w.client_filter='nonclient' and client is false or w.client_filter='unknown' and client is null))) loop
  insert into apoiarcred_private.webhook_events(id,event_key,user_id,event,payload)
  values(eid,event_key,uid,event_name,body||jsonb_build_object('event_id',eid,'event',event_name))
  on conflict on constraint webhook_events_event_key_key do update set event_key=excluded.event_key returning id into inserted_id;
  eid=inserted_id;
  insert into apoiarcred_private.webhook_deliveries(hook_id,event_id) values(h.id,eid) on conflict do nothing;
 end loop;return eid;
end $$;

create or replace function apoiarcred_private.wh_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb;lot record;result jsonb;client boolean;partial_result boolean;service_id text;begin
 r=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;service_id=r->>'servico';
 if tg_op='UPDATE' and new.status=old.status and new.consultado_em is not distinct from old.consultado_em then return new;end if;
 if tg_table_name='consulta_jobs' then select id,user_id,nome,tipo into lot from public.consulta_lotes where id=(r->>'lote_id')::uuid;
 else select id,user_id,nome,tipo into lot from public.tjba_lotes where id=(r->>'lote_id')::uuid;end if;
 if not found then return null;end if;
 if not apoiarcred_private.can_integrate(lot.user_id) then return null;end if;
 if tg_op='UPDATE' and old.status='processando' and new.status in ('concluida','nao_cliente','nao_localizado','nao_encontrado','erro','revisao') and new.consultado_em is not null then
  result=apoiarcred_private.wh_result(service_id,r);client=apoiarcred_private.wh_client(service_id,new.status,result);partial_result=client is true and new.status<>'concluida';
  perform apoiarcred_private.wh_enqueue(new.user_id,'consulta:'||tg_table_name||':'||new.id||':'||new.attempts||':'||new.consultado_em::text,'consulta.finalizada',
   jsonb_build_object('occurred_at',new.consultado_em,'campanha',case when lot.tipo='campanha' then jsonb_build_object('id',lot.id,'nome',lot.nome) else null end,
   'consulta',jsonb_build_object('id',new.id,'referencia_externa',r->'referencia_externa','servico',service_id,'convenio',r->'convenio','cpf',new.cpf,'nome',new.nome,'telefone',new.telefone,'status',new.status,'cliente_identificado',client,'resultado_parcial',partial_result,'mensagem',left(new.message,1000),'resultado',result)),
   service_id,lot.id,lot.tipo,new.status,client,partial_result);
 end if;
 if lot.tipo='campanha' and exists(select 1 from apoiarcred_private.webhooks w where w.user_id=lot.user_id and w.active and 'campanha.finalizada'=any(w.events) and w.scope<>'individual' and (w.service is null or w.service=service_id) and (w.scope='all' or w.campaign_id=lot.id)) then
  insert into apoiarcred_private.webhook_campaign_dirty(service,campaign_id,user_id) values(service_id,lot.id,lot.user_id)
  on conflict(service,campaign_id) do update set touched_at=clock_timestamp(),checked_at=null;
 end if;
 return null;
end $$;

create or replace function apoiarcred_private.wh_campaigns() returns void language plpgsql security definer set search_path='' as $$
declare dirty record;lot record;r jsonb;pending integer;total integer;last_result timestamptz;begin
 delete from apoiarcred_private.webhook_campaign_dirty where not apoiarcred_private.can_integrate(user_id);
 for dirty in select * from apoiarcred_private.webhook_campaign_dirty order by checked_at nulls first,touched_at limit 20 for update skip locked loop
  select * into lot from apoiarcred_private.api_campaign_rows where id=dirty.campaign_id and user_id=dirty.user_id and tipo='campanha';
  if not found then delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=dirty.campaign_id;continue;end if;
  select count(*),count(*) filter(where status in ('aguardando','processando')),max(consultado_em),
   jsonb_build_object('total',count(*),'clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is true),
    'nao_clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is false),'indeterminados',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is null),
    'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'))
   into total,pending,last_result,r from apoiarcred_private.api_lead_rows where campanha_id=lot.id and user_id=lot.user_id;
  if total>0 and pending=0 and last_result is not null then
   perform apoiarcred_private.wh_enqueue(lot.user_id,'campanha:'||dirty.service||':'||lot.id||':'||encode(extensions.digest(r::text||last_result::text,'sha256'),'hex'),'campanha.finalizada',
    jsonb_build_object('occurred_at',clock_timestamp(),'campanha',jsonb_build_object('id',lot.id,'nome',lot.nome,'servico',lot.servico,'convenio',lot.convenio),'relatorio',r),lot.servico,lot.id,'campanha',null,null,false);
   delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=lot.id;
  else update apoiarcred_private.webhook_campaign_dirty set checked_at=clock_timestamp() where service=dirty.service and campaign_id=lot.id;end if;
 end loop;
end $$;

create or replace function apoiarcred_private.wh_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare d record;result jsonb='[]';token uuid;begin
 perform apoiarcred_private.wh_campaigns();
 update apoiarcred_private.webhook_deliveries set state='failed',last_error='Confirmação da entrega não recebida após o limite de tentativas.' where state='delivering' and locked_until<now() and attempts>=8;
 for d in select q.id from apoiarcred_private.webhook_deliveries q join apoiarcred_private.webhooks w on w.id=q.hook_id
 join apoiarcred_private.user_profiles p on p.user_id=w.user_id and p.active and (p.role='admin' or p.allow_integrations)
 where w.active and q.attempts<8 and q.next_at<=now() and (q.state in ('pending','retry') or q.state='delivering' and q.locked_until<now())
 order by q.next_at,q.created_at limit 2 for update of q skip locked loop
  update apoiarcred_private.webhook_attempts set finished_at=clock_timestamp(),error='Confirmação da tentativa anterior não recebida.' where delivery_id=d.id and finished_at is null;
  token=gen_random_uuid();
  update apoiarcred_private.webhook_deliveries set state='delivering',attempts=attempts+1,total_attempts=total_attempts+1,claim_token=token,locked_until=now()+interval '2 minutes' where id=d.id;
  insert into apoiarcred_private.webhook_attempts(delivery_id,attempt,claim_token) select id,total_attempts,token from apoiarcred_private.webhook_deliveries where id=d.id;
  select result||jsonb_build_array(jsonb_build_object('id',q.id,'claim_token',token,'event_id',e.id,'payload',e.payload,'url',w.url,'secret',s.decrypted_secret)) into result
  from apoiarcred_private.webhook_deliveries q join apoiarcred_private.webhooks w on w.id=q.hook_id join apoiarcred_private.webhook_events e on e.id=q.event_id left join vault.decrypted_secrets s on s.id=w.secret_id where q.id=d.id;
 end loop;return result;
end $$;
notify pgrst,'reload schema';

-- Remove campaign row quotas for active administrators. Partner limits remain in force.
create or replace function public.create_consulta_campaign(p_nome text,p_items jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare campaign_id uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe um nome de campanha com até 160 caracteres.'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.'; end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>1000 and not public.am_i_admin() then raise exception 'Envie entre 1 e 1000 clientes.'; end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados na campanha.'; end if;
 insert into public.consulta_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into campaign_id;
 insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone)
 select campaign_id,auth.uid(),x.item->>'nome',x.item->>'cpf',x.item->>'telefone' from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return campaign_id;
end $$;

create or replace function public.create_tjba_campaign(p_nome text,p_items jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>1000 and not public.am_i_admin() then raise exception 'Envie de 1 a 1.000 clientes.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.nome),''),'CPF '||x.cpf),x.cpf,coalesce(x.telefone,'') from jsonb_to_recordset(p_items) x(nome text,cpf text,telefone text);
 return cid;
end $$;

create or replace function public.create_consigx_campaign(p_nome text,p_items jsonb,p_convenio text) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>1000 and not public.am_i_admin() then raise exception 'Envie de 1 a 1.000 clientes.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo,convenio) values(btrim(p_nome),'campanha',p_convenio) returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.item->>'nome'),''),'CPF '||(x.item->>'cpf')),x.item->>'cpf',coalesce(x.item->>'telefone','') from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return cid;
end $$;

create or replace function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
<<vars>>
declare parts text[]=string_to_array(trim(both '/' from route),'/'); cid uuid; item_id uuid; c record;
 service text; convenio text; lots text; jobs text; item jsonb; idx integer=0; cpf text; nome text; phone text; ref text;
 accepted jsonb='[]';duplicates jsonb='[]';rejected jsonb='[]';data jsonb;counts jsonb; total integer; n integer;
 page integer=greatest(1,coalesce((p->>'page')::integer,1));size integer=least(100,greatest(1,coalesce((p->>'page_size')::integer,50)));
begin
 if method='GET' and route='/servicos' then return apoiarcred_private.api_response(200,'{"data":[{"id":"digimais_saldo_parcela","campos_obrigatorios":["nome","cpf","telefone"]},{"id":"tjba_margem","campos_obrigatorios":["cpf"],"convenios":["tjba","dpeba","embasa","saeb","suprev"]}]}');end if;
 if method='GET' and route='/campanhas' then
  select count(*) into total from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean);
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean) order by created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 if method='POST' and route in ('/campanhas','/consultas') then
  service=coalesce(p->>'servico','digimais_saldo_parcela');convenio=coalesce(p->>'convenio','tjba');
  if service not in ('digimais_saldo_parcela','tjba_margem') or (service='tjba_margem' and convenio not in ('tjba','dpeba','embasa','saeb','suprev')) then return apoiarcred_private.api_error(422,'invalid_service','Serviço ou convênio inválido.');end if;
  nome=case when route='/consultas' then 'Consulta individual via API' else btrim(p->>'nome') end;
  if coalesce(length(nome),0) not between 1 and 160 then return apoiarcred_private.api_error(422,'invalid_name','Informe nome de campanha com até 160 caracteres.');end if;
  lots=case when service='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;
  jobs=case when service='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  -- Individual input validated before creating its lot; all changes atomic.
  if route='/consultas' then
   item=p;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');
   if cpf!~'^[0-9]{11}$' or (service='digimais_saldo_parcela' and (coalesce(length(btrim(item->>'nome')),0) not between 1 and 160 or phone!~'^[0-9]{10,13}$')) or length(coalesce(item->>'referencia_externa',''))>160 then return apoiarcred_private.api_error(422,'invalid_lead','CPF de 11 dígitos; Digi+ exige nome e telefone com DDD.');end if;
  end if;
  if service='tjba_margem' then
   insert into public.tjba_lotes(user_id,nome,tipo,convenio,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,convenio,route='/campanhas') returning id into cid;
  else
   insert into public.consulta_lotes(user_id,nome,tipo,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,route='/campanhas') returning id into cid;
  end if;
  if route='/consultas' then
   execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(btrim(item->>'nome'),''),'CPF '||cpf),cpf,phone,item->>'referencia_externa';
   return apoiarcred_private.api_response(202,jsonb_build_object('id',item_id,'campanha_id',cid,'status','aguardando'));
  end if;
  return apoiarcred_private.api_response(201,jsonb_build_object('id',cid,'nome',nome,'servico',service,'convenio',case when service='tjba_margem' then convenio else null end,'paused',true));
 end if;
 if parts[1]='campanhas' and cardinality(parts) between 2 and 3 then
  cid=parts[2]::uuid;
  select * into c from apoiarcred_private.api_campaign_rows where id=cid and user_id=uid and tipo='campanha';
  if not found then return apoiarcred_private.api_error(404,'not_found','Campanha não encontrada.');end if;
  lots=case when c.servico='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;jobs=case when c.servico='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  if method='GET' and cardinality(parts)=2 then
   select jsonb_build_object('total',count(*),'clientes',count(*) filter(where status='concluida'),'nao_clientes',count(*) filter(where status in ('nao_cliente','nao_localizado','nao_encontrado')),'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'),'aguardando',count(*) filter(where status='aguardando'),'processando',count(*) filter(where status='processando')) into counts from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid;
   return apoiarcred_private.api_response(200,(to_jsonb(c)-'user_id')||jsonb_build_object('relatorio',counts));
  elsif method='POST' then
   execute format('select paused from public.%I where id=$1 and user_id=$2 for update',lots) into c.paused using cid,uid;
   if parts[3] in ('iniciar','pausar') then
    execute format('update public.%I set paused=$1 where id=$2 and user_id=$3',lots) using parts[3]='pausar',cid,uid;
    return apoiarcred_private.api_response(200,jsonb_build_object('id',cid,'paused',parts[3]='pausar'));
   elsif parts[3]='leads' then
    if not c.paused then return apoiarcred_private.api_error(409,'campaign_running','Pause a campanha antes de adicionar leads.');end if;
    if jsonb_typeof(p->'leads') is distinct from 'array' then return apoiarcred_private.api_error(422,'invalid_leads','Envie leads como uma lista.');end if;
    if jsonb_array_length(p->'leads')=0 then return apoiarcred_private.api_error(422,'invalid_leads','Envie pelo menos um lead.');end if;
    if jsonb_array_length(p->'leads')>1000 and not apoiarcred_private.is_admin(uid) then return apoiarcred_private.api_error(422,'invalid_leads','Envie de 1 a 1000 leads.');end if;
    for item in select value from jsonb_array_elements(p->'leads') loop
     idx=idx+1;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');nome=btrim(item->>'nome');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');ref=item->>'referencia_externa';
     if jsonb_typeof(item) is distinct from 'object' or cpf!~'^[0-9]{11}$' or coalesce(length(nome),0)>160 or length(coalesce(ref,''))>160 or (c.servico='digimais_saldo_parcela' and (coalesce(length(nome),0)=0 or phone!~'^[0-9]{10,13}$')) then
      rejected=rejected||jsonb_build_array(jsonb_build_object('linha',idx,'code','invalid_lead','message','Confira CPF, nome, telefone e referência.'));continue;
     end if;
     -- Parent row lock serializes API inserts with API pause/start; no historical duplicates are deleted.
     if exists(select 1 from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid and api_lead_rows.cpf=vars.cpf) then
      duplicates=duplicates||jsonb_build_array(jsonb_build_object('linha',idx,'cpf',cpf));continue;
     end if;
     execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(nome,''),'CPF '||cpf),cpf,phone,ref;
     accepted=accepted||jsonb_build_array(jsonb_build_object('linha',idx,'id',item_id,'cpf',cpf));
    end loop;
    return apoiarcred_private.api_response(200,jsonb_build_object('accepted',accepted,'duplicates',duplicates,'rejected',rejected));
   elsif parts[3]='repetir-revisoes' then
    if c.servico='tjba_margem' then
     update public.tjba_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,matricula=null,tipo_servidor=null,situacao_atual=null,emprestimo_disponivel=null,cartao_disponivel=null,tjba_status=null,resultado_tjba=null where lote_id=cid and user_id=uid and status in ('erro','revisao');
    else
     update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,saldo_liquidacao=null,total_parcelas=null,valor_parcela=null,resultado_saldo=null,resultado_parcela=null where lote_id=cid and user_id=uid and status in ('erro','revisao');
    end if;
    get diagnostics n=row_count;return apoiarcred_private.api_response(202,jsonb_build_object('reenfileirados',n,'paused',c.paused));
   end if;
  end if;
 end if;
 if (method='GET' and parts[1] in ('leads','consultas') and cardinality(parts)=2) then
  select to_jsonb(x)-'user_id' into data from apoiarcred_private.api_lead_rows x where id=parts[2]::uuid and user_id=uid;
  if data is null then return apoiarcred_private.api_error(404,'not_found','Registro não encontrado.');end if;
  return apoiarcred_private.api_response(200,data);
 end if;
 if (method='POST' and route='/leads/buscar') or (method='GET' and parts[1]='campanhas' and parts[3]='leads' and cardinality(parts)=3) then
  cpf=case when method='POST' then regexp_replace(coalesce(p->>'cpf',''),'[^0-9]','','g') else null end;
  if method='POST' and cpf!~'^[0-9]{11}$' then return apoiarcred_private.api_error(422,'invalid_cpf','Informe CPF com 11 dígitos.');end if;
  cid=case when method='GET' then parts[2]::uuid else nullif(p->>'campanha_id','')::uuid end;
  select count(*) into total from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status');
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status') order by case when method='GET' then queue_order end,created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 return apoiarcred_private.api_error(404,'route_not_found','Rota não encontrada.');
end $$;

notify pgrst,'reload schema';
-- Private optional credentials per administrator and robot.
create table if not exists apoiarcred_private.tjba_robot_credentials (
 user_id uuid not null references auth.users(id) on delete cascade,
 slot integer not null check(slot between 1 and 3),
 username text not null,
 secret_id uuid not null,
 enabled boolean not null default true,
 updated_at timestamptz not null default now(),
 primary key(user_id,slot)
);
alter table apoiarcred_private.tjba_robot_credentials enable row level security;
revoke all on apoiarcred_private.tjba_robot_credentials from public,anon,authenticated,service_role;
alter table public.tjba_jobs add column if not exists robot_slot integer check(robot_slot between 1 and 3);
create index if not exists tjba_jobs_running_owner on public.tjba_jobs(user_id) where status='processando';

create or replace function apoiarcred_private.tjba_robot_login(p_uid uuid,p_slot integer)
returns table(username text,secret_id uuid,enabled boolean,updated_at timestamptz)
language sql stable set search_path='' as $$
 select x.username,x.secret_id,x.enabled,x.updated_at
 from (
  select r.username,r.secret_id,r.enabled,r.updated_at,0 priority
  from apoiarcred_private.tjba_robot_credentials r
  where r.user_id=p_uid and r.slot=p_slot and r.enabled and apoiarcred_private.is_admin(p_uid)
  union all
  select c.username,c.secret_id,c.enabled,c.updated_at,1
  from apoiarcred_private.tjba_credentials c where c.user_id=p_uid
 ) x order by x.priority limit 1;
$$;
revoke all on function apoiarcred_private.tjba_robot_login(uuid,integer) from public,anon,authenticated,service_role;

create or replace function apoiarcred_private.manage_tjba_robot_credentials(
 p_slot integer default null,p_username text default null,p_password text default null,p_enabled boolean default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); previous apoiarcred_private.tjba_robot_credentials;
begin
 if not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_slot is not null then
  if p_slot not between 1 and 3 or p_enabled is null or coalesce(length(btrim(p_username)),0) not between 1 and 160 or length(coalesce(p_password,''))>512 then
   raise exception 'Informe um robô, usuário e senha válidos.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text||':tjba-robot:'||p_slot,0));
  select * into previous from apoiarcred_private.tjba_robot_credentials where user_id=uid and slot=p_slot;
  if coalesce(p_password,'')='' and (previous.secret_id is null or previous.username<>btrim(p_username)) then
   raise exception 'Informe a senha para esse usuário.';
  end if;
  if previous.secret_id is null then
   previous.secret_id=vault.create_secret(p_password,'apoiarcred-tjba-robot-'||uid||'-'||p_slot);
  elsif coalesce(p_password,'')<>'' then
   perform vault.update_secret(previous.secret_id,p_password);
  end if;
  insert into apoiarcred_private.tjba_robot_credentials(user_id,slot,username,secret_id,enabled,updated_at)
  values(uid,p_slot,btrim(p_username),previous.secret_id,p_enabled,clock_timestamp())
  on conflict(user_id,slot) do update set username=excluded.username,enabled=excluded.enabled,updated_at=excluded.updated_at;
 end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('slot',r.slot,'username',r.username,'enabled',r.enabled) order by r.slot),'[]')
         from apoiarcred_private.tjba_robot_credentials r where r.user_id=uid);
end $$;
revoke all on function apoiarcred_private.manage_tjba_robot_credentials(integer,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.manage_tjba_robot_credentials(integer,text,text,boolean) to authenticated;
create or replace function public.manage_tjba_robot_credentials(
 p_slot integer default null,p_username text default null,p_password text default null,p_enabled boolean default null
) returns jsonb language sql security invoker set search_path='' as $$
 select apoiarcred_private.manage_tjba_robot_credentials(p_slot,p_username,p_password,p_enabled);
$$;
revoke all on function public.manage_tjba_robot_credentials(integer,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.manage_tjba_robot_credentials(integer,text,text,boolean) to authenticated;

create or replace function apoiarcred_private.get_tjba_robot_credentials(p_user_id uuid,p_slot integer)
returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('username',c.username,'password',v.decrypted_secret,'enabled',c.enabled,'revision',c.updated_at)
 from apoiarcred_private.tjba_robot_login(p_user_id,p_slot) c join vault.decrypted_secrets v on v.id=c.secret_id;
$$;
revoke all on function apoiarcred_private.get_tjba_robot_credentials(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.get_tjba_robot_credentials(uuid,integer) to service_role;
create or replace function public.get_tjba_robot_credentials(p_user_id uuid,p_slot integer)
returns jsonb language sql security invoker set search_path='' as $$
 select apoiarcred_private.get_tjba_robot_credentials(p_user_id,p_slot);
$$;
revoke all on function public.get_tjba_robot_credentials(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.get_tjba_robot_credentials(uuid,integer) to service_role;

create or replace function apoiarcred_private.claim_consigx_for_robot(p_slot integer)
returns setof public.tjba_jobs language plpgsql security definer set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is not null and p_slot not between 1 and 3 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 -- Serialize reservations, while actual portal work runs in parallel across logins.
 if not pg_try_advisory_xact_lock(763211,1) then return;end if;
 select l.id into selected_lot
 from public.tjba_lotes l
 left join lateral apoiarcred_private.tjba_robot_login(l.user_id,p_slot) login on true
 where not l.paused
 and exists(select 1 from public.tjba_jobs j where j.lote_id=l.id and j.status='aguardando')
 and not exists(
  select 1 from public.tjba_jobs running
  left join lateral apoiarcred_private.tjba_robot_login(running.user_id,running.robot_slot) other on true
  where running.status='processando'
  and (lower(btrim(other.username))=lower(btrim(login.username))
       or (running.user_id=l.user_id and (login.username is null or other.username is null)))
 )
 order by l.created_at,l.id limit 1 for share of l;
 if selected_lot is null then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.tjba_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1)
 returning *;
end $$;
revoke all on function apoiarcred_private.claim_consigx_for_robot(integer) from public,anon,authenticated,service_role;
grant execute on function apoiarcred_private.claim_consigx_for_robot(integer) to service_role;

create or replace function public.claim_tjba_job_for_robot(p_slot integer) returns setof public.tjba_jobs
language sql security invoker set search_path='' as $$
 select * from apoiarcred_private.claim_consigx_for_robot(p_slot);
$$;
revoke all on function public.claim_tjba_job_for_robot(integer) from public,anon,authenticated,service_role;
grant execute on function public.claim_tjba_job_for_robot(integer) to service_role;

create or replace function public.claim_tjba_job() returns setof public.tjba_jobs
language sql security invoker set search_path='' as $$
 select * from apoiarcred_private.claim_consigx_for_robot(null);
$$;
notify pgrst,'reload schema';

-- A single authenticated entry point for the shared and per-robot logins.
-- Existing routines retain validation, owner scoping and Vault secret IDs.
create or replace function public.manage_consigx_access(
 p_slot integer default null,
 p_username text default null,
 p_password text default null,
 p_enabled boolean default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 admin boolean;
 robot_access jsonb := '[]'::jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 admin := public.am_i_admin();
 if p_slot is not null then
  if p_slot not between 0 and 3 or p_enabled is null then
   raise exception 'Selecione um acesso válido.';
  end if;
  if p_slot=0 then
   perform public.save_tjba_credentials(p_username,p_password,p_enabled);
  else
   if not admin then raise insufficient_privilege;end if;
   robot_access := public.manage_tjba_robot_credentials(p_slot,p_username,p_password,p_enabled);
  end if;
 end if;
 if admin and (p_slot is null or p_slot=0) then
  robot_access := public.manage_tjba_robot_credentials();
 end if;
 return jsonb_build_object('shared',public.tjba_credentials_status(),'robots',robot_access);
end $$;
revoke all on function public.manage_consigx_access(integer,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.manage_consigx_access(integer,text,text,boolean) to authenticated;
notify pgrst,'reload schema';

-- Admin jobs require an enabled credential for the requesting robot.
-- Partner accounts have a single credential and can run on robot 1.
create or replace function apoiarcred_private.tjba_robot_login(p_uid uuid,p_slot integer)
returns table(username text,secret_id uuid,enabled boolean,updated_at timestamptz)
language sql stable set search_path='' as $$
 select r.username,r.secret_id,r.enabled,r.updated_at
 from apoiarcred_private.tjba_robot_credentials r
 join apoiarcred_private.user_profiles p on p.user_id=r.user_id
 where r.user_id=p_uid and r.slot=p_slot and r.enabled and p.role='admin' and p.active
 union all
 select c.username,c.secret_id,c.enabled,c.updated_at
 from apoiarcred_private.tjba_credentials c
 join apoiarcred_private.user_profiles p on p.user_id=c.user_id
 where c.user_id=p_uid and coalesce(p_slot,1)=1 and c.enabled and p.role='partner' and p.active;
$$;

create or replace function apoiarcred_private.claim_consigx_for_robot(p_slot integer)
returns setof public.tjba_jobs language plpgsql security definer set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is not null and p_slot not between 1 and 3 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 -- Serialize reservations, while actual portal work runs in parallel across logins.
 if not pg_try_advisory_xact_lock(763211,1) then return;end if;
 select l.id into selected_lot
 from public.tjba_lotes l
 join lateral apoiarcred_private.tjba_robot_login(l.user_id,p_slot) login on login.enabled
 where not l.paused
 and exists(select 1 from public.tjba_jobs j where j.lote_id=l.id and j.status='aguardando')
 and not exists(
  select 1 from public.tjba_jobs running
  left join lateral apoiarcred_private.tjba_robot_login(running.user_id,running.robot_slot) other on true
  where running.status='processando'
  and (lower(btrim(other.username))=lower(btrim(login.username))
       or (running.user_id=l.user_id and (login.username is null or other.username is null)))
 )
 order by l.created_at,l.id limit 1 for share of l;
 if selected_lot is null then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.tjba_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1)
 returning *;
end $$;

notify pgrst,'reload schema';

-- Attribute Digi+ reservations to a robot, as already done for ConsigX.
alter table public.consulta_jobs add column if not exists robot_slot integer check(robot_slot between 1 and 3);

create or replace function public.claim_consulta_job_for_robot(p_slot integer) returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is null or p_slot not between 1 and 3 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando'))
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1) returning *;
end $$;
revoke all on function public.claim_consulta_job_for_robot(integer) from public,anon,authenticated,service_role;
grant execute on function public.claim_consulta_job_for_robot(integer) to service_role;
notify pgrst,'reload schema';

-- Track outcomes as workers finish. The campaign row serializes concurrent completions.
alter table public.consulta_jobs drop constraint consulta_jobs_status_check;
alter table public.consulta_jobs add constraint consulta_jobs_status_check check(status in
 ('aguardando','processando','concluida','nao_localizado','nao_cliente','erro','revisao','interrompida'));

alter table public.consulta_lotes add column failure_streak integer not null default 0,
 add column auto_paused boolean not null default false;
alter table public.tjba_lotes add column failure_streak integer not null default 0,
 add column auto_paused boolean not null default false;

create function apoiarcred_private.track_campaign_failures() returns trigger
language plpgsql security definer set search_path='' as $$
declare failed boolean := new.status in ('erro','revisao','interrompida');
begin
 if old.status<>'processando' or new.status in ('processando','aguardando') then return new;end if;
 if tg_table_name='consulta_jobs' then
  update public.consulta_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 else
  update public.tjba_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 end if;
 return new;
end $$;

create function apoiarcred_private.reset_campaign_failures() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.paused and not new.paused then
  new.failure_streak=0;
  new.auto_paused=false;
 end if;
 return new;
end $$;

revoke all on function apoiarcred_private.track_campaign_failures() from public,anon,authenticated;
revoke all on function apoiarcred_private.reset_campaign_failures() from public,anon,authenticated;
create trigger track_campaign_failures after update of status on public.consulta_jobs
 for each row execute function apoiarcred_private.track_campaign_failures();
create trigger track_campaign_failures after update of status on public.tjba_jobs
 for each row execute function apoiarcred_private.track_campaign_failures();
create trigger reset_campaign_failures before update of paused on public.consulta_lotes
 for each row execute function apoiarcred_private.reset_campaign_failures();
create trigger reset_campaign_failures before update of paused on public.tjba_lotes
 for each row execute function apoiarcred_private.reset_campaign_failures();


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
 where lote_id=p_campaign_id and user_id=owner_id and status in ('erro','revisao','interrompida');
 get diagnostics retried = row_count;
 return retried;
end $$;

create or replace function apoiarcred_private.guard_partner_job() returns trigger language plpgsql security definer set search_path='' as $$
declare lot record;
begin
 if tg_op='UPDATE' then
  if new.user_id<>old.user_id or new.lote_id<>old.lote_id or new.servico<>old.servico then raise insufficient_privilege;end if;
  if not (new.status='aguardando' and old.status in ('erro','revisao','interrompida')) then return new;end if;
 end if;
 if tg_table_name='consulta_jobs' then select user_id,tipo,servico into lot from public.consulta_lotes where id=new.lote_id for share;
 else select user_id,tipo,servico into lot from public.tjba_lotes where id=new.lote_id for share;end if;
 if not found or lot.user_id<>new.user_id or lot.servico<>new.servico then raise insufficient_privilege;end if;
 perform apoiarcred_private.check_partner_access(new.user_id,lot.servico,lot.tipo,true);return new;
end $$;

create or replace function apoiarcred_private.api_route(uid uuid,method text,route text,p jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
<<vars>>
declare parts text[]=string_to_array(trim(both '/' from route),'/'); cid uuid; item_id uuid; c record;
 service text; convenio text; lead_status text; lots text; jobs text; item jsonb; idx integer=0; cpf text; nome text; phone text; ref text;
 accepted jsonb='[]';duplicates jsonb='[]';rejected jsonb='[]';data jsonb;counts jsonb; total integer; n integer;
 page integer=greatest(1,coalesce((p->>'page')::integer,1));size integer=least(100,greatest(1,coalesce((p->>'page_size')::integer,50)));
begin
 if method='GET' and route='/servicos' then return apoiarcred_private.api_response(200,'{"data":[{"id":"digimais_saldo_parcela","campos_obrigatorios":["nome","cpf","telefone"]},{"id":"tjba_margem","campos_obrigatorios":["cpf"],"convenios":["tjba","dpeba","embasa","saeb","suprev"]}]}');end if;
 if method='GET' and route='/campanhas' then
  select count(*) into total from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean);
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_campaign_rows where user_id=uid and tipo='campanha' and (p->>'servico' is null or servico=p->>'servico') and (p->>'paused' is null or paused=(p->>'paused')::boolean) order by created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 if method='POST' and route in ('/campanhas','/consultas') then
  service=coalesce(p->>'servico','digimais_saldo_parcela');convenio=coalesce(p->>'convenio','tjba');
  if service not in ('digimais_saldo_parcela','tjba_margem') or (service='tjba_margem' and convenio not in ('tjba','dpeba','embasa','saeb','suprev')) then return apoiarcred_private.api_error(422,'invalid_service','Serviço ou convênio inválido.');end if;
  nome=case when route='/consultas' then 'Consulta individual via API' else btrim(p->>'nome') end;
  if coalesce(length(nome),0) not between 1 and 160 then return apoiarcred_private.api_error(422,'invalid_name','Informe nome de campanha com até 160 caracteres.');end if;
  lots=case when service='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;
  jobs=case when service='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  -- Individual input validated before creating its lot; all changes atomic.
  if route='/consultas' then
   item=p;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');
   if cpf!~'^[0-9]{11}$' or (service='digimais_saldo_parcela' and (coalesce(length(btrim(item->>'nome')),0) not between 1 and 160 or phone!~'^[0-9]{10,13}$')) or length(coalesce(item->>'referencia_externa',''))>160 then return apoiarcred_private.api_error(422,'invalid_lead','CPF de 11 dígitos; Digi+ exige nome e telefone com DDD.');end if;
  end if;
  if service='tjba_margem' then
   insert into public.tjba_lotes(user_id,nome,tipo,convenio,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,convenio,route='/campanhas') returning id into cid;
  else
   insert into public.consulta_lotes(user_id,nome,tipo,paused) values(uid,nome,case when route='/consultas' then 'individual' else 'campanha' end,route='/campanhas') returning id into cid;
  end if;
  if route='/consultas' then
   execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(btrim(item->>'nome'),''),'CPF '||cpf),cpf,phone,item->>'referencia_externa';
   return apoiarcred_private.api_response(202,jsonb_build_object('id',item_id,'campanha_id',cid,'status','aguardando'));
  end if;
  return apoiarcred_private.api_response(201,jsonb_build_object('id',cid,'nome',nome,'servico',service,'convenio',case when service='tjba_margem' then convenio else null end,'paused',true));
 end if;
 -- Full campaign reads take one snapshot and use the same owner and token checks.
 if method='GET' and parts[1]='campanhas' and parts[3]='leads' and
    ((cardinality(parts)=3 and p ? 'all') or (cardinality(parts)=5 and parts[4]='status')) then
  if cardinality(parts)=5 then
   if p<>'{}'::jsonb then
    return apoiarcred_private.api_error(422,'invalid_filter','Informe o status na rota, sem filtros adicionais.');
   end if;
   lead_status=parts[5];
  else
   if p->>'all' is distinct from 'true' or p ? 'page' or p ? 'page_size' then
    return apoiarcred_private.api_error(422,'invalid_filter','Use all=true sem page ou page_size.');
   end if;
   lead_status=p->>'status';
  end if;
  if lead_status is not null and lead_status not in
     ('aguardando','processando','concluida','nao_cliente','nao_localizado','nao_encontrado','erro','revisao','interrompida') then
   return apoiarcred_private.api_error(422,'invalid_status','Status de lead inválido.');
  end if;
  cid=parts[2]::uuid;
  if not exists(select 1 from apoiarcred_private.api_campaign_rows
                where id=cid and user_id=uid and tipo='campanha') then
   return apoiarcred_private.api_error(404,'not_found','Campanha não encontrada.');
  end if;
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id' order by x.queue_order,x.created_at desc,x.id),'[]'::jsonb)
  into data
  from apoiarcred_private.api_lead_rows x
  where x.user_id=uid and x.campanha_id=cid and (lead_status is null or x.status=lead_status);
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'total',jsonb_array_length(data)));
 end if;
 if parts[1]='campanhas' and cardinality(parts) between 2 and 3 then
  cid=parts[2]::uuid;
  select * into c from apoiarcred_private.api_campaign_rows where id=cid and user_id=uid and tipo='campanha';
  if not found then return apoiarcred_private.api_error(404,'not_found','Campanha não encontrada.');end if;
  lots=case when c.servico='tjba_margem' then 'tjba_lotes' else 'consulta_lotes' end;jobs=case when c.servico='tjba_margem' then 'tjba_jobs' else 'consulta_jobs' end;
  if method='GET' and cardinality(parts)=2 then
   select jsonb_build_object('total',count(*),'clientes',count(*) filter(where status='concluida'),'nao_clientes',count(*) filter(where status in ('nao_cliente','nao_localizado','nao_encontrado')),'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'),'interrompidas',count(*) filter(where status='interrompida'),'aguardando',count(*) filter(where status='aguardando'),'processando',count(*) filter(where status='processando')) into counts from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid;
   return apoiarcred_private.api_response(200,(to_jsonb(c)-'user_id')||jsonb_build_object('relatorio',counts));
  elsif method='POST' then
   execute format('select paused from public.%I where id=$1 and user_id=$2 for update',lots) into c.paused using cid,uid;
   if parts[3] in ('iniciar','pausar') then
    execute format('update public.%I set paused=$1 where id=$2 and user_id=$3',lots) using parts[3]='pausar',cid,uid;
    return apoiarcred_private.api_response(200,jsonb_build_object('id',cid,'paused',parts[3]='pausar'));
   elsif parts[3]='leads' then
    if not c.paused then return apoiarcred_private.api_error(409,'campaign_running','Pause a campanha antes de adicionar leads.');end if;
    if jsonb_typeof(p->'leads') is distinct from 'array' then return apoiarcred_private.api_error(422,'invalid_leads','Envie leads como uma lista.');end if;
    if jsonb_array_length(p->'leads')=0 then return apoiarcred_private.api_error(422,'invalid_leads','Envie pelo menos um lead.');end if;
    if jsonb_array_length(p->'leads')>1000 and not apoiarcred_private.is_admin(uid) then return apoiarcred_private.api_error(422,'invalid_leads','Envie de 1 a 1000 leads.');end if;
    for item in select value from jsonb_array_elements(p->'leads') loop
     idx=idx+1;cpf=regexp_replace(coalesce(item->>'cpf',''),'[^0-9]','','g');nome=btrim(item->>'nome');phone=regexp_replace(coalesce(item->>'telefone',''),'[^0-9]','','g');ref=item->>'referencia_externa';
     if jsonb_typeof(item) is distinct from 'object' or cpf!~'^[0-9]{11}$' or coalesce(length(nome),0)>160 or length(coalesce(ref,''))>160 or (c.servico='digimais_saldo_parcela' and (coalesce(length(nome),0)=0 or phone!~'^[0-9]{10,13}$')) then
      rejected=rejected||jsonb_build_array(jsonb_build_object('linha',idx,'code','invalid_lead','message','Confira CPF, nome, telefone e referência.'));continue;
     end if;
     -- Parent row lock serializes API inserts with API pause/start; no historical duplicates are deleted.
     if exists(select 1 from apoiarcred_private.api_lead_rows where campanha_id=cid and user_id=uid and api_lead_rows.cpf=vars.cpf) then
      duplicates=duplicates||jsonb_build_array(jsonb_build_object('linha',idx,'cpf',cpf));continue;
     end if;
     execute format('insert into public.%I(user_id,lote_id,nome,cpf,telefone,referencia_externa) values($1,$2,$3,$4,$5,$6) returning id',jobs) into item_id using uid,cid,coalesce(nullif(nome,''),'CPF '||cpf),cpf,phone,ref;
     accepted=accepted||jsonb_build_array(jsonb_build_object('linha',idx,'id',item_id,'cpf',cpf));
    end loop;
    return apoiarcred_private.api_response(200,jsonb_build_object('accepted',accepted,'duplicates',duplicates,'rejected',rejected));
   elsif parts[3]='repetir-revisoes' then
    if c.servico='tjba_margem' then
     update public.tjba_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,matricula=null,tipo_servidor=null,situacao_atual=null,emprestimo_disponivel=null,cartao_disponivel=null,tjba_status=null,resultado_tjba=null where lote_id=cid and user_id=uid and status in ('erro','revisao');
    else
     update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,saldo_liquidacao=null,total_parcelas=null,valor_parcela=null,resultado_saldo=null,resultado_parcela=null where lote_id=cid and user_id=uid and status in ('erro','revisao','interrompida');
    end if;
    get diagnostics n=row_count;return apoiarcred_private.api_response(202,jsonb_build_object('reenfileirados',n,'paused',c.paused));
   end if;
  end if;
 end if;
 if (method='GET' and parts[1] in ('leads','consultas') and cardinality(parts)=2) then
  select to_jsonb(x)-'user_id' into data from apoiarcred_private.api_lead_rows x where id=parts[2]::uuid and user_id=uid;
  if data is null then return apoiarcred_private.api_error(404,'not_found','Registro não encontrado.');end if;
  return apoiarcred_private.api_response(200,data);
 end if;
 if (method='POST' and route='/leads/buscar') or (method='GET' and parts[1]='campanhas' and parts[3]='leads' and cardinality(parts)=3) then
  cpf=case when method='POST' then regexp_replace(coalesce(p->>'cpf',''),'[^0-9]','','g') else null end;
  if method='POST' and cpf!~'^[0-9]{11}$' then return apoiarcred_private.api_error(422,'invalid_cpf','Informe CPF com 11 dígitos.');end if;
  cid=case when method='GET' then parts[2]::uuid else nullif(p->>'campanha_id','')::uuid end;
  select count(*) into total from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status');
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'),'[]') into data from (select * from apoiarcred_private.api_lead_rows x where user_id=uid and (cid is null or campanha_id=cid) and (vars.cpf is null or x.cpf=vars.cpf) and (p->>'status' is null or status=p->>'status') order by case when method='GET' then queue_order end,created_at desc,id limit size offset (page-1)*size) x;
  return apoiarcred_private.api_response(200,jsonb_build_object('data',data,'pagination',jsonb_build_object('page',page,'page_size',size,'total',total)));
 end if;
 return apoiarcred_private.api_error(404,'route_not_found','Rota não encontrada.');
end $$;

create or replace function apoiarcred_private.wh_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb;lot record;result jsonb;client boolean;partial_result boolean;service_id text;begin
 r=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;service_id=r->>'servico';
 if tg_op='UPDATE' and new.status=old.status and new.consultado_em is not distinct from old.consultado_em then return new;end if;
 if tg_table_name='consulta_jobs' then select id,user_id,nome,tipo into lot from public.consulta_lotes where id=(r->>'lote_id')::uuid;
 else select id,user_id,nome,tipo into lot from public.tjba_lotes where id=(r->>'lote_id')::uuid;end if;
 if not found then return null;end if;
 if not apoiarcred_private.can_integrate(lot.user_id) then return null;end if;
 if tg_op='UPDATE' and old.status='processando' and new.status in ('concluida','nao_cliente','nao_localizado','nao_encontrado','erro','revisao','interrompida') and new.consultado_em is not null then
  result=apoiarcred_private.wh_result(service_id,r);client=apoiarcred_private.wh_client(service_id,new.status,result);partial_result=client is true and new.status<>'concluida';
  perform apoiarcred_private.wh_enqueue(new.user_id,'consulta:'||tg_table_name||':'||new.id||':'||new.attempts||':'||new.consultado_em::text,'consulta.finalizada',
   jsonb_build_object('occurred_at',new.consultado_em,'campanha',case when lot.tipo='campanha' then jsonb_build_object('id',lot.id,'nome',lot.nome) else null end,
   'consulta',jsonb_build_object('id',new.id,'referencia_externa',r->'referencia_externa','servico',service_id,'convenio',r->'convenio','cpf',new.cpf,'nome',new.nome,'telefone',new.telefone,'status',new.status,'cliente_identificado',client,'resultado_parcial',partial_result,'mensagem',left(new.message,1000),'resultado',result)),
   service_id,lot.id,lot.tipo,new.status,client,partial_result);
 end if;
 if lot.tipo='campanha' and exists(select 1 from apoiarcred_private.webhooks w where w.user_id=lot.user_id and w.active and 'campanha.finalizada'=any(w.events) and w.scope<>'individual' and (w.service is null or w.service=service_id) and (w.scope='all' or w.campaign_id=lot.id)) then
  insert into apoiarcred_private.webhook_campaign_dirty(service,campaign_id,user_id) values(service_id,lot.id,lot.user_id)
  on conflict(service,campaign_id) do update set touched_at=clock_timestamp(),checked_at=null;
 end if;
 return null;
end $$;

create or replace function apoiarcred_private.wh_campaigns() returns void language plpgsql security definer set search_path='' as $$
declare dirty record;lot record;r jsonb;pending integer;total integer;last_result timestamptz;begin
 delete from apoiarcred_private.webhook_campaign_dirty where not apoiarcred_private.can_integrate(user_id);
 for dirty in select * from apoiarcred_private.webhook_campaign_dirty order by checked_at nulls first,touched_at limit 20 for update skip locked loop
  select * into lot from apoiarcred_private.api_campaign_rows where id=dirty.campaign_id and user_id=dirty.user_id and tipo='campanha';
  if not found then delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=dirty.campaign_id;continue;end if;
  select count(*),count(*) filter(where status in ('aguardando','processando')),max(consultado_em),
   jsonb_build_object('total',count(*),'clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is true),
    'nao_clientes',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is false),'indeterminados',count(*) filter(where apoiarcred_private.wh_client(servico,status,resultado) is null),
    'erros',count(*) filter(where status='erro'),'revisao',count(*) filter(where status='revisao'),'interrompidas',count(*) filter(where status='interrompida'))
   into total,pending,last_result,r from apoiarcred_private.api_lead_rows where campanha_id=lot.id and user_id=lot.user_id;
  if total>0 and pending=0 and last_result is not null then
   perform apoiarcred_private.wh_enqueue(lot.user_id,'campanha:'||dirty.service||':'||lot.id||':'||encode(extensions.digest(r::text||last_result::text,'sha256'),'hex'),'campanha.finalizada',
    jsonb_build_object('occurred_at',clock_timestamp(),'campanha',jsonb_build_object('id',lot.id,'nome',lot.nome,'servico',lot.servico,'convenio',lot.convenio),'relatorio',r),lot.servico,lot.id,'campanha',null,null,false);
   delete from apoiarcred_private.webhook_campaign_dirty where service=dirty.service and campaign_id=lot.id;
  else update apoiarcred_private.webhook_campaign_dirty set checked_at=clock_timestamp() where service=dirty.service and campaign_id=lot.id;end if;
 end loop;
end $$;

create or replace function apoiarcred_private.manage_webhooks(action text,input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
<<vars>>
declare uid uuid=auth.uid();hid uuid;w apoiarcred_private.webhooks;secret text;sid uuid;data jsonb;lot record;ev text[];st text[];scope text;service_id text;campaign_id uuid;delivery record;eid uuid;
begin
 if uid is null or not apoiarcred_private.can_integrate(uid) then raise insufficient_privilege;end if;
 if action='list' then
  select coalesce(jsonb_agg(to_jsonb(x)-'user_id'-'secret_id'-'manual_window'-'manual_count' order by x.created_at desc),'[]') into data from apoiarcred_private.webhooks x where user_id=uid;return data;
 end if;
 if action='history' then
  hid=nullif(input->>'hook_id','')::uuid;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into data from (
   select d.id,d.hook_id,h.name hook_name,e.id event_id,e.event,e.payload->'consulta'->>'cpf' cpf,e.payload->'campanha'->>'nome' campaign_name,
    d.state,d.attempts,d.total_attempts,d.last_http,d.last_error,d.next_at,d.created_at,d.delivered_at,
    (select coalesce(jsonb_agg(to_jsonb(a)-'claim_token'-'delivery_id' order by attempt desc),'[]') from apoiarcred_private.webhook_attempts a where a.delivery_id=d.id) attempts_log
   from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id join apoiarcred_private.webhook_events e on e.id=d.event_id
   where h.user_id=uid and (hid is null or h.id=hid) order by d.created_at desc limit 50
  ) x;return data;
 end if;
 if action in ('update','toggle','rotate','test') then
  hid=(input->>'id')::uuid;select * into w from apoiarcred_private.webhooks where id=hid and user_id=uid for update;
  if not found then raise insufficient_privilege;end if;
 end if;
 if action='toggle' then
  update apoiarcred_private.webhooks set active=(input->>'active')::boolean,updated_at=clock_timestamp() where id=hid;return '{"ok":true}';
 elsif action='rotate' then
  secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');perform vault.update_secret(w.secret_id,secret);return jsonb_build_object('secret',secret);
 elsif action in ('test','retry') then
  if action='retry' then
   select d.* into delivery from apoiarcred_private.webhook_deliveries d join apoiarcred_private.webhooks h on h.id=d.hook_id where d.id=(input->>'delivery_id')::uuid and h.user_id=uid for update of d;
   if not found then raise insufficient_privilege;end if;
   if delivery.state not in ('delivered','failed') then raise exception 'A entrega já está na fila ou em andamento.';end if;
   select * into w from apoiarcred_private.webhooks where id=delivery.hook_id for update;hid=w.id;
  end if;
  if not w.active then raise exception 'Ative o webhook para testar ou reenviar.';end if;
  if w.manual_window is null or w.manual_window<now()-interval '1 hour' then w.manual_count=0;w.manual_window=now();end if;
  if w.manual_count>=10 then raise exception 'Limite de 10 testes/reenvios manuais por hora neste webhook.';end if;
  update apoiarcred_private.webhooks set manual_window=w.manual_window,manual_count=w.manual_count+1 where id=hid;
  if action='retry' then
   update apoiarcred_private.webhook_deliveries set state='pending',attempts=0,next_at=clock_timestamp(),claim_token=null,locked_until=null,last_error=null where id=delivery.id;
   return jsonb_build_object('delivery_id',delivery.id);
  end if;
  eid=gen_random_uuid();insert into apoiarcred_private.webhook_events(id,event_key,user_id,event,payload) values(eid,'test:'||eid,uid,'webhook.teste',
   jsonb_build_object('event_id',eid,'event','webhook.teste','occurred_at',clock_timestamp(),'test',true,'campanha',null,'consulta',jsonb_build_object('id',gen_random_uuid(),'servico',coalesce(w.service,'digimais_saldo_parcela'),'cpf','00000000000','nome','Cliente fictício de teste','telefone','00000000000','status','concluida','cliente_identificado',true,'resultado_parcial',false,'resultado',case when w.service='tjba_margem' then jsonb_build_object('emprestimo_disponivel',100,'cartao_disponivel',50,'matricula','TESTE-FICTICIO','tipo_servidor',null,'situacao_atual',null) else jsonb_build_object('saldo_liquidacao',1000,'valor_parcela',100,'total_parcelas',96) end)));
  insert into apoiarcred_private.webhook_deliveries(hook_id,event_id) values(hid,eid) returning id into hid;return jsonb_build_object('delivery_id',hid);
 elsif action not in ('create','update') then raise exception 'Ação inválida.';end if;
 if coalesce(length(btrim(input->>'name')),0) not between 1 and 100 or coalesce(length(input->>'url'),0) not between 9 and 2048 or input->>'url'!~'^https://[^/@#[:space:]]+(/[^#[:space:]]*)?$' then raise exception 'Informe nome e URL HTTPS pública válida, sem usuário, senha ou fragmento.';end if;
 scope=input->>'scope';service_id=nullif(input->>'service','');campaign_id=nullif(input->>'campaign_id','')::uuid;
 if scope is null or scope not in ('all','individual','campaign') or (service_id is not null and service_id not in ('digimais_saldo_parcela','tjba_margem')) then raise exception 'Origem ou serviço inválido.';end if;
 if scope='campaign' then
  select * into lot from apoiarcred_private.api_campaign_rows c where c.id=vars.campaign_id and c.user_id=uid and c.tipo='campanha';
  if not found then raise insufficient_privilege;end if;service_id=lot.servico;
 else campaign_id=null;end if;
 select array_agg(distinct x) into ev from jsonb_array_elements_text(input->'events') x;
 select array_agg(distinct x) into st from jsonb_array_elements_text(input->'statuses') x;
 if coalesce(cardinality(ev),0)=0 or not ev<@array['consulta.finalizada','campanha.finalizada'] or (scope='individual' and 'campanha.finalizada'=any(ev)) then raise exception 'Escolha eventos válidos.';end if;
 if coalesce(cardinality(st),0)=0 or not st<@array['concluida','erro','revisao','nao_cliente','nao_localizado','nao_encontrado','interrompida'] or coalesce(input->>'client_filter','') not in ('all','client','nonclient','unknown') then raise exception 'Filtros de resultado inválidos.';end if;
 if action='create' then
  perform pg_advisory_xact_lock(hashtextextended(uid::text,11));
  if (select count(*) from apoiarcred_private.webhooks where user_id=uid)>=20 then raise exception 'Limite de 20 webhooks por conta.';end if;
  hid=gen_random_uuid();secret='whsec_'||encode(extensions.gen_random_bytes(32),'hex');sid=vault.create_secret(secret,'apoiarcred-webhook-'||hid);
  insert into apoiarcred_private.webhooks(id,user_id,name,url,active,scope,service,campaign_id,events,statuses,client_filter,include_partial,secret_id)
  values(hid,uid,btrim(input->>'name'),input->>'url',coalesce((input->>'active')::boolean,true),scope,service_id,campaign_id,ev,st,input->>'client_filter',coalesce((input->>'include_partial')::boolean,true),sid);
 else
  update apoiarcred_private.webhooks set name=btrim(input->>'name'),url=input->>'url',active=coalesce((input->>'active')::boolean,true),scope=vars.scope,service=service_id,campaign_id=vars.campaign_id,events=ev,statuses=st,client_filter=input->>'client_filter',include_partial=coalesce((input->>'include_partial')::boolean,true),updated_at=clock_timestamp() where id=hid;
 end if;
 return jsonb_build_object('id',hid,'secret',secret);
end $$;
notify pgrst,'reload schema';

-- Accept a fourth robot while preserving existing reservations and credentials.
alter table apoiarcred_private.tjba_robot_credentials
 drop constraint tjba_robot_credentials_slot_check,
 add constraint tjba_robot_credentials_slot_check check(slot between 1 and 4);
alter table public.tjba_jobs
 drop constraint tjba_jobs_robot_slot_check,
 add constraint tjba_jobs_robot_slot_check check(robot_slot between 1 and 4);
alter table public.consulta_jobs
 drop constraint consulta_jobs_robot_slot_check,
 add constraint consulta_jobs_robot_slot_check check(robot_slot between 1 and 4);

create or replace function apoiarcred_private.manage_tjba_robot_credentials(
 p_slot integer default null,p_username text default null,p_password text default null,p_enabled boolean default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); previous apoiarcred_private.tjba_robot_credentials;
begin
 if not apoiarcred_private.is_admin(uid) then raise insufficient_privilege;end if;
 if p_slot is not null then
  if p_slot not between 1 and 4 or p_enabled is null or coalesce(length(btrim(p_username)),0) not between 1 and 160 or length(coalesce(p_password,''))>512 then
   raise exception 'Informe um robô, usuário e senha válidos.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text||':tjba-robot:'||p_slot,0));
  select * into previous from apoiarcred_private.tjba_robot_credentials where user_id=uid and slot=p_slot;
  if coalesce(p_password,'')='' and (previous.secret_id is null or previous.username<>btrim(p_username)) then
   raise exception 'Informe a senha para esse usuário.';
  end if;
  if previous.secret_id is null then
   previous.secret_id=vault.create_secret(p_password,'apoiarcred-tjba-robot-'||uid||'-'||p_slot);
  elsif coalesce(p_password,'')<>'' then
   perform vault.update_secret(previous.secret_id,p_password);
  end if;
  insert into apoiarcred_private.tjba_robot_credentials(user_id,slot,username,secret_id,enabled,updated_at)
  values(uid,p_slot,btrim(p_username),previous.secret_id,p_enabled,clock_timestamp())
  on conflict(user_id,slot) do update set username=excluded.username,enabled=excluded.enabled,updated_at=excluded.updated_at;
 end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('slot',r.slot,'username',r.username,'enabled',r.enabled) order by r.slot),'[]')
         from apoiarcred_private.tjba_robot_credentials r where r.user_id=uid);
end $$;

create or replace function public.manage_consigx_access(
 p_slot integer default null,
 p_username text default null,
 p_password text default null,
 p_enabled boolean default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 admin boolean;
 robot_access jsonb := '[]'::jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 admin := public.am_i_admin();
 if p_slot is not null then
  if p_slot not between 0 and 4 or p_enabled is null then
   raise exception 'Selecione um acesso válido.';
  end if;
  if p_slot=0 then
   perform public.save_tjba_credentials(p_username,p_password,p_enabled);
  else
   if not admin then raise insufficient_privilege;end if;
   robot_access := public.manage_tjba_robot_credentials(p_slot,p_username,p_password,p_enabled);
  end if;
 end if;
 if admin and (p_slot is null or p_slot=0) then
  robot_access := public.manage_tjba_robot_credentials();
 end if;
 return jsonb_build_object('shared',public.tjba_credentials_status(),'robots',robot_access);
end $$;

create or replace function apoiarcred_private.claim_consigx_for_robot(p_slot integer)
returns setof public.tjba_jobs language plpgsql security definer set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is not null and p_slot not between 1 and 4 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 -- Serialize reservations, while actual portal work runs in parallel across logins.
 if not pg_try_advisory_xact_lock(763211,1) then return;end if;
 select l.id into selected_lot
 from public.tjba_lotes l
 join lateral apoiarcred_private.tjba_robot_login(l.user_id,p_slot) login on login.enabled
 where not l.paused
 and exists(select 1 from public.tjba_jobs j where j.lote_id=l.id and j.status='aguardando')
 and not exists(
  select 1 from public.tjba_jobs running
  left join lateral apoiarcred_private.tjba_robot_login(running.user_id,running.robot_slot) other on true
  where running.status='processando'
  and (lower(btrim(other.username))=lower(btrim(login.username))
       or (running.user_id=l.user_id and (login.username is null or other.username is null)))
 )
 order by l.created_at,l.id limit 1 for share of l;
 if selected_lot is null then return;end if;
 return query update public.tjba_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.tjba_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1)
 returning *;
end $$;

create or replace function public.claim_consulta_job_for_robot(p_slot integer) returns setof public.consulta_jobs language plpgsql security invoker set search_path='' as $$
declare selected_lot uuid;
begin
 if p_slot is null or p_slot not between 1 and 4 then raise exception 'Robô inválido.';end if;
 perform 1 from apoiarcred_private.queue_maintenance where id for share;
 if exists(select 1 from apoiarcred_private.queue_maintenance where id and paused_until>clock_timestamp()) then return;end if;
 select l.id into selected_lot from public.consulta_lotes l
 where not l.paused and exists(select 1 from public.consulta_jobs j where j.lote_id=l.id and j.status in ('aguardando','processando'))
 order by l.created_at,l.id for share of l limit 1;
 if selected_lot is null then return;end if;
 return query update public.consulta_jobs set status='processando',locked_at=now(),attempts=attempts+1,robot_slot=p_slot
 where id=(select j.id from public.consulta_jobs j where j.lote_id=selected_lot and j.status='aguardando' order by j.queue_order for update skip locked limit 1) returning *;
end $$;
notify pgrst,'reload schema';

-- An interrupted consultation breaks the streak of consecutive errors or reviews.
create or replace function apoiarcred_private.track_campaign_failures() returns trigger
language plpgsql security definer set search_path='' as $$
declare failed boolean := new.status in ('erro','revisao');
begin
 if old.status<>'processando' or new.status in ('processando','aguardando') then return new;end if;
 if tg_table_name='consulta_jobs' then
  update public.consulta_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 else
  update public.tjba_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 end if;
 return new;
end $$;

-- Shared daily quota for configured partners and trials ending in Brasília time.
alter table apoiarcred_private.user_profiles
 add column if not exists shared_quota boolean not null default false,
 add column if not exists shared_daily_limit integer check(shared_daily_limit between 1 and 100000),
 add column if not exists trial_until date;

create or replace function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'allow_integrations',coalesce(p.active and (p.role='admin' or p.allow_integrations),false),
 'trial_until',p.trial_until,
 'trial_expired',coalesce(p.trial_until<(now() at time zone 'America/Sao_Paulo')::date,false),
 'trial_days_left',case when p.trial_until is not null then greatest(0,p.trial_until-(now() at time zone 'America/Sao_Paulo')::date+1) end,
 'shared_quota',coalesce(p.shared_quota,false),'daily_limit',p.shared_daily_limit,
 'remaining',case when p.shared_daily_limit is not null then greatest(0,p.shared_daily_limit-coalesce(shared.used,0)) end,
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid
 left join apoiarcred_private.partner_daily_usage shared on shared.user_id=uid and shared.service='shared'
  and shared.day=(now() at time zone 'America/Sao_Paulo')::date;
$$;

create or replace function apoiarcred_private.check_partner_access(uid uuid,service_id text,mode text,consume boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare profile apoiarcred_private.user_profiles;rule apoiarcred_private.partner_permissions;today date=(now() at time zone 'America/Sao_Paulo')::date;n integer;
begin
 select * into profile from apoiarcred_private.user_profiles where user_id=uid for share;
 if not found or not profile.active then raise insufficient_privilege using message='Conta sem acesso ativo. Solicite liberação ao administrador.';end if;
 if profile.role='admin' then return;end if;
 if profile.trial_until<today then
  raise insufficient_privilege using message='Seu período de teste terminou. Solicite a renovação ao administrador.';
 end if;
 select * into rule from apoiarcred_private.partner_permissions where user_id=uid and service=service_id for share;
 if not found or not rule.enabled then raise insufficient_privilege using message='Tipo de higienização não autorizado para este parceiro.';end if;
 if mode='campanha' then
  if not rule.allow_campaign then raise insufficient_privilege using message='Campanhas não estão habilitadas para este tipo de higienização.';end if;
 elsif mode='individual' then
  if not rule.allow_individual or (not profile.shared_quota and rule.daily_limit=0) then raise insufficient_privilege using message='Consultas individuais não estão habilitadas para este tipo de higienização.';end if;
  if consume and not profile.shared_quota then
   insert into apoiarcred_private.partner_daily_usage(user_id,service,day,used) values(uid,service_id,today,0) on conflict do nothing;
   update apoiarcred_private.partner_daily_usage set used=used+1 where user_id=uid and service=service_id and day=today and used<rule.daily_limit;
   get diagnostics n=row_count;
   if n=0 then raise sqlstate 'PT429' using message='Limite diário de consultas individuais atingido para este tipo. Renova à meia-noite no horário de Brasília.';end if;
  end if;
 else raise insufficient_privilege;end if;
 if consume and profile.shared_quota then
  insert into apoiarcred_private.partner_daily_usage(user_id,service,day,used)
  values(uid,'shared',today,0) on conflict do nothing;
  update apoiarcred_private.partner_daily_usage set used=used+1
   where user_id=uid and service='shared' and day=today
     and (profile.shared_daily_limit is null or used<profile.shared_daily_limit);
  if not found then raise sqlstate 'PT429' using message='Limite diário compartilhado entre campanhas e consultas individuais atingido. Renova à meia-noite no horário de Brasília.';end if;
 end if;
end $$;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;quota integer;trial date;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg((to_jsonb(p)-'created_by')||jsonb_build_object('access',apoiarcred_private.access_for(p.user_id)) order by p.created_at desc),'[]') into result from apoiarcred_private.user_profiles p where role='partner';return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null then raise insufficient_privilege;end if;
 if p_action='create' and exists(select 1 from apoiarcred_private.user_profiles where user_id=uid) then raise exception 'Perfil já existe.';end if;
 if p_action='update' and not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='partner') then raise insufficient_privilege;end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' not in ('digimais_saldo_parcela','tjba_margem') or item->>'service' is null or (item->>'daily_limit')::int not between 0 and 100000 then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_input ? 'allow_integrations' and jsonb_typeof(p_input->'allow_integrations') is distinct from 'boolean' then raise exception 'Permissão de integrações inválida.';end if;
 if p_input ? 'shared_daily_limit' then
  if jsonb_typeof(p_input->'shared_daily_limit') not in ('number','null') then raise exception 'Cota diária inválida.';end if;
  quota=(p_input->>'shared_daily_limit')::integer;
  if quota not between 1 and 100000 then raise exception 'Cota diária inválida.';end if;
 end if;
 if p_input ? 'trial_until' then trial=(p_input->>'trial_until')::date;end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,allow_integrations,shared_quota,shared_daily_limit,trial_until,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),coalesce((p_input->>'allow_integrations')::boolean,false),p_input ? 'shared_daily_limit',quota,trial,p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),allow_integrations=coalesce((p_input->>'allow_integrations')::boolean,allow_integrations),shared_quota=shared_quota or p_input ? 'shared_daily_limit',
   shared_daily_limit=case when p_input ? 'shared_daily_limit' then quota else shared_daily_limit end,
   trial_until=case when p_input ? 'trial_until' then trial else trial_until end,
   updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;

create or replace function public.create_consulta_campaign(p_nome text,p_items jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare campaign_id uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe um nome de campanha com até 160 caracteres.'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.'; end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>10000 then raise exception 'Envie até 10.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados na campanha.'; end if;
 insert into public.consulta_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into campaign_id;
 insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone)
 select campaign_id,auth.uid(),x.item->>'nome',x.item->>'cpf',x.item->>'telefone' from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return campaign_id;
end $$;

create or replace function public.create_tjba_campaign(p_nome text,p_items jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>10000 then raise exception 'Envie até 10.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.nome),''),'CPF '||x.cpf),x.cpf,coalesce(x.telefone,'') from jsonb_to_recordset(p_items) x(nome text,cpf text,telefone text);
 return cid;
end $$;

create or replace function public.create_consigx_campaign(p_nome text,p_items jsonb,p_convenio text) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>10000 then raise exception 'Envie até 10.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo,convenio) values(btrim(p_nome),'campanha',p_convenio) returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.item->>'nome'),''),'CPF '||(x.item->>'cpf')),x.item->>'cpf',coalesce(x.item->>'telefone','') from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return cid;
end $$;

-- Individual Amigoz access is opt-in for each partner.
alter table apoiarcred_private.user_profiles add column if not exists allow_amigoz boolean not null default false;

create or replace function apoiarcred_private.access_for(uid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',uid,'role',coalesce(p.role,'partner'),'name',p.name,'active',coalesce(p.active,false),
 'allow_amigoz',coalesce(p.active and (p.role='admin' or p.allow_amigoz),false),
 'allow_integrations',coalesce(p.active and (p.role='admin' or p.allow_integrations),false),
 'trial_until',p.trial_until,
 'trial_expired',coalesce(p.trial_until<(now() at time zone 'America/Sao_Paulo')::date,false),
 'trial_days_left',case when p.trial_until is not null then greatest(0,p.trial_until-(now() at time zone 'America/Sao_Paulo')::date+1) end,
 'shared_quota',coalesce(p.shared_quota,false),'daily_limit',p.shared_daily_limit,
 'remaining',case when p.shared_daily_limit is not null then greatest(0,p.shared_daily_limit-coalesce(shared.used,0)) end,
 'day',(now() at time zone 'America/Sao_Paulo')::date,'timezone','America/Sao_Paulo',
 'services',(select jsonb_agg(jsonb_build_object('id',s,'enabled',case when p.role='admin' then p.active else coalesce(r.enabled,false) end,
 'allow_individual',case when p.role='admin' then true else coalesce(r.allow_individual,false) end,
 'allow_campaign',case when p.role='admin' then true else coalesce(r.allow_campaign,false) end,
 'daily_limit',case when p.role='admin' then null else coalesce(r.daily_limit,0) end,
 'used',coalesce(u.used,0),'remaining',case when p.role='admin' then null else greatest(0,coalesce(r.daily_limit,0)-coalesce(u.used,0)) end) order by s)
 from unnest(array['digimais_saldo_parcela','tjba_margem']) s
 left join apoiarcred_private.partner_permissions r on r.user_id=uid and r.service=s
 left join apoiarcred_private.partner_daily_usage u on u.user_id=uid and u.service=s and u.day=(now() at time zone 'America/Sao_Paulo')::date))
 from (select 1) seed left join apoiarcred_private.user_profiles p on p.user_id=uid
 left join apoiarcred_private.partner_daily_usage shared on shared.user_id=uid and shared.service='shared'
  and shared.day=(now() at time zone 'America/Sao_Paulo')::date;
$$;

create or replace function public.admin_partner_manage(p_actor uuid,p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare uid uuid;item jsonb;service_id text;rules jsonb;result jsonb;quota integer;trial date;
begin
 if not apoiarcred_private.is_admin(p_actor) then raise insufficient_privilege;end if;
 if p_action='check' then return '{"admin":true}';end if;
 if p_action='list' then
  select coalesce(jsonb_agg((to_jsonb(p)-'created_by')||jsonb_build_object('access',apoiarcred_private.access_for(p.user_id)) order by p.created_at desc),'[]') into result from apoiarcred_private.user_profiles p where role='partner';return result;
 end if;
 if p_action not in ('create','update') then raise exception 'Ação inválida.';end if;
 uid=(p_input->>'user_id')::uuid;rules=p_input->'permissions';
 if uid=p_actor or uid is null then raise insufficient_privilege;end if;
 if p_action='create' and exists(select 1 from apoiarcred_private.user_profiles where user_id=uid) then raise exception 'Perfil já existe.';end if;
 if p_action='update' and not exists(select 1 from apoiarcred_private.user_profiles where user_id=uid and role='partner') then raise insufficient_privilege;end if;
 if coalesce(length(btrim(p_input->>'name')),0) not between 1 and 160 or jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)<>2 then raise exception 'Nome ou permissões inválidos.';end if;
 if (select count(distinct value->>'service') from jsonb_array_elements(rules))<>2 then raise exception 'Serviços duplicados.';end if;
 for item in select value from jsonb_array_elements(rules) loop
  if item->>'service' not in ('digimais_saldo_parcela','tjba_margem') or item->>'service' is null or (item->>'daily_limit')::int not between 0 and 100000 then raise exception 'Permissões inválidas.';end if;
 end loop;
 if p_input ? 'allow_integrations' and jsonb_typeof(p_input->'allow_integrations') is distinct from 'boolean' then raise exception 'Permissão de integrações inválida.';end if;
 if p_input ? 'allow_amigoz' and jsonb_typeof(p_input->'allow_amigoz') is distinct from 'boolean' then raise exception 'Permissão Amigoz inválida.';end if;
 if (p_input->>'allow_amigoz')::boolean and not (p_input ? 'shared_daily_limit' or exists(
  select 1 from apoiarcred_private.user_profiles where user_id=uid and shared_quota
 )) then raise exception 'Configure a cota compartilhada para liberar Amigoz.';end if;
 if p_input ? 'shared_daily_limit' then
  if jsonb_typeof(p_input->'shared_daily_limit') not in ('number','null') then raise exception 'Cota diária inválida.';end if;
  quota=(p_input->>'shared_daily_limit')::integer;
  if quota not between 1 and 100000 then raise exception 'Cota diária inválida.';end if;
 end if;
 if p_input ? 'trial_until' then trial=(p_input->>'trial_until')::date;end if;
 if p_action='create' then
  insert into apoiarcred_private.user_profiles(user_id,role,name,email,active,allow_integrations,allow_amigoz,shared_quota,shared_daily_limit,trial_until,created_by) values(uid,'partner',btrim(p_input->>'name'),p_input->>'email',coalesce((p_input->>'active')::boolean,true),coalesce((p_input->>'allow_integrations')::boolean,false),coalesce((p_input->>'allow_amigoz')::boolean,false),p_input ? 'shared_daily_limit',quota,trial,p_actor);
 else
  update apoiarcred_private.user_profiles set name=btrim(p_input->>'name'),active=coalesce((p_input->>'active')::boolean,true),allow_integrations=coalesce((p_input->>'allow_integrations')::boolean,allow_integrations),shared_quota=shared_quota or p_input ? 'shared_daily_limit',
   allow_amigoz=coalesce((p_input->>'allow_amigoz')::boolean,allow_amigoz),
   shared_daily_limit=case when p_input ? 'shared_daily_limit' then quota else shared_daily_limit end,
   trial_until=case when p_input ? 'trial_until' then trial else trial_until end,
   updated_at=now() where user_id=uid;
 end if;
 -- Profile lock is held through permission changes and serializes with quota acceptance.
 for item in select value from jsonb_array_elements(rules) loop
  insert into apoiarcred_private.partner_permissions(user_id,service,enabled,allow_individual,daily_limit,allow_campaign)
  values(uid,item->>'service',coalesce((item->>'enabled')::boolean,false),coalesce((item->>'allow_individual')::boolean,false),coalesce((item->>'daily_limit')::integer,0),coalesce((item->>'allow_campaign')::boolean,false))
  on conflict(user_id,service) do update set enabled=excluded.enabled,allow_individual=excluded.allow_individual,daily_limit=excluded.daily_limit,allow_campaign=excluded.allow_campaign;
 end loop;
 return apoiarcred_private.access_for(uid);
end $$;

create or replace function public.authorize_amigoz(p_actor uuid,p_consume boolean)
returns boolean language plpgsql security invoker set search_path='' as $$
declare profile apoiarcred_private.user_profiles; today date=(now() at time zone 'America/Sao_Paulo')::date;
begin
 select * into profile from apoiarcred_private.user_profiles where user_id=p_actor for share;
 if not found or not profile.active then
  raise insufficient_privilege using message='Conta sem acesso ativo.';
 end if;
 if profile.role='admin' then return true;end if;
 if not profile.allow_amigoz or not profile.shared_quota then
  raise insufficient_privilege using message='Acesso Amigoz não liberado.';
 end if;
 if profile.trial_until<today then
  raise insufficient_privilege using message='Seu período de teste terminou.';
 end if;
 if p_consume then
  insert into apoiarcred_private.partner_daily_usage as quota(user_id,service,day,used)
   values(p_actor,'shared',today,1)
   on conflict(user_id,service,day) do update set used=quota.used+1
   where profile.shared_daily_limit is null or quota.used<profile.shared_daily_limit;
  if not found then raise sqlstate 'PT429' using message='Limite diário de consultas atingido.';end if;
 end if;
 return true;
end $$;
revoke all on function public.authorize_amigoz(uuid,boolean) from public,anon,authenticated;
grant execute on function public.authorize_amigoz(uuid,boolean) to service_role;
begin;

-- Caller privileges and the original row policies protect both sources.
create or replace view public.crm_consultas with (security_invoker=true) as
select id, user_id, cpf, nome, telefone, servico, null::text as convenio,
       status, created_at, consultado_em, null::text as matricula,
       null::text as situacao_atual, null::numeric as emprestimo_disponivel,
       null::numeric as cartao_disponivel, saldo_liquidacao, valor_parcela
from public.consulta_jobs
union all
select id, user_id, cpf, nome, telefone, servico, convenio,
       status, created_at, consultado_em, matricula, situacao_atual,
       emprestimo_disponivel, cartao_disponivel, null::numeric, null::numeric
from public.tjba_jobs;

create or replace view public.crm_clientes with (security_invoker=true) as
select user_id, cpf,
       (array_agg(nome order by created_at desc, id desc)
          filter (where nome <> 'CPF ' || cpf and nome <> 'Cliente TJBA'
                  and btrim(nome) <> ''))[1] as nome,
       (array_agg(telefone order by created_at desc, id desc)
          filter (where btrim(telefone) <> ''))[1] as telefone,
       max(coalesce(consultado_em, created_at)) as ultima_atividade
from public.crm_consultas
group by user_id, cpf;

revoke all on public.crm_consultas, public.crm_clientes from public, anon, authenticated;
grant select on public.crm_consultas, public.crm_clientes to authenticated;
create index if not exists consulta_jobs_crm_cpf on public.consulta_jobs(user_id, cpf);
create index if not exists tjba_jobs_crm_cpf on public.tjba_jobs(user_id, cpf);

commit;
begin;

create table if not exists public.crm_cadastros (
  user_id uuid not null references auth.users(id) on delete cascade,
  cpf text not null check (cpf ~ '^[0-9]{11}$'),
  nome text,
  nome_atualizado_em timestamptz,
  telefone text,
  telefone_atualizado_em timestamptz,
  ultima_atividade timestamptz not null,
  primary key (user_id, cpf)
);

create table if not exists public.crm_vinculos (
  user_id uuid not null,
  cpf text not null,
  uf text not null,
  convenio text not null,
  matricula text not null check (btrim(matricula) <> ''),
  situacao_atual text,
  fonte text not null,
  confirmado_em timestamptz not null,
  primary key (user_id, cpf, uf, convenio, matricula),
  foreign key (user_id, cpf) references public.crm_cadastros(user_id, cpf) on delete cascade
);

alter table public.crm_cadastros enable row level security;
alter table public.crm_vinculos enable row level security;
revoke all on public.crm_cadastros, public.crm_vinculos from public, anon, authenticated;
grant select on public.crm_cadastros, public.crm_vinculos to authenticated;
drop policy if exists crm_cadastro_leitura on public.crm_cadastros;
create policy crm_cadastro_leitura on public.crm_cadastros for select
  to authenticated using (user_id = (select auth.uid()));
drop policy if exists crm_vinculo_leitura on public.crm_vinculos;
create policy crm_vinculo_leitura on public.crm_vinculos for select
  to authenticated using (user_id = (select auth.uid()));

insert into public.crm_cadastros(user_id, cpf, nome, nome_atualizado_em, telefone,
                                 telefone_atualizado_em, ultima_atividade)
select user_id, cpf,
       (array_agg(nome order by created_at desc,id desc)
          filter (where nome <> 'CPF ' || cpf and nome <> 'Cliente TJBA' and btrim(nome) <> ''))[1],
       max(created_at) filter (where nome <> 'CPF ' || cpf and nome <> 'Cliente TJBA' and btrim(nome) <> ''),
       (array_agg(telefone order by created_at desc,id desc) filter (where btrim(telefone) <> ''))[1],
       max(created_at) filter (where btrim(telefone) <> ''),
       max(coalesce(consultado_em,created_at))
from public.crm_consultas
group by user_id, cpf
on conflict (user_id, cpf) do nothing;

insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,situacao_atual,fonte,confirmado_em)
select distinct on (user_id,cpf,convenio,btrim(matricula))
       user_id,cpf,'BA',convenio,btrim(matricula),nullif(btrim(situacao_atual),''),'consigx',
       coalesce(consultado_em,created_at)
from public.tjba_jobs
where status='concluida' and btrim(matricula) <> ''
order by user_id,cpf,convenio,btrim(matricula),coalesce(consultado_em,created_at) desc,id desc
on conflict (user_id,cpf,uf,convenio,matricula) do nothing;

-- The trigger uses only the owner and fields of an existing, authorized job.
create or replace function apoiarcred_private.crm_sync_job()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  nome_real text := nullif(btrim(new.nome),'');
  telefone_real text := nullif(btrim(new.telefone),'');
  atividade timestamptz := coalesce(new.consultado_em,new.created_at);
begin
  if nome_real in ('CPF ' || new.cpf, 'Cliente TJBA') then nome_real := null; end if;

  insert into public.crm_cadastros as atual
    (user_id,cpf,nome,nome_atualizado_em,telefone,telefone_atualizado_em,ultima_atividade)
  values (new.user_id,new.cpf,nome_real,case when nome_real is not null then new.created_at end,
          telefone_real,case when telefone_real is not null then new.created_at end,atividade)
  on conflict (user_id,cpf) do update set
    nome = case when excluded.nome_atualizado_em >= coalesce(atual.nome_atualizado_em,'-infinity')
                then excluded.nome else atual.nome end,
    nome_atualizado_em = greatest(atual.nome_atualizado_em,excluded.nome_atualizado_em),
    telefone = case when excluded.telefone_atualizado_em >= coalesce(atual.telefone_atualizado_em,'-infinity')
                    then excluded.telefone else atual.telefone end,
    telefone_atualizado_em = greatest(atual.telefone_atualizado_em,excluded.telefone_atualizado_em),
    ultima_atividade = greatest(atual.ultima_atividade,excluded.ultima_atividade);

  if tg_table_name = 'tjba_jobs' then
    if new.status = 'concluida' and btrim(new.matricula) <> '' then
      insert into public.crm_vinculos as atual
        (user_id,cpf,uf,convenio,matricula,situacao_atual,fonte,confirmado_em)
      values (new.user_id,new.cpf,'BA',new.convenio,btrim(new.matricula),
              nullif(btrim(new.situacao_atual),''),'consigx',atividade)
      on conflict (user_id,cpf,uf,convenio,matricula) do update set
        situacao_atual = coalesce(excluded.situacao_atual,atual.situacao_atual),
        confirmado_em = excluded.confirmado_em
      where excluded.confirmado_em >= atual.confirmado_em;
    end if;
  end if;
  return new;
end $$;
revoke all on function apoiarcred_private.crm_sync_job() from public, anon, authenticated;

drop trigger if exists crm_sync_consulta on public.consulta_jobs;
create trigger crm_sync_consulta after insert or update of nome,telefone,consultado_em
on public.consulta_jobs for each row execute function apoiarcred_private.crm_sync_job();
drop trigger if exists crm_sync_tjba on public.tjba_jobs;
create trigger crm_sync_tjba after insert or update of nome,telefone,consultado_em,matricula,situacao_atual,status
on public.tjba_jobs for each row execute function apoiarcred_private.crm_sync_job();

create or replace view public.crm_clientes with (security_invoker=true) as
select user_id,cpf,nome,telefone,ultima_atividade from public.crm_cadastros;

commit;
begin;

create table if not exists public.crm_oportunidades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cpf text not null check (cpf ~ '^[0-9]{11}$'),
  nome text check (length(nome) <= 160),
  produto text not null check (produto in ('margem','saque','recompra')),
  convenio text not null default '',
  etapa text not null default 'novo'
    check (etapa in ('novo','contato','simulacao','negociacao','ganho','perdido')),
  proxima_acao text check (length(proxima_acao) <= 500),
  created_at timestamptz not null default now()
);
alter table public.crm_oportunidades enable row level security;
revoke all on public.crm_oportunidades from public, anon, authenticated;
grant select, insert (cpf,nome,produto,convenio), update (etapa,proxima_acao)
  on public.crm_oportunidades to authenticated;
drop policy if exists crm_oportunidades_owner on public.crm_oportunidades;
create policy crm_oportunidades_owner on public.crm_oportunidades
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists crm_oportunidades_update on public.crm_oportunidades;
create policy crm_oportunidades_update on public.crm_oportunidades
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists crm_oportunidades_insert on public.crm_oportunidades;
create policy crm_oportunidades_insert on public.crm_oportunidades
  for insert to authenticated with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.crm_clientes c
      where c.user_id = crm_oportunidades.user_id
        and c.cpf = crm_oportunidades.cpf
    ) and (crm_oportunidades.convenio = '' or exists (
      select 1 from public.crm_vinculos c
      where c.user_id = crm_oportunidades.user_id
        and c.cpf = crm_oportunidades.cpf
        and c.convenio = crm_oportunidades.convenio
    ))
  );
create unique index if not exists crm_oportunidade_aberta
  on public.crm_oportunidades(user_id,cpf,produto,convenio)
  where etapa not in ('ganho','perdido');
create index if not exists crm_oportunidades_lista
  on public.crm_oportunidades(user_id,created_at desc,id desc);

commit;

-- CRM Kanban e filtros
begin;
create table if not exists public.crm_card_settings (
 user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
 visible text[] not null default array['cpf','produto','convenio','proxima_acao'],
 fields jsonb not null default '[]'::jsonb,
 updated_at timestamptz not null default now()
);
alter table public.crm_card_settings enable row level security;
revoke all on public.crm_card_settings from public,anon,authenticated;
grant select,insert(visible,fields),update(visible,fields) on public.crm_card_settings to authenticated;
drop policy if exists crm_card_settings_owner on public.crm_card_settings;
create policy crm_card_settings_owner on public.crm_card_settings for all to authenticated
 using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
alter table public.crm_oportunidades add column if not exists campos jsonb not null default '{}'::jsonb;
grant update(campos) on public.crm_oportunidades to authenticated;
create or replace function apoiarcred_private.crm_validate_customization() returns trigger
language plpgsql set search_path='' as $$
declare f jsonb; k text; v jsonb; definitions jsonb; seen text[] := '{}';
begin
 if TG_TABLE_NAME='crm_card_settings' then
  if not (new.visible <@ array['cpf','produto','convenio','proxima_acao']) or jsonb_typeof(new.fields)<>'array' or jsonb_array_length(new.fields)>30 then raise exception 'Configuração inválida'; end if;
  for f in select value from jsonb_array_elements(new.fields) loop
   if coalesce(f->>'id','') !~ '^cf_[a-f0-9]{16}$' or f->>'id'=any(seen)
    or coalesce(f->>'label','') !~ '\S' or length(f->>'label')>60
    or lower(f->>'label') ~ '(saldo|margem|margens)'
    or coalesce(f->>'type','') not in ('text','number','date','boolean')
    or jsonb_typeof(f->'visible') is distinct from 'boolean' then raise exception 'Campo personalizado inválido; saldo e margem são protegidos'; end if;
   if TG_OP='UPDATE' and exists(select 1 from jsonb_array_elements(old.fields) x where x->>'id'=f->>'id' and x->>'type'<>f->>'type') then raise exception 'O tipo de um campo existente não pode mudar'; end if;
   seen:=array_append(seen,f->>'id');
  end loop;
  if TG_OP='UPDATE' and exists(select 1 from jsonb_array_elements(old.fields) x where not (x->>'id'=any(seen))) then raise exception 'Oculte campos existentes para preservar os dados'; end if;
  new.updated_at:=now();
 else
  if jsonb_typeof(new.campos)<>'object' or octet_length(new.campos::text)>64000 then raise exception 'Valores inválidos'; end if;
  select fields into definitions from public.crm_card_settings where user_id=new.user_id;
  for k,v in select * from jsonb_each(new.campos) loop
   select value into f from jsonb_array_elements(coalesce(definitions,'[]')) where value->>'id'=k;
   if f is null then raise exception 'Campo desconhecido'; end if;
   if v<>'null'::jsonb and (case f->>'type' when 'number' then jsonb_typeof(v)<>'number' when 'boolean' then jsonb_typeof(v)<>'boolean' else jsonb_typeof(v)<>'string' or length(v#>>'{}')>2000 end) then raise exception 'Tipo de valor inválido'; end if;
   if f->>'type'='date' and v<>'null'::jsonb then perform (v#>>'{}')::date; end if;
  end loop;
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.crm_validate_customization() from public,anon,authenticated;
drop trigger if exists crm_card_settings_validate on public.crm_card_settings;
create trigger crm_card_settings_validate before insert or update on public.crm_card_settings for each row execute function apoiarcred_private.crm_validate_customization();
drop trigger if exists crm_campos_validate on public.crm_oportunidades;
create trigger crm_campos_validate before insert or update of campos on public.crm_oportunidades for each row execute function apoiarcred_private.crm_validate_customization();

-- Filters evaluate UF and agreement on the same confirmed vínculo. No inferred classification.
create or replace function public.crm_filter_clients(p_query text default '',p_uf text default '',p_convenio text default '',p_servico text default '',p_after text default '',p_limit integer default 26)
returns setof public.crm_cadastros language sql stable security invoker set search_path='' as $$
 select c.* from public.crm_cadastros c
 where c.cpf>p_after
 and (p_query='' or position(lower(p_query) in lower(coalesce(c.nome,'')))>0 or
  (regexp_replace(p_query,'[^0-9]','','g')<>'' and position(regexp_replace(p_query,'[^0-9]','','g') in c.cpf)>0))
 and ((p_uf='' and p_convenio='') or exists(select 1 from public.crm_vinculos v where v.user_id=c.user_id and v.cpf=c.cpf and (p_uf='' or v.uf=p_uf) and (p_convenio='' or v.convenio=p_convenio)))
 and (p_servico='' or exists(select 1 from public.crm_consultas q where q.user_id=c.user_id and q.cpf=c.cpf and q.servico=p_servico and (p_convenio='' or q.convenio=p_convenio or (q.convenio is null and q.servico='digimais_saldo_parcela'))))
 order by c.cpf limit greatest(1,least(coalesce(p_limit,26),500));
$$;
create or replace function public.crm_filter_options() returns table(uf text,convenio text)
language sql stable security invoker set search_path='' as $$ select distinct v.uf,v.convenio from public.crm_vinculos v order by v.uf,v.convenio $$;
revoke all on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() from public,anon;
grant execute on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() to authenticated;
create or replace view public.crm_opportunity_cards with(security_invoker=true) as
 select o.*,q.saldo_liquidacao,q.emprestimo_disponivel,q.consultado_em as resultado_em,q.created_at as resultado_criado_em,q.servico as resultado_fonte
 from public.crm_oportunidades o left join lateral (
 select c.saldo_liquidacao,c.emprestimo_disponivel,c.consultado_em,c.created_at,c.servico
 from public.crm_consultas c where c.user_id=o.user_id and c.cpf=o.cpf and
 ((o.produto='recompra' and c.servico='digimais_saldo_parcela' and c.saldo_liquidacao is not null)
 or (o.produto='margem' and o.convenio<>'' and c.convenio=o.convenio and c.servico='tjba_margem' and c.emprestimo_disponivel is not null))
 order by c.consultado_em desc nulls last,c.created_at desc,c.id desc limit 1
 ) q on true;
revoke all on public.crm_opportunity_cards from public,anon,authenticated;
grant select on public.crm_opportunity_cards to authenticated;
notify pgrst,'reload schema';
commit;

begin;
alter table public.crm_card_settings add column if not exists density text not null default 'comfortable' check(density in ('compact','comfortable'));
grant insert(density),update(density) on public.crm_card_settings to authenticated;
grant update(nome) on public.crm_oportunidades to authenticated;
notify pgrst,'reload schema';
commit;
begin;

create table if not exists public.crm_classificacoes (
  user_id uuid not null,
  cpf text not null,
  uf text not null,
  convenio text not null,
  usar_digimais boolean not null,
  importado_em timestamptz not null default now(),
  primary key (user_id, cpf, uf, convenio),
  foreign key (user_id, cpf) references public.crm_cadastros(user_id, cpf) on delete cascade
);

alter table public.crm_classificacoes enable row level security;
revoke all on public.crm_classificacoes from public, anon, authenticated;
grant select on public.crm_classificacoes to authenticated;
drop policy if exists crm_classificacao_leitura on public.crm_classificacoes;
create policy crm_classificacao_leitura on public.crm_classificacoes
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function apoiarcred_private.crm_import_clients(
  p_uf text, p_convenio text, p_usar_digimais boolean, p_rows jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
  owner_id uuid := auth.uid();
  account_access jsonb;
  state_code text := upper(btrim(p_uf));
  agreement text := lower(regexp_replace(btrim(p_convenio), '[[:space:]]+', ' ', 'g'));
begin
  account_access := apoiarcred_private.access_for(owner_id);
  if owner_id is null or not coalesce((account_access->>'active')::boolean, false)
      or coalesce((account_access->>'trial_expired')::boolean, false) then
    raise exception 'Importação indisponível para esta conta.' using errcode='42501';
  end if;
  if state_code is null or state_code not in
      ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')
      or agreement is null or length(agreement) not between 1 and 120 or p_usar_digimais is null then
    raise exception 'Informe estado, convênio e a preferência de uso do Digi+.';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Envie uma lista de clientes.';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 10000 then
    raise exception 'Envie entre 1 e 10.000 clientes por arquivo.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_rows) as r(cpf text, nome text, telefone text)
    where cpf is null or cpf !~ '^[0-9]{11}$' or cpf='00000000000'
       or length(btrim(nome)) > 160 or coalesce(telefone,'') !~ '^([0-9]{10,13})?$'
  ) then raise exception 'A lista contém CPF, nome ou telefone inválido.'; end if;
  if exists (select 1 from jsonb_to_recordset(p_rows) as r(cpf text) group by cpf having count(*)>1) then
    raise exception 'A lista contém CPFs repetidos.';
  end if;

  insert into public.crm_cadastros as c
    (user_id, cpf, nome, telefone, nome_atualizado_em, telefone_atualizado_em, ultima_atividade)
  select owner_id, r.cpf, nullif(btrim(r.nome),''), nullif(r.telefone,''),
         case when nullif(btrim(r.nome),'') is not null then now() end,
         case when nullif(r.telefone,'') is not null then now() end, now()
  from jsonb_to_recordset(p_rows) as r(cpf text, nome text, telefone text)
  order by r.cpf
  on conflict (user_id, cpf) do update set
    nome=coalesce(excluded.nome,c.nome),
    telefone=coalesce(excluded.telefone,c.telefone),
    nome_atualizado_em=coalesce(excluded.nome_atualizado_em,c.nome_atualizado_em),
    telefone_atualizado_em=coalesce(excluded.telefone_atualizado_em,c.telefone_atualizado_em),
    ultima_atividade=greatest(c.ultima_atividade,excluded.ultima_atividade);

  insert into public.crm_classificacoes (user_id, cpf, uf, convenio, usar_digimais)
  select owner_id, r.cpf, state_code, agreement, p_usar_digimais
  from jsonb_to_recordset(p_rows) as r(cpf text)
  order by r.cpf
  on conflict (user_id, cpf, uf, convenio) do update set
    usar_digimais=excluded.usar_digimais, importado_em=excluded.importado_em;
  return jsonb_array_length(p_rows);
end $$;
revoke all on function apoiarcred_private.crm_import_clients(text,text,boolean,jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_import_clients(text,text,boolean,jsonb) to authenticated;

create or replace function public.crm_import_clients(
  p_uf text, p_convenio text, p_usar_digimais boolean, p_rows jsonb
) returns integer language sql security invoker set search_path='' as $$
  select apoiarcred_private.crm_import_clients(p_uf,p_convenio,p_usar_digimais,p_rows);
$$;
revoke all on function public.crm_import_clients(text,text,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.crm_import_clients(text,text,boolean,jsonb) to authenticated;

create or replace view public.crm_classificacao_filtros with (security_invoker=true) as
select user_id,cpf,uf,convenio from public.crm_vinculos
union all
select user_id,cpf,uf,convenio from public.crm_classificacoes;
revoke all on public.crm_classificacao_filtros from public,anon,authenticated;
grant select on public.crm_classificacao_filtros to authenticated;

create or replace function public.crm_filter_clients(p_query text default '',p_uf text default '',p_convenio text default '',p_servico text default '',p_after text default '',p_limit integer default 26)
returns setof public.crm_cadastros language sql stable security invoker set search_path='' as $$
 select c.* from public.crm_cadastros c
 where c.cpf>p_after
 and (p_query='' or position(lower(p_query) in lower(coalesce(c.nome,'')))>0 or
  (regexp_replace(p_query,'[^0-9]','','g')<>'' and position(regexp_replace(p_query,'[^0-9]','','g') in c.cpf)>0))
 and ((p_uf='' and p_convenio='') or exists(select 1 from public.crm_classificacao_filtros v where v.user_id=c.user_id and v.cpf=c.cpf and (p_uf='' or v.uf=p_uf) and (p_convenio='' or v.convenio=p_convenio)))
 and (p_servico='' or exists(select 1 from public.crm_consultas q where q.user_id=c.user_id and q.cpf=c.cpf and q.servico=p_servico and (p_convenio='' or q.convenio=p_convenio or (q.convenio is null and q.servico='digimais_saldo_parcela'))))
 order by c.cpf limit greatest(1,least(coalesce(p_limit,26),500));
$$;
create or replace function public.crm_filter_options() returns table(uf text,convenio text)
language sql stable security invoker set search_path='' as $$ select distinct v.uf,v.convenio from public.crm_classificacao_filtros v order by v.uf,v.convenio $$;
revoke all on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() from public,anon;
grant execute on function public.crm_filter_clients(text,text,text,text,text,integer),public.crm_filter_options() to authenticated;
notify pgrst,'reload schema';
commit;
begin;

create or replace function apoiarcred_private.crm_reset_account(p_confirmation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  owner_id uuid := auth.uid();
  client_count integer;
  opportunity_count integer;
  job_count integer;
  count_tjba integer;
  lot_count integer;
  count_tjba_lots integer;
begin
  if owner_id is null or not exists (
    select 1 from apoiarcred_private.user_profiles
    where user_id=owner_id and role='admin' and active
    for share
  ) then raise exception 'Apenas administradores ativos podem zerar a própria conta.' using errcode='42501'; end if;
  if p_confirmation is distinct from 'ZERAR MINHA CONTA' then
    raise exception 'Digite ZERAR MINHA CONTA para confirmar.';
  end if;

  -- Avoid a race with queue claims, new jobs and webhook deliveries.
  begin
    lock table public.consulta_lotes, public.tjba_lotes, public.consulta_jobs, public.tjba_jobs,
      public.crm_cadastros, public.crm_oportunidades, public.crm_classificacoes,
      apoiarcred_private.webhook_deliveries, apoiarcred_private.api_idempotency
    in share row exclusive mode nowait;
  exception when lock_not_available then
    raise exception 'Há gravações em andamento. Aguarde alguns instantes e tente novamente.';
  end;
  if exists (select 1 from public.consulta_jobs where user_id=owner_id and status='processando')
    or exists (select 1 from public.tjba_jobs where user_id=owner_id and status='processando')
    or exists (
      select 1 from apoiarcred_private.webhook_deliveries d
      join apoiarcred_private.webhook_events e on e.id=d.event_id
      where e.user_id=owner_id and d.state='delivering' and d.locked_until>now()
    )
  then raise exception 'Aguarde as consultas e entregas de webhook em execução terminarem. Pause as campanhas antes de tentar novamente.'; end if;

  delete from public.crm_oportunidades where user_id=owner_id;
  get diagnostics opportunity_count=row_count;
  delete from public.consulta_jobs where user_id=owner_id;
  get diagnostics job_count=row_count;
  delete from public.tjba_jobs where user_id=owner_id;
  get diagnostics count_tjba=row_count;
  delete from public.consulta_lotes where user_id=owner_id;
  get diagnostics lot_count=row_count;
  delete from public.tjba_lotes where user_id=owner_id;
  get diagnostics count_tjba_lots=row_count;
  delete from public.crm_cadastros where user_id=owner_id;
  get diagnostics client_count=row_count;
  delete from apoiarcred_private.webhook_events where user_id=owner_id;
  delete from apoiarcred_private.webhook_campaign_dirty where user_id=owner_id;
  update apoiarcred_private.webhooks set active=false
    where user_id=owner_id and scope='campaign';

  -- Retain the request fingerprints for the existing replay window while
  -- removing cached payloads and preventing retries from recreating records.
  update apoiarcred_private.api_idempotency i
    set response=apoiarcred_private.api_error(410,'account_data_reset','Os registros desta operação foram apagados.')
    from apoiarcred_private.api_tokens t
    where i.token_id=t.id and t.user_id=owner_id;

  return jsonb_build_object('clientes',client_count,'oportunidades',opportunity_count,
    'consultas',job_count+count_tjba,'lotes',lot_count+count_tjba_lots);
end $$;
revoke all on function apoiarcred_private.crm_reset_account(text) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_reset_account(text) to authenticated;

create or replace function public.crm_reset_account(p_confirmation text)
returns jsonb language sql security invoker set search_path='' as $$
  select apoiarcred_private.crm_reset_account(p_confirmation);
$$;
revoke all on function public.crm_reset_account(text) from public,anon,authenticated;
grant execute on function public.crm_reset_account(text) to authenticated;

notify pgrst,'reload schema';
commit;
begin;

create table if not exists public.crm_catalogo_importacao (
  uf text not null,
  codigo text not null,
  nome text not null,
  servicos text[] not null,
  primary key (uf,codigo)
);
alter table public.crm_catalogo_importacao enable row level security;
revoke all on public.crm_catalogo_importacao from public,anon,authenticated;
grant select on public.crm_catalogo_importacao to authenticated;
drop policy if exists crm_catalogo_importacao_leitura on public.crm_catalogo_importacao;
create policy crm_catalogo_importacao_leitura on public.crm_catalogo_importacao
  for select to authenticated using (true);

-- IDs Amigoz de vps/amigoz_convenios.json e códigos ConsigX de vps/tjba.py.
insert into public.crm_catalogo_importacao (uf,codigo,nome,servicos) values
  ('BA','tjba','Tribunal de Justiça da Bahia (TJBA)',array['consigx_margem','digimais_saldo']),
  ('BA','saeb','Governo do Estado da Bahia (SAEB)',array['consigx_margem','digimais_saldo']),
  ('BA','dpeba','Defensoria Pública da Bahia (DPEBA)',array['consigx_margem','digimais_saldo']),
  ('BA','embasa','EMBASA',array['consigx_margem','digimais_saldo']),
  ('BA','suprev','Superintendência de Previdência (SUPREV)',array['consigx_margem','digimais_saldo']),
  ('AC','amigoz_138','Prefeitura de Rio Branco - AC',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AL','amigoz_105','Governo de Alagoas - AL',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AL','amigoz_133','TJAL - Tribunal de Justiça de Alagoas - AL',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AM','amigoz_131','AMAZONPREV-AM',array['amigoz_saque','digimais_saldo']),
  ('AM','amigoz_132','Governo Amazonas - AM',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AM','amigoz_73','Manausprev - AM',array['amigoz_saque','digimais_saldo']),
  ('CE','amigoz_95','Governo do Ceará - CE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('CE','amigoz_30','Prefeitura de Juazeiro do Norte - CE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_56','Governo do Espírito Santo - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_159','IPAMV - Prev. Vitória - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_154','Prefeitura de Aracruz - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_143','Prefeitura de Linhares - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_115','Prefeitura de Serra - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('GO','amigoz_15','Governo de Goias',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('GO','amigoz_97','Prefeitura de Caldas Novas - GO',array['amigoz_saque','digimais_saldo']),
  ('GO','amigoz_166','Prefeitura de Valparaíso de Goiás - GO',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MA','amigoz_39','Governo do Maranhão - MA',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MA','amigoz_100','Prefeitura de São Luís - MA',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_52','Bombeiros Militar - Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_53','Defensoria - Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_48','Governo de Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_50','IPSEMG - MG - Previdencia',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_49','IPSM - MG - Militares',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_146','JFPREV - Prev. Juiz de Fora - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_51','Policia Militar - Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_96','Prefeitura de Betim - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_83','Prefeitura de Contagem - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_11','Prefeitura de Juiz de Fora - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_162','Prefeitura de Mariana - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_47','Prefeitura de Nova Lima - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_110','Prefeitura de Sabará - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_112','Prefeitura de Uberaba - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_4','Tribunal de Justiça de Minas Gerais',array['amigoz_saque','digimais_saldo']),
  ('MS','amigoz_81','IMPCG - Inst. Mun. de Prev. de Campo Grande – MS',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MT','amigoz_12','Prefeitura de Sorriso - MT',array['amigoz_saque','digimais_saldo']),
  ('MT','amigoz_20','Prefeitura de Tangará da Serra - MT',array['amigoz_saque','digimais_saldo']),
  ('MT','amigoz_43','Previso - MT',array['amigoz_saque','digimais_saldo']),
  ('PA','amigoz_157','Prefeitura de Belém - Compra Cliente',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PA','amigoz_156','Prefeitura de Belém - PA',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PB','amigoz_46','Governo da Paraíba - PB',array['amigoz_saque','digimais_saldo']),
  ('PB','amigoz_67','IPSEM - Instituto de Previdência Campina de Grande - PB',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PB','amigoz_3','Prefeitura de Campina Grande - PB',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PB','amigoz_2','Prefeitura de João Pessoa - PB',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_139','Governo de Pernambuco - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_160','IPMC - Prev. Carpina - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_116','Prefeitura de Carpina - PE',array['amigoz_saque','digimais_saldo']),
  ('PE','amigoz_35','Prefeitura de Jaboatão dos Guararapes - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_40','Prefeitura de Olinda - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_1','Prefeitura de Recife - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PI','amigoz_25','Governo de Piauí',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_93','Governo do Paraná - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_142','IPMC - Prev. Cascavel - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_34','MaringaPrev - PR',array['amigoz_saque','digimais_saldo']),
  ('PR','amigoz_106','Prefeitura de Cascavel - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_122','Prefeitura de Cascavel - PR - (SEMED e SESAU)',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_45','Prefeitura de Curitiba - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_32','Prefeitura de Maringa - PR',array['amigoz_saque','digimais_saldo']),
  ('PR','amigoz_152','Prefeitura de Medianeira - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_102','Prefeitura de Ponta Grossa - PR',array['amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_141','Prefeitura de Macaé - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_76','Prefeitura de Nova Iguaçu - RJ',array['amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_163','Prefeitura de Saquarema - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_124','Prefeitura de São Pedro da Aldeia - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_126','PREVINI-RJ',array['amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_167','SGPREVI - Prev. São Gonçalo - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_55','Prefeitura de Macaíba - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_151','Prefeitura de Mossoró - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_19','Prefeitura de Natal - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_18','Prefeitura de Parnamirim - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RO','amigoz_68','Governo de Rondônia - RO',array['amigoz_saque','digimais_saldo']),
  ('RO','amigoz_145','Prefeitura de Ariquemes - RO',array['amigoz_saque','digimais_saldo']),
  ('RO','amigoz_29','Prefeitura de Porto Velho - RO',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RR','amigoz_104','IPER - Inst. de Prev. de Roraima - RR',array['amigoz_saque','digimais_saldo']),
  ('RR','amigoz_118','Prefeitura de Boa Vista - RR',array['amigoz_saque','digimais_saldo']),
  ('SC','amigoz_148','Prefeitura de Chapecó - SC',array['amigoz_saque','digimais_saldo']),
  ('SC','amigoz_58','Prefeitura de Navegantes - SC',array['amigoz_saque','digimais_saldo']),
  ('SE','amigoz_147','Prefeitura de Aracaju - SE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_23','Governo de São Paulo',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_135','Governo de São Paulo - Lei 500',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_26','Governo de São Paulo - Secr. da Educação',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_70','IPMO - Inst. Prev. de Osasco - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_28','IPREM - SP - APOSENTADOS',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_27','IPREM - SP - PENSIONISTAS',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_129','IPREV -  Santos - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_99','IPSA - Inst. de Prev. de Santo André - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_33','Polícia Militar - São Paulo',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_54','Prefeitura Campinas - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_140','Prefeitura de Araraquara - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_92','Prefeitura de Campinas – SP – Celetistas',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_127','Prefeitura de Ferraz de Vasconcelos - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_144','Prefeitura de Guarulhos - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_137','Prefeitura de Ilhabela - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_155','Prefeitura de Itapeva - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_158','Prefeitura de Jundiaí - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_130','Prefeitura de Mauá - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_123','Prefeitura de Praia Grande - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_85','Prefeitura de Ribeirão Preto -SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_74','Prefeitura de Santo André - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_61','Prefeitura de Santos -SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_66','Prefeitura de Sorocaba - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_41','Prefeitura de Suzano - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_164','Prefeitura de São Bernardo do Campo - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_134','Prefeitura de São José do Rio Preto - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_108','Prefeitura de São José dos Campos - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_17','Prefeitura de São Paulo - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_165','Prefeitura de Taboão da Serra - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_31','SPPREV - São Paulo - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_168','TJSP - Tribunal de Justiça de São Paulo',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('TO','amigoz_60','Prefeitura de Araguaína - TO',array['amigoz_margem','amigoz_saque','digimais_saldo'])
on conflict (uf,codigo) do update set nome=excluded.nome,servicos=excluded.servicos;

alter table public.crm_classificacoes add column if not exists servicos_planejados text[];
update public.crm_classificacoes
set servicos_planejados=case when usar_digimais then array['digimais_saldo']::text[] else '{}'::text[] end
where servicos_planejados is null;
alter table public.crm_classificacoes alter column servicos_planejados set default '{}'::text[];
alter table public.crm_classificacoes alter column servicos_planejados set not null;

create or replace function apoiarcred_private.crm_import_catalog_clients(
  p_uf text, p_convenio text, p_servicos text[], p_rows jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
  allowed text[];
  imported integer;
begin
  select servicos into allowed from public.crm_catalogo_importacao
  where uf=p_uf and codigo=p_convenio;
  if allowed is null then raise exception 'Escolha um convênio cadastrado para o estado.'; end if;
  if p_servicos is null or array_position(p_servicos,null) is not null
    or not (p_servicos <@ allowed) then
    raise exception 'Há consultas incompatíveis com o convênio selecionado.';
  end if;
  imported := apoiarcred_private.crm_import_clients(
    p_uf,p_convenio,'digimais_saldo'=any(p_servicos),p_rows
  );
  update public.crm_classificacoes c set servicos_planejados=(
    select array(select distinct s from unnest(p_servicos) as t(s) order by s)
  )
  where c.user_id=auth.uid() and c.uf=p_uf and c.convenio=p_convenio
    and exists (select 1 from jsonb_to_recordset(p_rows) as r(cpf text) where r.cpf=c.cpf);
  return imported;
end $$;
revoke all on function apoiarcred_private.crm_import_catalog_clients(text,text,text[],jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_import_catalog_clients(text,text,text[],jsonb) to authenticated;

create or replace function public.crm_import_catalog_clients(
  p_uf text, p_convenio text, p_servicos text[], p_rows jsonb
) returns integer language sql security invoker set search_path='' as $$
  select apoiarcred_private.crm_import_catalog_clients(p_uf,p_convenio,p_servicos,p_rows);
$$;
revoke all on function public.crm_import_catalog_clients(text,text,text[],jsonb) from public,anon,authenticated;
grant execute on function public.crm_import_catalog_clients(text,text,text[],jsonb) to authenticated;
notify pgrst,'reload schema';
commit;

-- Automatic consultations selected in CRM imports
begin;
alter table public.crm_catalogo_importacao add column if not exists matricula_obrigatoria boolean not null default false;
alter table public.crm_catalogo_importacao add column if not exists senha_servidor boolean not null default false;
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_138';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_105';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_133';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_131';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_132';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_73';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_16';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_75';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_13';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_94';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_95';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_30';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_56';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_159';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_154';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_143';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_115';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_15';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_97';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_166';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_39';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_100';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_52';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_53';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_48';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_50';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_49';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_146';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_51';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_96';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_83';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_11';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_162';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_47';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_110';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_112';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_4';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_81';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_12';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_20';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_43';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_157';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_156';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_46';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_67';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_3';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_2';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_139';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_160';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_116';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_35';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_40';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_1';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_25';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_93';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_142';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_34';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_106';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_122';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_45';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_32';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_152';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_102';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_141';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_76';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_163';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_124';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_126';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_167';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_55';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_151';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_19';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_18';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_68';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_145';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_29';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_104';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_118';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_148';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_58';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_147';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_23';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_135';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_26';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_70';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_28';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_27';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_129';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_99';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_33';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_54';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_140';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_92';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_127';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_144';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_137';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_155';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_158';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_130';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_123';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_85';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_74';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_61';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_66';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=false where codigo='amigoz_41';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=true where codigo='amigoz_164';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_134';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_108';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_17';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_165';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_31';
update public.crm_catalogo_importacao set matricula_obrigatoria=true, senha_servidor=false where codigo='amigoz_168';
update public.crm_catalogo_importacao set matricula_obrigatoria=false, senha_servidor=true where codigo='amigoz_60';
create table public.crm_import_requests (
 user_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null, fingerprint text not null, response jsonb not null,
 created_at timestamptz not null default now(), primary key(user_id,request_id)
);
alter table public.crm_import_requests enable row level security;
revoke all on public.crm_import_requests from public,anon,authenticated;

create table public.amigoz_jobs (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null, cpf text not null, nome text, telefone text,
 convenio text not null, uf text not null, modo text not null check(modo in ('saque','margem','ambos')),
 numero_matricula text, import_id uuid not null,
 status text not null default 'aguardando' check(status in ('aguardando','processando','concluida','erro','revisao')),
 message text, resultado jsonb, created_at timestamptz not null default now(),
 consultado_em timestamptz, locked_at timestamptz, lease uuid,
 foreign key(user_id,cpf) references public.crm_cadastros(user_id,cpf) on delete cascade,
 unique(user_id,import_id,cpf)
);
alter table public.amigoz_jobs enable row level security;
revoke all on public.amigoz_jobs from public,anon,authenticated;
grant select on public.amigoz_jobs to authenticated;
grant all on public.amigoz_jobs to service_role;
create policy amigoz_jobs_owner on public.amigoz_jobs for select to authenticated using(user_id=(select auth.uid()));
create index amigoz_jobs_pending on public.amigoz_jobs(created_at,id) where status in ('aguardando','processando');
create index amigoz_jobs_client on public.amigoz_jobs(user_id,cpf);

create function apoiarcred_private.crm_import_and_start(p_request_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); fingerprint text; previous public.crm_import_requests;
 count_clients integer; n integer=0; cid uuid; lots jsonb='[]'; mode text;
 agreement public.crm_catalogo_importacao; result jsonb; row jsonb;
begin
 if uid is null or p_request_id is null then raise insufficient_privilege;end if;
 -- Serialize retries of one confirmation; an ambiguous HTTP response is safe to retry.
 perform pg_advisory_xact_lock(hashtextextended(uid::text||p_request_id::text,0));
 fingerprint=md5(jsonb_build_object('uf',p_uf,'convenio',p_convenio,'servicos',p_servicos,'rows',p_rows)::text);
 select * into previous from public.crm_import_requests where user_id=uid and request_id=p_request_id;
 if found then
  if previous.fingerprint<>fingerprint then raise exception 'Esta confirmação já foi usada com outros dados. Reabra a importação.';end if;
  return previous.response;
 end if;
 count_clients=apoiarcred_private.crm_import_catalog_clients(p_uf,p_convenio,p_servicos,p_rows);
 select * into agreement from public.crm_catalogo_importacao where uf=p_uf and codigo=p_convenio;
 if 'digimais_saldo'=any(p_servicos) then
  if exists(select 1 from jsonb_to_recordset(p_rows) x(nome text,telefone text) where coalesce(length(btrim(nome)),0)=0 or coalesce(telefone,'')!~'^[0-9]{10,13}$') then
   raise exception 'Digi+ exige nome e telefone com DDD em todas as linhas.';
  end if;
  cid=public.create_consulta_campaign('Importação · '||left(agreement.nome,100)||' · Digi+',p_rows);
  lots=lots||jsonb_build_array(jsonb_build_object('id',cid,'servico','digimais_saldo_parcela'));
  n=n+count_clients;
 end if;
 if 'consigx_margem'=any(p_servicos) then
  cid=public.create_consigx_campaign('Importação · '||left(agreement.nome,100)||' · ConsigX',p_rows,p_convenio);
  lots=lots||jsonb_build_array(jsonb_build_object('id',cid,'servico','tjba_margem'));
  n=n+count_clients;
 end if;
 if p_servicos && array['amigoz_saque','amigoz_margem'] then
  mode=case when array['amigoz_saque','amigoz_margem'] <@ p_servicos then 'ambos' when 'amigoz_margem'=any(p_servicos) then 'margem' else 'saque' end;
  if exists(select 1 from jsonb_array_elements(p_rows) x where length(coalesce(x->>'numero_matricula',''))>256) then raise exception 'Matrícula deve ter até 256 caracteres.';end if;
  -- Same shared quota and access contract as the Amigoz individual API.
  for row in select value from jsonb_array_elements(p_rows) loop
   perform public.authorize_amigoz(uid,true);
   insert into public.amigoz_jobs(user_id,cpf,nome,telefone,convenio,uf,modo,numero_matricula,import_id)
   values(uid,row->>'cpf',row->>'nome',row->>'telefone',p_convenio,p_uf,mode,nullif(btrim(row->>'numero_matricula'),''),p_request_id);
  end loop;
  n=n+count_clients;
 end if;
 result=jsonb_build_object('clientes',count_clients,'consultas',n,'campanhas',lots);
 insert into public.crm_import_requests(user_id,request_id,fingerprint,response) values(uid,p_request_id,fingerprint,result);
 return result;
end $$;
revoke all on function apoiarcred_private.crm_import_and_start(uuid,text,text,text[],jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_import_and_start(uuid,text,text,text[],jsonb) to authenticated;
create function public.crm_import_and_start(p_request_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select apoiarcred_private.crm_import_and_start(p_request_id,p_uf,p_convenio,p_servicos,p_rows) $$;
revoke all on function public.crm_import_and_start(uuid,text,text,text[],jsonb) from public,anon,authenticated;
grant execute on function public.crm_import_and_start(uuid,text,text,text[],jsonb) to authenticated;

create function public.claim_amigoz_import_job() returns setof public.amigoz_jobs language plpgsql security invoker set search_path='' as $$
declare job public.amigoz_jobs;
begin
 -- A lost process may have called the provider: do not blindly repeat that charge.
 update public.amigoz_jobs set status='revisao',message='Execução interrompida durante reinício. Confira antes de repetir.',consultado_em=now()
 where status='processando' and locked_at<now()-interval '10 minutes';
 select * into job from public.amigoz_jobs where status='aguardando' order by created_at,id for update skip locked limit 1;
 if not found then return;end if;
 begin
  perform public.authorize_amigoz(job.user_id,false);
 exception when insufficient_privilege then
  update public.amigoz_jobs set status='revisao',message='Acesso Amigoz revogado ou teste encerrado.',consultado_em=now() where id=job.id;
  return;
 end;
 return query update public.amigoz_jobs set status='processando',locked_at=now(),lease=gen_random_uuid(),message='Consultando…' where id=job.id returning *;
end $$;
revoke all on function public.claim_amigoz_import_job() from public,anon,authenticated;
grant execute on function public.claim_amigoz_import_job() to service_role;

create function public.finish_amigoz_import_job(p_id uuid,p_lease uuid,p_status text,p_resultado jsonb,p_message text)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
 if p_status not in ('concluida','erro','revisao') then raise exception 'Status inválido';end if;
 update public.amigoz_jobs set status=p_status,resultado=p_resultado,message=p_message,consultado_em=now()
 where id=p_id and lease=p_lease and status='processando';
 return found;
end $$;
revoke all on function public.finish_amigoz_import_job(uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.finish_amigoz_import_job(uuid,uuid,text,jsonb,text) to service_role;

create or replace view public.crm_consultas with (security_invoker=true) as
select id, user_id, cpf, nome, telefone, servico, null::text as convenio,
       status, created_at, consultado_em, null::text as matricula,
       null::text as situacao_atual, null::numeric as emprestimo_disponivel,
       null::numeric as cartao_disponivel, saldo_liquidacao, valor_parcela, null::jsonb as resultado_amigoz, null::text as detalhe
from public.consulta_jobs
union all
select id, user_id, cpf, nome, telefone, servico, convenio,
       status, created_at, consultado_em, matricula, situacao_atual,
       emprestimo_disponivel, cartao_disponivel, null::numeric, null::numeric, null::jsonb, null::text
from public.tjba_jobs
union all
select id,user_id,cpf,nome,telefone,'amigoz_'||modo,convenio,status,created_at,consultado_em,
 numero_matricula,null::text,null::numeric,null::numeric,null::numeric,null::numeric,resultado,message
from public.amigoz_jobs;
create trigger crm_sync_amigoz after insert or update of consultado_em on public.amigoz_jobs
for each row execute function apoiarcred_private.crm_sync_job();
-- Account reset must wait for an external Amigoz call just like the other robots.
create function apoiarcred_private.guard_amigoz_client_delete() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.amigoz_jobs where user_id=old.user_id and cpf=old.cpf for update;
 if exists(select 1 from public.amigoz_jobs where user_id=old.user_id and cpf=old.cpf and status='processando') then
  raise exception 'Aguarde a consulta Amigoz terminar antes de apagar este cadastro ou zerar a conta.';
 end if;
 return old;
end $$;
revoke all on function apoiarcred_private.guard_amigoz_client_delete() from public,anon,authenticated;
create trigger guard_amigoz_client_delete before delete on public.crm_cadastros for each row execute function apoiarcred_private.guard_amigoz_client_delete();
notify pgrst,'reload schema';
commit;

begin;
create function public.start_amigoz_individual(p_actor uuid,p_cpf text,p_convenio text,p_uf text,p_modo text,p_matricula text default null)
returns public.amigoz_jobs language plpgsql security invoker set search_path='' as $$
declare job public.amigoz_jobs;
begin
 if p_cpf is null or p_cpf!~'^[0-9]{11}$' or p_modo is null or p_modo not in ('saque','margem','ambos') then raise exception 'Consulta inválida';end if;
 if not exists(select 1 from public.crm_catalogo_importacao where codigo=p_convenio and uf=p_uf) and p_uf<>'BR' then raise exception 'Convênio inválido';end if;
 perform public.authorize_amigoz(p_actor,true);
 insert into public.crm_cadastros(user_id,cpf,ultima_atividade) values(p_actor,p_cpf,now())
 on conflict(user_id,cpf) do update set ultima_atividade=excluded.ultima_atividade;
 insert into public.amigoz_jobs(user_id,cpf,convenio,uf,modo,numero_matricula,import_id,status,lease,locked_at,message)
 values(p_actor,p_cpf,p_convenio,p_uf,p_modo,nullif(p_matricula,''),gen_random_uuid(),'processando',gen_random_uuid(),now(),'Consultando…') returning * into job;
 return job;
end $$;
revoke all on function public.start_amigoz_individual(uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.start_amigoz_individual(uuid,text,text,text,text,text) to service_role;
notify pgrst,'reload schema';
commit;
