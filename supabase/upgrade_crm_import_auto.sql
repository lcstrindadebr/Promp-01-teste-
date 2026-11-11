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
