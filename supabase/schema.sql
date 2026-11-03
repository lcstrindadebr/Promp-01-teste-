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
