-- Fase 2c, etapa 3: o painel deixa de baixar as consultas de campanha.
-- 1. painel_consultas_sync ganha p_escopo (as avulsas são buscadas pelas suas campanhas, pelo índice de lote): 'avulsas' devolve as campanhas (poucas linhas) e só as consultas
--    avulsas; as consultas de campanha chegam página a página por painel_campanha (etapa 2).
--    'tudo' (padrão) mantém o comportamento atual para painéis ainda não atualizados.
-- 2. public.painel_log_consultas: os logs de Configurações (robôs e API Digi+) buscam as consultas
--    encerradas mais recentes no banco, em vez de filtrar a lista completa no navegador.

begin;

do $$
declare def text; n integer;
begin
 def:=pg_get_functiondef('public.painel_consultas_sync(text,text,text)'::regprocedure);
 if position('p_after text DEFAULT NULL::text)' in def)=0 then raise exception 'Assinatura de painel_consultas_sync inesperada';end if;
 def:=replace(def,'p_after text DEFAULT NULL::text)','p_after text DEFAULT NULL::text, p_escopo text DEFAULT ''tudo''::text)');
 n:=(length(def)-length(replace(def,'select r.* from public.consulta_jobs r','')))/length('select r.* from public.consulta_jobs r');
 if n<>1 then raise exception 'Trecho de consulta_jobs não encontrado (%).',n;end if;
 n:=(length(def)-length(replace(def,'select r.* from public.tjba_jobs r','')))/length('select r.* from public.tjba_jobs r');
 if n<>1 then raise exception 'Trecho de tjba_jobs não encontrado (%).',n;end if;
 def:=regexp_replace(def,'select r\.\* from public\.consulta_jobs r\s+where ',
  E'select r.* from public.consulta_jobs r\n  where (p_escopo<>''avulsas'' or r.lote_id=any(array(select l.id from public.consulta_lotes l where l.tipo<>''campanha'' and l.tenant_id=(select apoiarcred_private.current_tenant()))))\n  and ');
 def:=regexp_replace(def,'select r\.\* from public\.tjba_jobs r\s+where ',
  E'select r.* from public.tjba_jobs r\n  where (p_escopo<>''avulsas'' or r.lote_id=any(array(select l.id from public.tjba_lotes l where l.tipo<>''campanha'' and l.tenant_id=(select apoiarcred_private.current_tenant()))))\n  and ');
 if position('p_escopo<>''avulsas'' or r.lote_id=any(array(select l.id from public.tjba_lotes' in def)=0 then raise exception 'Filtro não aplicado';end if;
 drop function public.painel_consultas_sync(text,text,text);
 execute def;
end $$;
revoke all on function public.painel_consultas_sync(text,text,text,text) from public,anon;
grant execute on function public.painel_consultas_sync(text,text,text,text) to authenticated;

-- Para os logs: as encerradas mais recentes da empresa.
create index if not exists consulta_jobs_recentes on public.consulta_jobs(tenant_id,(coalesce(consultado_em,created_at)) desc);
create index if not exists tjba_jobs_recentes on public.tjba_jobs(tenant_id,(coalesce(consultado_em,created_at)) desc);
create index if not exists consulta_jobs_api_recentes on public.consulta_jobs(tenant_id,(coalesce(consultado_em,created_at)) desc)
 where api_handoff is not null or execution_mode='api';

-- p_modo 'robo': consultas encerradas feitas pelos robôs (Digi+ fora da API e ConsigX), filtradas pelo robô.
-- p_modo 'api': consultas da API Digi+ encerradas ou encaminhadas ao robô, filtradas pela API.
-- p_slot: '' todos, 'unassigned' sem executor, ou o número. Até 500 linhas, das mais recentes.
create function public.painel_log_consultas(p_modo text,p_slot text default '',p_limite integer default 200)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tenant uuid; me uuid=auth.uid(); all_company boolean; size integer; slot integer; result jsonb;
 performed text[]:=array['concluida','nao_cliente','nao_localizado','ja_vendeu','nao_encontrado','erro','revisao','interrompida'];
begin
 if me is null then raise insufficient_privilege;end if;
 if p_modo not in ('robo','api') then raise exception 'Modo de log inválido.';end if;
 tenant:=apoiarcred_private.current_tenant();
 all_company:=apoiarcred_private.current_sees_company();
 size:=least(greatest(coalesce(p_limite,200),1),500);
 slot:=case when coalesce(p_slot,'') ~ '^[0-9]+$' then p_slot::integer end;
 if p_modo='robo' then
  with rows as (
   (select r.id,coalesce(r.consultado_em,r.created_at) quando,jsonb_build_object('id',r.id,'lote_id',r.lote_id,'nome',r.nome,'cpf',r.cpf,
     'telefone',r.telefone,'progress',r.progress,'stage',r.stage,'status',r.status,'valor_parcela',r.valor_parcela,
     'saldo_liquidacao',r.saldo_liquidacao,'total_parcelas',r.total_parcelas,'created_at',r.created_at,'consultado_em',r.consultado_em,
     'attempts',r.attempts,'servico',r.servico,'robot_slot',r.robot_slot,'execution_mode',r.execution_mode,'api_slot',r.api_slot,
     'message',left(r.message,500)) dados
    from public.consulta_jobs r
    where r.tenant_id=tenant and (all_company or r.user_id=me) and r.execution_mode is distinct from 'api'
     and r.status=any(performed)
     and (coalesce(p_slot,'')='' or (p_slot='unassigned' and r.robot_slot is null) or r.robot_slot=slot)
    order by coalesce(r.consultado_em,r.created_at) desc limit size)
   union all
   (select r.id,coalesce(r.consultado_em,r.created_at),jsonb_build_object('id',r.id,'lote_id',r.lote_id,'nome',r.nome,'cpf',r.cpf,
     'telefone',r.telefone,'progress',r.progress,'stage',r.stage,'status',r.status,'created_at',r.created_at,
     'consultado_em',r.consultado_em,'attempts',r.attempts,'servico',r.servico,'robot_slot',r.robot_slot,'convenio',r.convenio,
     'matricula',r.matricula,'situacao_atual',r.situacao_atual,'tjba_status',r.tjba_status,'message',left(r.message,500))
    from public.tjba_jobs r
    where r.tenant_id=tenant and (all_company or r.user_id=me) and r.status=any(performed)
     and (coalesce(p_slot,'')='' or (p_slot='unassigned' and r.robot_slot is null) or r.robot_slot=slot)
    order by coalesce(r.consultado_em,r.created_at) desc limit size)
  )
  select coalesce(jsonb_agg(dados order by quando desc,id),'[]') into result
  from (select * from rows order by quando desc,id limit size) x;
 else
  -- Ordenadas pela conclusão, pelo índice parcial das consultas da API; o painel reordena pela data do encaminhamento.
  select coalesce(jsonb_agg(dados order by quando desc,id),'[]') into result from (
   select r.id,coalesce(r.consultado_em,r.created_at) quando,
    jsonb_build_object('id',r.id,'lote_id',r.lote_id,'nome',r.nome,'cpf',r.cpf,'progress',r.progress,'stage',r.stage,
     'status',r.status,'created_at',r.created_at,'consultado_em',r.consultado_em,'servico',r.servico,'robot_slot',r.robot_slot,
     'execution_mode',r.execution_mode,'api_slot',r.api_slot,'message',left(r.message,500),
     'api_handoff',r.api_handoff-'resultado_saldo'-'resultado_parcela') dados
   from public.consulta_jobs r
   where r.tenant_id=tenant and (all_company or r.user_id=me)
    and (r.api_handoff is not null or r.execution_mode='api')
    and (r.api_handoff is not null or r.status=any(performed))
    and (coalesce(p_slot,'')='' or (p_slot='unassigned' and coalesce((r.api_handoff->>'api_slot')::integer,r.api_slot) is null)
     or coalesce((r.api_handoff->>'api_slot')::integer,r.api_slot)=slot)
   order by coalesce(r.consultado_em,r.created_at) desc,r.id limit size) x;
 end if;
 return result;
end $$;
revoke all on function public.painel_log_consultas(text,text,integer) from public,anon;
grant execute on function public.painel_log_consultas(text,text,integer) to authenticated;

commit;
