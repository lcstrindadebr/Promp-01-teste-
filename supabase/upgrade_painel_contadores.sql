-- Fase 2c, etapa 1: contadores do painel mantidos no banco.
-- Em vez de o painel baixar todas as consultas para contar, o banco guarda quantas consultas há em cada
-- situação, por campanha (lote), usuário e situação. Gatilhos mantêm os números na mesma transação de
-- cada consulta criada, alterada ou excluída: soma 1 na situação nova e tira 1 da antiga.
-- public.painel_resumo() devolve, em poucas linhas, o que o Início e os contadores da consulta
-- individual mostram. Uma conferência diária compara com a contagem real e corrige diferenças.

begin;
create table apoiarcred_private.painel_contadores(
 lote_id uuid not null,
 status text not null,
 user_id uuid not null,
 tenant_id uuid,
 origem text not null check(origem in ('consulta_jobs','tjba_jobs')),
 servico text not null,
 n bigint not null,
 primary key(lote_id,status,user_id)
);
create index painel_contadores_tenant on apoiarcred_private.painel_contadores(tenant_id);
alter table apoiarcred_private.painel_contadores enable row level security;
revoke all on apoiarcred_private.painel_contadores from public,anon,authenticated;

create table apoiarcred_private.painel_contadores_conferencias(
 conferido_em timestamptz primary key default now(),
 diferencas jsonb not null
);
alter table apoiarcred_private.painel_contadores_conferencias enable row level security;
revoke all on apoiarcred_private.painel_contadores_conferencias from public,anon,authenticated;

-- Soma (ou tira) n de uma chave; apaga a linha quando chega a zero.
create function apoiarcred_private.painel_ajustar(p_lote uuid,p_status text,p_user uuid,p_tenant uuid,
 p_origem text,p_servico text,p_delta bigint)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_delta=0 or p_lote is null then return;end if;
 insert into apoiarcred_private.painel_contadores as c(lote_id,status,user_id,tenant_id,origem,servico,n)
 values(p_lote,p_status,p_user,p_tenant,p_origem,p_servico,p_delta)
 on conflict(lote_id,status,user_id) do update set n=c.n+excluded.n,tenant_id=excluded.tenant_id;
 delete from apoiarcred_private.painel_contadores
  where lote_id=p_lote and status=p_status and user_id=p_user and n<=0;
end $$;

create function apoiarcred_private.painel_servico_padrao(p_origem text)
returns text language sql immutable set search_path='' as $$
 select case p_origem when 'tjba_jobs' then 'tjba_margem' else 'digimais_saldo_parcela' end
$$;

-- Inclusões e exclusões: um ajuste por chave e por comando (uma campanha de 11 mil clientes = 1 ajuste),
-- sempre na mesma ordem para que dois comandos simultâneos não se travem.
create function apoiarcred_private.painel_contar_lote()
returns trigger language plpgsql security definer set search_path='' as $$
declare k record; sign integer:=case when TG_OP='INSERT' then 1 else -1 end;
begin
 if TG_OP='INSERT' then
  for k in select lote_id,status,user_id,(array_agg(tenant_id))[1] tenant_id,
    coalesce((array_agg(servico))[1],apoiarcred_private.painel_servico_padrao(TG_TABLE_NAME)) servico,count(*) n
   from novos group by 1,2,3 order by 1,2,3 loop
   perform apoiarcred_private.painel_ajustar(k.lote_id,k.status,k.user_id,k.tenant_id,TG_TABLE_NAME,k.servico,sign*k.n);
  end loop;
 else
  for k in select lote_id,status,user_id,(array_agg(tenant_id))[1] tenant_id,
    coalesce((array_agg(servico))[1],apoiarcred_private.painel_servico_padrao(TG_TABLE_NAME)) servico,count(*) n
   from antigos group by 1,2,3 order by 1,2,3 loop
   perform apoiarcred_private.painel_ajustar(k.lote_id,k.status,k.user_id,k.tenant_id,TG_TABLE_NAME,k.servico,sign*k.n);
  end loop;
 end if;
 return null;
end $$;

-- Alterações: agrupa por comando o que mudou de situação, dono, campanha ou empresa (o progresso não
-- conta). Um "repetir erros" com 10 mil consultas vira poucos ajustes, e não 10 mil.
create function apoiarcred_private.painel_contar_atualizacao()
returns trigger language plpgsql security definer set search_path='' as $$
declare k record;
begin
 for k in
  with changed as (
   select o.lote_id ol,o.status os,o.user_id ou,o.tenant_id ot,n.lote_id nl,n.status ns,n.user_id nu,n.tenant_id nt,
    coalesce(n.servico,apoiarcred_private.painel_servico_padrao(TG_TABLE_NAME)) servico
   from antigos o join novos n on n.id=o.id
   where (o.status,o.lote_id,o.user_id,o.tenant_id) is distinct from (n.status,n.lote_id,n.user_id,n.tenant_id)
  ), deltas as (
   select ol lote_id,os status,ou user_id,ot tenant_id,servico,-1 d from changed
   union all select nl,ns,nu,nt,servico,1 from changed
  )
  select lote_id,status,user_id,(array_agg(tenant_id) filter (where d>0))[1] tenant_id_new,
   (array_agg(tenant_id))[1] tenant_id_any,min(servico) servico,sum(d) n
  from deltas group by 1,2,3 having sum(d)<>0 order by 1,2,3
 loop
  perform apoiarcred_private.painel_ajustar(k.lote_id,k.status,k.user_id,coalesce(k.tenant_id_new,k.tenant_id_any),
   TG_TABLE_NAME,k.servico,k.n);
 end loop;
 return null;
end $$;

-- Conta a partir das tabelas de consultas (usada no preenchimento inicial e na conferência).
create function apoiarcred_private.painel_contagem_real()
returns table(lote_id uuid,status text,user_id uuid,tenant_id uuid,origem text,servico text,n bigint)
language sql stable security definer set search_path='' as $$
 select lote_id,status,user_id,(array_agg(tenant_id))[1],'consulta_jobs',
  coalesce((array_agg(servico))[1],'digimais_saldo_parcela'),count(*)
 from public.consulta_jobs group by 1,2,3
 union all
 select lote_id,status,user_id,(array_agg(tenant_id))[1],'tjba_jobs',
  coalesce((array_agg(servico))[1],'tjba_margem'),count(*)
 from public.tjba_jobs group by 1,2,3
$$;

-- Compara o resumo com a contagem real (as duas no mesmo instante do banco) e, se pedido, corrige
-- somando a diferença. Grava as diferenças encontradas para acompanhamento.
create function apoiarcred_private.painel_contadores_conferir(p_corrigir boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare diffs jsonb; k record;
begin
 with real as (select * from apoiarcred_private.painel_contagem_real()),
 diff as (
  select coalesce(r.lote_id,c.lote_id) lote_id,coalesce(r.status,c.status) status,coalesce(r.user_id,c.user_id) user_id,
   coalesce(r.tenant_id,c.tenant_id) tenant_id,coalesce(r.origem,c.origem) origem,coalesce(r.servico,c.servico) servico,
   coalesce(r.n,0) real_n,coalesce(c.n,0) resumo_n
  from real r full join apoiarcred_private.painel_contadores c
   on c.lote_id=r.lote_id and c.status=r.status and c.user_id=r.user_id
  where coalesce(r.n,0)<>coalesce(c.n,0))
 select coalesce(jsonb_agg(to_jsonb(diff) order by lote_id,status,user_id),'[]') into diffs from diff;
 if jsonb_array_length(diffs)>0 then
  insert into apoiarcred_private.painel_contadores_conferencias(diferencas) values(diffs);
  if p_corrigir then
   for k in select * from jsonb_to_recordset(diffs) as x(lote_id uuid,status text,user_id uuid,tenant_id uuid,
     origem text,servico text,real_n bigint,resumo_n bigint) order by lote_id,status,user_id loop
    perform apoiarcred_private.painel_ajustar(k.lote_id,k.status,k.user_id,k.tenant_id,k.origem,k.servico,k.real_n-k.resumo_n);
   end loop;
  end if;
 end if;
 return jsonb_build_object('diferencas',jsonb_array_length(diffs),'corrigido',p_corrigir and jsonb_array_length(diffs)>0);
end $$;
revoke all on function apoiarcred_private.painel_ajustar(uuid,text,uuid,uuid,text,text,bigint),
 apoiarcred_private.painel_contar_lote(),apoiarcred_private.painel_contar_atualizacao(),
 apoiarcred_private.painel_contagem_real(),apoiarcred_private.painel_contadores_conferir(boolean)
 from public,anon,authenticated;

-- Para a lista "Precisam de atenção" do Início: as mais recentes com erro, revisão ou interrompida.
create index if not exists consulta_jobs_atencao on public.consulta_jobs(tenant_id,(coalesce(consultado_em,created_at)) desc)
 where status in ('erro','revisao','interrompida');
create index if not exists tjba_jobs_atencao on public.tjba_jobs(tenant_id,(coalesce(consultado_em,created_at)) desc)
 where status in ('erro','revisao','interrompida');

-- Gatilhos e preenchimento inicial na mesma transação, com as consultas travadas para escrita
-- (os robôs esperam menos de um segundo), para o resumo nascer igual à contagem real.
lock table public.consulta_jobs,public.tjba_jobs in share row exclusive mode;
create trigger painel_contar_insercao after insert on public.consulta_jobs
 referencing new table as novos for each statement execute function apoiarcred_private.painel_contar_lote();
create trigger painel_contar_exclusao after delete on public.consulta_jobs
 referencing old table as antigos for each statement execute function apoiarcred_private.painel_contar_lote();
create trigger painel_contar_atualizacao after update on public.consulta_jobs
 referencing old table as antigos new table as novos for each statement execute function apoiarcred_private.painel_contar_atualizacao();
create trigger painel_contar_insercao after insert on public.tjba_jobs
 referencing new table as novos for each statement execute function apoiarcred_private.painel_contar_lote();
create trigger painel_contar_exclusao after delete on public.tjba_jobs
 referencing old table as antigos for each statement execute function apoiarcred_private.painel_contar_lote();
create trigger painel_contar_atualizacao after update on public.tjba_jobs
 referencing old table as antigos new table as novos for each statement execute function apoiarcred_private.painel_contar_atualizacao();
insert into apoiarcred_private.painel_contadores select * from apoiarcred_private.painel_contagem_real();

-- Resumo para o painel: só a empresa atual e, para quem não vê a empresa toda, só o que é seu.
create function public.painel_resumo()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tenant uuid; me uuid=auth.uid(); all_company boolean; today timestamptz; result jsonb;
begin
 if me is null then raise insufficient_privilege;end if;
 tenant:=apoiarcred_private.current_tenant();
 all_company:=apoiarcred_private.current_sees_company();
 today:=(date_trunc('day',now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo';
 with visible as (
  select c.*,coalesce(cl.tipo,tl.tipo,'individual') tipo,coalesce(cl.nome,tl.nome) nome,
   coalesce(cl.paused,tl.paused,false) paused,coalesce(cl.created_at,tl.created_at) lote_criado
  from apoiarcred_private.painel_contadores c
  left join public.consulta_lotes cl on c.origem='consulta_jobs' and cl.id=c.lote_id
  left join public.tjba_lotes tl on c.origem='tjba_jobs' and tl.id=c.lote_id
  where c.tenant_id=tenant and (all_company or c.user_id=me)
 ), counts as (
  select servico,case when tipo='campanha' then 'campanha' else 'individual' end tipo,status,sum(n)::bigint n
  from visible group by 1,2,3
 ), active as (
  select lote_id id,min(nome) nome,min(servico) servico,bool_or(paused) paused,min(lote_criado) created_at,
   sum(n)::bigint total,sum(n) filter (where status in ('aguardando','processando'))::bigint pendentes
  from visible where tipo='campanha' group by lote_id
  having sum(n) filter (where status in ('aguardando','processando'))>0
 ), done_today as (
  select j.servico,count(*) n from public.consulta_jobs j
   where j.consultado_em>=today and j.status='concluida' and j.tenant_id=tenant and (all_company or j.user_id=me) group by 1
  union all
  select j.servico,count(*) from public.tjba_jobs j
   where j.consultado_em>=today and j.status='concluida' and j.tenant_id=tenant and (all_company or j.user_id=me) group by 1
 ), attention as (
  (select j.id,j.lote_id,j.nome,j.cpf,j.servico,j.status,coalesce(j.consultado_em,j.created_at) data from public.consulta_jobs j
   where j.status in ('erro','revisao','interrompida') and j.tenant_id=tenant and (all_company or j.user_id=me)
   order by coalesce(j.consultado_em,j.created_at) desc limit 6)
  union all
  (select j.id,j.lote_id,j.nome,j.cpf,j.servico,j.status,coalesce(j.consultado_em,j.created_at) from public.tjba_jobs j
   where j.status in ('erro','revisao','interrompida') and j.tenant_id=tenant and (all_company or j.user_id=me)
   order by coalesce(j.consultado_em,j.created_at) desc limit 6)
 )
 select jsonb_build_object('gerado_em',now(),
  'contagens',(select coalesce(jsonb_agg(to_jsonb(counts) order by servico,tipo,status),'[]') from counts),
  'campanhas_ativas',(select coalesce(jsonb_agg(to_jsonb(active) order by paused,created_at desc),'[]') from active),
  'concluidas_hoje',(select coalesce(jsonb_object_agg(servico,n),'{}') from (select servico,sum(n) n from done_today group by 1) d),
  'atencao',(select coalesce(jsonb_agg(to_jsonb(a) order by data desc),'[]') from (select * from attention order by data desc limit 6) a))
 into result;
 return result;
end $$;
revoke all on function public.painel_resumo() from public,anon;
grant execute on function public.painel_resumo() to authenticated;

-- Conferência diária às 3h17 (horário de Brasília), fora do horário de uso.
do $do$
begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') then
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname='apoiarcred-painel-contadores';
  perform cron.schedule('apoiarcred-painel-contadores','17 6 * * *',
   $cron$select apoiarcred_private.painel_contadores_conferir(true)$cron$);
 else
  raise notice 'pg_cron indisponível: rode apoiarcred_private.painel_contadores_conferir() manualmente.';
 end if;
end $do$;
commit;
