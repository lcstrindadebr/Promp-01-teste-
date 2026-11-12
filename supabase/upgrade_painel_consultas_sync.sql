begin;
create table public.painel_exclusoes (
 user_id uuid not null references auth.users(id) on delete cascade,
 origem text not null, id uuid not null, sync_xid xid8 not null,
 primary key(user_id,origem,id)
);
create index painel_exclusoes_sync on public.painel_exclusoes(user_id,sync_xid);
alter table public.painel_exclusoes enable row level security;
revoke all on public.painel_exclusoes from public,anon,authenticated;
grant select on public.painel_exclusoes to authenticated;
create policy painel_exclusoes_conta on public.painel_exclusoes for select to authenticated using(user_id=(select auth.uid()));

create function apoiarcred_private.painel_marcar_mudanca() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
  -- During an account cascade the owner may already have been removed.
  insert into public.painel_exclusoes(user_id,origem,id,sync_xid)
  select old.user_id,tg_table_name,old.id,pg_current_xact_id() from auth.users where id=old.user_id
  on conflict(user_id,origem,id) do update set sync_xid=excluded.sync_xid;
  return old;
 end if;
 new.sync_xid=pg_current_xact_id();
 if tg_op='INSERT' then
  delete from public.painel_exclusoes where user_id=new.user_id and origem=tg_table_name and id=new.id;
 end if;
 return new;
end $$;
revoke all on function apoiarcred_private.painel_marcar_mudanca() from public,anon,authenticated;
alter table public.consulta_jobs add column sync_xid xid8;
create index consulta_jobs_painel_sync on public.consulta_jobs(user_id,sync_xid);
create trigger painel_marcar_mudanca before insert or update or delete on public.consulta_jobs
 for each row execute function apoiarcred_private.painel_marcar_mudanca();
alter table public.tjba_jobs add column sync_xid xid8;
create index tjba_jobs_painel_sync on public.tjba_jobs(user_id,sync_xid);
create trigger painel_marcar_mudanca before insert or update or delete on public.tjba_jobs
 for each row execute function apoiarcred_private.painel_marcar_mudanca();
alter table public.consulta_lotes add column sync_xid xid8;
create index consulta_lotes_painel_sync on public.consulta_lotes(user_id,sync_xid);
create trigger painel_marcar_mudanca before insert or update or delete on public.consulta_lotes
 for each row execute function apoiarcred_private.painel_marcar_mudanca();
alter table public.tjba_lotes add column sync_xid xid8;
create index tjba_lotes_painel_sync on public.tjba_lotes(user_id,sync_xid);
create trigger painel_marcar_mudanca before insert or update or delete on public.tjba_lotes
 for each row execute function apoiarcred_private.painel_marcar_mudanca();

create function public.painel_consultas_sync(p_since text default null,p_until text default null,p_after text default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare uid uuid=auth.uid(); previous pg_snapshot=p_since::pg_snapshot;
 cutoff pg_snapshot=coalesce(p_until::pg_snapshot,pg_current_snapshot()); result jsonb;
begin
 if uid is null then raise insufficient_privilege;end if;
 select coalesce(jsonb_agg(to_jsonb(page) order by page.chave),'[]') into result from (
 select 'consulta_jobs:'||r.id::text as chave,'consulta_jobs'::text as origem,r.id,
   r.sync_xid::text as revisao,false as excluido,jsonb_build_object('id',r.id,'lote_id',r.lote_id,'nome',r.nome,'cpf',r.cpf,'telefone',r.telefone,'progress',r.progress,'stage',r.stage,'status',r.status,'valor_parcela',r.valor_parcela,'saldo_liquidacao',r.saldo_liquidacao,'total_parcelas',r.total_parcelas,'created_at',r.created_at,'consultado_em',r.consultado_em,'attempts',r.attempts,'servico',r.servico,'queue_order',r.queue_order,'robot_slot',r.robot_slot,'execution_mode',r.execution_mode,'api_slot',r.api_slot,'message',left(r.message,500),'api_handoff',r.api_handoff-'resultado_saldo'-'resultado_parcela') as dados
 from public.consulta_jobs r
 where r.user_id=uid and 'consulta_jobs:'||r.id::text>coalesce(p_after,'')
 and (r.sync_xid is null or pg_visible_in_snapshot(r.sync_xid,cutoff))
 and (previous is null or (r.sync_xid>=pg_snapshot_xmin(previous) and not pg_visible_in_snapshot(r.sync_xid,previous)))
 union all
 select 'tjba_jobs:'||r.id::text as chave,'tjba_jobs'::text as origem,r.id,
   r.sync_xid::text as revisao,false as excluido,jsonb_build_object('id',r.id,'lote_id',r.lote_id,'nome',r.nome,'cpf',r.cpf,'telefone',r.telefone,'progress',r.progress,'stage',r.stage,'status',r.status,'created_at',r.created_at,'consultado_em',r.consultado_em,'attempts',r.attempts,'servico',r.servico,'queue_order',r.queue_order,'robot_slot',r.robot_slot,'convenio',r.convenio,'matricula',r.matricula,'tipo_servidor',r.tipo_servidor,'situacao_atual',r.situacao_atual,'emprestimo_disponivel',r.emprestimo_disponivel,'cartao_disponivel',r.cartao_disponivel,'tjba_status',r.tjba_status,'message',left(r.message,500)) as dados
 from public.tjba_jobs r
 where r.user_id=uid and 'tjba_jobs:'||r.id::text>coalesce(p_after,'')
 and (r.sync_xid is null or pg_visible_in_snapshot(r.sync_xid,cutoff))
 and (previous is null or (r.sync_xid>=pg_snapshot_xmin(previous) and not pg_visible_in_snapshot(r.sync_xid,previous)))
 union all
 select 'consulta_lotes:'||r.id::text as chave,'consulta_lotes'::text as origem,r.id,
   r.sync_xid::text as revisao,false as excluido,jsonb_build_object('id',r.id,'nome',r.nome,'created_at',r.created_at,'tipo',r.tipo,'servico',r.servico,'paused',r.paused,'auto_paused',r.auto_paused) as dados
 from public.consulta_lotes r
 where r.user_id=uid and 'consulta_lotes:'||r.id::text>coalesce(p_after,'')
 and (r.sync_xid is null or pg_visible_in_snapshot(r.sync_xid,cutoff))
 and (previous is null or (r.sync_xid>=pg_snapshot_xmin(previous) and not pg_visible_in_snapshot(r.sync_xid,previous)))
 union all
 select 'tjba_lotes:'||r.id::text as chave,'tjba_lotes'::text as origem,r.id,
   r.sync_xid::text as revisao,false as excluido,jsonb_build_object('id',r.id,'nome',r.nome,'created_at',r.created_at,'tipo',r.tipo,'servico',r.servico,'convenio',r.convenio,'paused',r.paused,'auto_paused',r.auto_paused) as dados
 from public.tjba_lotes r
 where r.user_id=uid and 'tjba_lotes:'||r.id::text>coalesce(p_after,'')
 and (r.sync_xid is null or pg_visible_in_snapshot(r.sync_xid,cutoff))
 and (previous is null or (r.sync_xid>=pg_snapshot_xmin(previous) and not pg_visible_in_snapshot(r.sync_xid,previous)))
 union all
 select d.origem||':'||d.id::text,d.origem,d.id,d.sync_xid::text,true,null::jsonb
 from public.painel_exclusoes d where d.user_id=uid and previous is not null
  and d.origem||':'||d.id::text>coalesce(p_after,'')
  and d.sync_xid>=pg_snapshot_xmin(previous) and not pg_visible_in_snapshot(d.sync_xid,previous)
  and pg_visible_in_snapshot(d.sync_xid,cutoff)
 order by chave limit 400
 ) page;
 return jsonb_build_object('snapshot',cutoff::text,'rows',result,
  'next',case when jsonb_array_length(result)=400 then result->399->>'chave' end);
end $$;
revoke all on function public.painel_consultas_sync(text,text,text) from public,anon;
grant execute on function public.painel_consultas_sync(text,text,text) to authenticated;
notify pgrst,'reload schema';

commit;
