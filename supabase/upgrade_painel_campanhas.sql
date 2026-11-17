-- Fase 2c, etapa 2: campanhas paginadas no servidor.
-- public.painel_campanhas(): a lista de campanhas com os totais por situação, lidos do resumo da etapa 1.
-- public.painel_campanha(): o detalhe de uma campanha — números, ritmo para a previsão, quem está sendo
-- consultado agora — e só a página de clientes pedida (50 por vez), já buscada, filtrada e ordenada no banco.
-- As duas respeitam a empresa e, para quem não vê a empresa toda, só o que é seu.

begin;

create function public.painel_campanhas()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tenant uuid; me uuid=auth.uid(); all_company boolean; result jsonb;
begin
 if me is null then raise insufficient_privilege;end if;
 tenant:=apoiarcred_private.current_tenant();
 all_company:=apoiarcred_private.current_sees_company();
 with lots as (
  select l.id,l.nome,l.servico,null::text convenio,l.created_at,l.paused,l.auto_paused,'consulta_jobs'::text origem
  from public.consulta_lotes l
  where l.tipo='campanha' and l.tenant_id=tenant and (all_company or l.user_id=me)
  union all
  select l.id,l.nome,l.servico,l.convenio,l.created_at,l.paused,l.auto_paused,'tjba_jobs'
  from public.tjba_lotes l
  where l.tipo='campanha' and l.tenant_id=tenant and (all_company or l.user_id=me)
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'nome',l.nome,'servico',l.servico,'convenio',l.convenio,
   'created_at',l.created_at,'paused',l.paused,'auto_paused',l.auto_paused,
   'contagens',coalesce((select jsonb_object_agg(c.status,c.n) from (
     select c.status,sum(c.n)::bigint n from apoiarcred_private.painel_contadores c
     where c.lote_id=l.id and c.origem=l.origem group by c.status) c),'{}'))
  order by l.created_at,l.id),'[]')
 into result from lots l;
 return result;
end $$;
revoke all on function public.painel_campanhas() from public,anon;
grant execute on function public.painel_campanhas() to authenticated;

create function public.painel_campanha(p_id uuid,p_busca text default '',p_filtro text default '',
 p_pagina integer default 1,p_tamanho integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tenant uuid; me uuid=auth.uid(); all_company boolean; origem text; owner uuid; lot_tenant uuid;
 q text:=lower(btrim(coalesce(p_busca,''))); cpf_q text; statuses text[]; size integer; page integer;
 window_start timestamptz:=now()-interval '10 minutes'; result jsonb;
begin
 if me is null then raise insufficient_privilege;end if;
 tenant:=apoiarcred_private.current_tenant();
 all_company:=apoiarcred_private.current_sees_company();
 select 'consulta_jobs',l.user_id,l.tenant_id into origem,owner,lot_tenant from public.consulta_lotes l where l.id=p_id and l.tipo='campanha';
 if origem is null then
  select 'tjba_jobs',l.user_id,l.tenant_id into origem,owner,lot_tenant from public.tjba_lotes l where l.id=p_id and l.tipo='campanha';
 end if;
 if origem is null or lot_tenant is distinct from tenant or not (all_company or owner=me) then
  raise exception 'Campanha não encontrada.' using errcode='P0002';
 end if;
 -- Mesma busca do painel: trecho do nome ou do CPF; só números (com ponto, traço ou espaço) procuram no CPF.
 cpf_q:=case when q ~ '^[0-9.\-\s]+$' then regexp_replace(q,'\D','','g') else '' end;
 statuses:=case p_filtro
  when '' then null
  when 'attention' then array['erro','revisao','interrompida']
  when 'Aguardando' then array['aguardando'] when 'Processando' then array['processando']
  when 'Concluída' then array['concluida'] when 'Consulta interrompida' then array['interrompida']
  when 'Erro' then array['erro'] when 'Revisão' then array['revisao']
  else array[]::text[] end;
 size:=least(greatest(coalesce(p_tamanho,50),1),200);
 page:=greatest(coalesce(p_pagina,1),1);

 if origem='consulta_jobs' then
  with ranked as (
   select r.id,r.status,r.nome,r.cpf,r.consultado_em,r.saldo_liquidacao,r.valor_parcela,
    row_number() over (order by r.queue_order nulls last,r.created_at,r.id) posicao
   from public.consulta_jobs r where r.lote_id=p_id
  ), matched as (
   select * from ranked r
   where (statuses is null or r.status=any(statuses))
    and (q='' or position(q in lower(r.nome||' '||r.cpf))>0 or (cpf_q<>'' and position(cpf_q in r.cpf)>0))
  ), page_rows as (
   select r.*,m.posicao from (select id,posicao from matched order by posicao offset (page-1)*size limit size) m
   join public.consulta_jobs r on r.id=m.id
  )
  select jsonb_build_object(
   'id',p_id,'origem',origem,
   'resumo',(select jsonb_build_object('total',count(*),
     'clients',count(*) filter (where r.saldo_liquidacao is not null or r.valor_parcela is not null or r.status='concluida'),
     'nonclients',count(*) filter (where r.status in ('nao_cliente','nao_localizado','nao_encontrado')),
     'errors',count(*) filter (where r.status='erro'),'sold',count(*) filter (where r.status='ja_vendeu'),
     'review',count(*) filter (where r.status='revisao'),'interrupted',count(*) filter (where r.status='interrompida'),
     'waiting',count(*) filter (where r.status in ('aguardando','processando')),
     'running',count(*) filter (where r.status='processando'),
     'pace_count',count(*) filter (where r.status not in ('aguardando','processando') and r.consultado_em between window_start and now()),
     'pace_first',min(r.consultado_em) filter (where r.status not in ('aguardando','processando') and r.consultado_em between window_start and now()),
     'pace_last',max(r.consultado_em) filter (where r.status not in ('aguardando','processando') and r.consultado_em between window_start and now()))
    from ranked r),
   'consultando',(select coalesce(jsonb_agg(jsonb_build_object('nome',r.nome,'cpf',r.cpf) order by r.posicao),'[]')
    from (select * from ranked where status='processando' order by posicao limit 3) r),
   'filtrados',(select count(*) from matched),
   'pagina',page,'tamanho',size,
   'linhas',(select coalesce(jsonb_agg(jsonb_build_object('posicao',r.posicao,'dados',jsonb_build_object(
     'id',r.id,'lote_id',r.lote_id,'nome',r.nome,'cpf',r.cpf,'telefone',r.telefone,'progress',r.progress,'stage',r.stage,
     'status',r.status,'valor_parcela',r.valor_parcela,'saldo_liquidacao',r.saldo_liquidacao,'total_parcelas',r.total_parcelas,
     'created_at',r.created_at,'consultado_em',r.consultado_em,'attempts',r.attempts,'servico',r.servico,'queue_order',r.queue_order,
     'robot_slot',r.robot_slot,'execution_mode',r.execution_mode,'api_slot',r.api_slot,'message',left(r.message,500),
     'api_handoff',r.api_handoff-'resultado_saldo'-'resultado_parcela')) order by r.posicao),'[]') from page_rows r))
  into result;
 else
  with ranked as (
   select r.id,r.status,r.nome,r.cpf,r.consultado_em,r.emprestimo_disponivel,r.cartao_disponivel,r.matricula,
    row_number() over (order by r.queue_order nulls last,r.created_at,r.id) posicao
   from public.tjba_jobs r where r.lote_id=p_id
  ), matched as (
   select * from ranked r
   where (statuses is null or r.status=any(statuses))
    and (q='' or position(q in lower(r.nome||' '||r.cpf))>0 or (cpf_q<>'' and position(cpf_q in r.cpf)>0))
  ), page_rows as (
   select r.*,m.posicao from (select id,posicao from matched order by posicao offset (page-1)*size limit size) m
   join public.tjba_jobs r on r.id=m.id
  )
  select jsonb_build_object(
   'id',p_id,'origem',origem,
   'resumo',(select jsonb_build_object('total',count(*),
     'clients',count(*) filter (where r.emprestimo_disponivel is not null or r.cartao_disponivel is not null or r.matricula is not null or r.status='concluida'),
     'nonclients',count(*) filter (where r.status in ('nao_cliente','nao_localizado','nao_encontrado')),
     'errors',count(*) filter (where r.status='erro'),'sold',count(*) filter (where r.status='ja_vendeu'),
     'review',count(*) filter (where r.status='revisao'),'interrupted',count(*) filter (where r.status='interrompida'),
     'waiting',count(*) filter (where r.status in ('aguardando','processando')),
     'running',count(*) filter (where r.status='processando'),
     'pace_count',count(*) filter (where r.status not in ('aguardando','processando') and r.consultado_em between window_start and now()),
     'pace_first',min(r.consultado_em) filter (where r.status not in ('aguardando','processando') and r.consultado_em between window_start and now()),
     'pace_last',max(r.consultado_em) filter (where r.status not in ('aguardando','processando') and r.consultado_em between window_start and now()))
    from ranked r),
   'consultando',(select coalesce(jsonb_agg(jsonb_build_object('nome',r.nome,'cpf',r.cpf) order by r.posicao),'[]')
    from (select * from ranked where status='processando' order by posicao limit 3) r),
   'filtrados',(select count(*) from matched),
   'pagina',page,'tamanho',size,
   'linhas',(select coalesce(jsonb_agg(jsonb_build_object('posicao',r.posicao,'dados',jsonb_build_object(
     'id',r.id,'lote_id',r.lote_id,'nome',r.nome,'cpf',r.cpf,'telefone',r.telefone,'progress',r.progress,'stage',r.stage,
     'status',r.status,'created_at',r.created_at,'consultado_em',r.consultado_em,'attempts',r.attempts,'servico',r.servico,
     'queue_order',r.queue_order,'robot_slot',r.robot_slot,'convenio',r.convenio,'matricula',r.matricula,
     'tipo_servidor',r.tipo_servidor,'situacao_atual',r.situacao_atual,'emprestimo_disponivel',r.emprestimo_disponivel,
     'cartao_disponivel',r.cartao_disponivel,'tjba_status',r.tjba_status,'emprestimo_bruta',r.resultado_tjba->>'emprestimo_bruta',
     'cartao_bruta',r.resultado_tjba->>'cartao_bruta','motivo_situacao',r.resultado_tjba->>'motivo_situacao',
     'message',left(r.message,500))) order by r.posicao),'[]') from page_rows r))
  into result;
 end if;
 return result;
end $$;
revoke all on function public.painel_campanha(uuid,text,text,integer,integer) from public,anon;
grant execute on function public.painel_campanha(uuid,text,text,integer,integer) to authenticated;

commit;
