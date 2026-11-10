begin;
alter table public.crm_cadastros add column if not exists data_nascimento date;
alter table public.crm_cadastros add column if not exists resumo_consultas jsonb not null default '{}';
alter table public.crm_oportunidades add column if not exists automatica boolean not null default false;
alter table public.crm_oportunidades add column if not exists sinais_consulta jsonb not null default '{}';
create unique index if not exists crm_uma_oportunidade_automatica
 on public.crm_oportunidades(user_id,cpf) where automatica;

create function apoiarcred_private.crm_consolidar(p_uid uuid,p_cpf text,p_fonte text,p_data timestamptz,p_dados jsonb,p_produto text)
returns void language plpgsql security definer set search_path='' as $$
begin
 update public.crm_cadastros
 set resumo_consultas=jsonb_set(resumo_consultas,array[p_fonte],jsonb_build_object('data',p_data,'dados',p_dados))
 where user_id=p_uid and cpf=p_cpf
 and coalesce((resumo_consultas->p_fonte->>'data')::timestamptz,'-infinity')<=p_data;
 if found and p_produto is not null then
  update public.crm_oportunidades
  set sinais_consulta=jsonb_set(sinais_consulta,array[p_fonte],p_dados)
  where user_id=p_uid and cpf=p_cpf and automatica;
  if not found then
   update public.crm_oportunidades set automatica=true,
    sinais_consulta=jsonb_set(sinais_consulta,array[p_fonte],p_dados)
   where id=(select id from public.crm_oportunidades
     where user_id=p_uid and cpf=p_cpf and etapa not in ('ganho','perdido')
     order by created_at desc,id desc limit 1);
  end if;
  if not found then
   insert into public.crm_oportunidades(user_id,cpf,nome,produto,automatica,sinais_consulta)
   select user_id,cpf,left(nome,160),p_produto,true,jsonb_build_object(p_fonte,p_dados)
   from public.crm_cadastros where user_id=p_uid and cpf=p_cpf
   on conflict do nothing;
  end if;
 elsif found then
  update public.crm_oportunidades set sinais_consulta=sinais_consulta-p_fonte
  where user_id=p_uid and cpf=p_cpf and automatica;
 end if;
end $$;
revoke all on function apoiarcred_private.crm_consolidar(uuid,text,text,timestamptz,jsonb,text) from public,anon,authenticated;

create function apoiarcred_private.crm_enriquecer_consulta()
returns trigger language plpgsql security definer set search_path='' as $$
declare item jsonb; dados jsonb; momento timestamptz:=coalesce(new.consultado_em,new.created_at);
begin
 if tg_table_name='consulta_jobs' then
  if new.status in ('concluida','nao_cliente') then
   perform apoiarcred_private.crm_consolidar(new.user_id,new.cpf,'digimais',momento,
    jsonb_build_object('status',new.status,'saldo',new.saldo_liquidacao,'parcela',new.valor_parcela),
    case when new.status='concluida' then 'recompra' end);
  end if;
  return new;
 end if;
 if new.resultado->'margem'->>'status'='respondido' then
  dados:=new.resultado->'margem'->'dados';
  if jsonb_typeof(dados)='array' then
   for item in select value from jsonb_array_elements(dados) loop
    if nullif(btrim(item->>'numeroMatricula'),'') is not null then
     insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,fonte,confirmado_em)
     values(new.user_id,new.cpf,new.uf,new.convenio,btrim(item->>'numeroMatricula'),'amigoz',momento)
     on conflict(user_id,cpf,uf,convenio,matricula) do update set fonte='amigoz',confirmado_em=excluded.confirmado_em
     where crm_vinculos.confirmado_em<=excluded.confirmado_em;
    end if;
   end loop;
   perform apoiarcred_private.crm_consolidar(new.user_id,new.cpf,'amigoz_margem_'||new.convenio,momento,dados,null);
  end if;
 end if;
 if new.resultado->'saque'->>'status'='respondido' then
  dados:=new.resultado->'saque'->'dados'->'ofertas';
  if jsonb_typeof(dados)='array' then
   for item in select value from jsonb_array_elements(dados) loop
    if item->>'erro_informado' is distinct from 'true' and
       nullif(btrim(coalesce(item->>'numeroMatricula',item->>'numero_matricula')),'') is not null then
     insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,fonte,confirmado_em)
     values(new.user_id,new.cpf,new.uf,new.convenio,btrim(coalesce(item->>'numeroMatricula',item->>'numero_matricula')),'amigoz',momento)
     on conflict(user_id,cpf,uf,convenio,matricula) do update set fonte='amigoz',confirmado_em=excluded.confirmado_em
     where crm_vinculos.confirmado_em<=excluded.confirmado_em;
    end if;
   end loop;
   perform apoiarcred_private.crm_consolidar(new.user_id,new.cpf,'amigoz_saque_'||new.convenio,momento,dados,
    case when exists(select 1 from jsonb_array_elements(dados) x
     where lower(x->>'elegivel')='sim' and x->>'erro_informado' is distinct from 'true'
       and case when jsonb_typeof(x->'valor_saque_disponivel')='number'
                then (x->>'valor_saque_disponivel')::numeric>0 else false end)
    then 'saque' end);
  end if;
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.crm_enriquecer_consulta() from public,anon,authenticated;
create trigger zz_crm_enriquecer_digi after insert or update of status,consultado_em on public.consulta_jobs
for each row execute function apoiarcred_private.crm_enriquecer_consulta();
create trigger zz_crm_enriquecer_amigoz after update of resultado on public.amigoz_jobs
for each row execute function apoiarcred_private.crm_enriquecer_consulta();
create or replace function apoiarcred_private.crm_import_and_start(p_request_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb)
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
 update public.crm_cadastros c set data_nascimento=x.data_nascimento::date
 from jsonb_to_recordset(p_rows) x(cpf text,data_nascimento text)
 where c.user_id=uid and c.cpf=x.cpf and nullif(x.data_nascimento,'') is not null;
 insert into public.crm_vinculos(user_id,cpf,uf,convenio,matricula,fonte,confirmado_em)
 select uid,x.cpf,p_uf,p_convenio,btrim(x.numero_matricula),'importacao',now()
 from jsonb_to_recordset(p_rows) x(cpf text,numero_matricula text)
 where nullif(btrim(x.numero_matricula),'') is not null
 on conflict(user_id,cpf,uf,convenio,matricula) do nothing;

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
create or replace view public.crm_opportunity_cards with(security_invoker=true) as
 select o.id,o.user_id,o.cpf,o.nome,o.produto,o.convenio,o.etapa,o.proxima_acao,o.created_at,o.campos,q.saldo_liquidacao,q.emprestimo_disponivel,q.consultado_em as resultado_em,q.created_at as resultado_criado_em,q.servico as resultado_fonte,o.automatica,o.sinais_consulta
 from public.crm_oportunidades o left join lateral (
 select c.saldo_liquidacao,c.emprestimo_disponivel,c.consultado_em,c.created_at,c.servico
 from public.crm_consultas c where c.user_id=o.user_id and c.cpf=o.cpf and
 ((o.produto='recompra' and c.servico='digimais_saldo_parcela' and c.saldo_liquidacao is not null)
 or (o.produto='margem' and o.convenio<>'' and c.convenio=o.convenio and c.servico='tjba_margem' and c.emprestimo_disponivel is not null))
 order by c.consultado_em desc nulls last,c.created_at desc,c.id desc limit 1
 ) q on true;

-- Replay existing Amigoz results through the same consolidation path.
update public.amigoz_jobs set resultado=resultado where resultado is not null;
-- Only the latest definitive Digi+ result per client seeds its signal.
do $$
declare j record;
begin
 for j in select distinct on(user_id,cpf) * from public.consulta_jobs
  where status in ('concluida','nao_cliente')
  order by user_id,cpf,coalesce(consultado_em,created_at) desc,id desc
 loop
  perform apoiarcred_private.crm_consolidar(j.user_id,j.cpf,'digimais',coalesce(j.consultado_em,j.created_at),
   jsonb_build_object('status',j.status,'saldo',j.saldo_liquidacao,'parcela',j.valor_parcela),
   case when j.status='concluida' then 'recompra' end);
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
