-- Multi-tenant: pausar, retomar e repetir falhas de campanhas da empresa.
-- Antes só quem criou a campanha podia. Agora pode quem vê a campanha (quem criou, ou Gestor e
-- Administrador da empresa) e tem permissão de campanha daquele serviço. O papel Leitura só vê.
-- Quem criou sempre pode pausar (parar é seguro, mesmo com a conta suspensa).
-- As consultas continuam no nome de quem criou a campanha, e a cota é a da empresa.

create function apoiarcred_private.campaign_actor_ok(p_tenant uuid,p_owner uuid,p_service text)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and apoiarcred_private.can_see(p_tenant,p_owner)
  and (apoiarcred_private.is_admin(auth.uid())
   or apoiarcred_private.has_permission(auth.uid(),apoiarcred_private.consult_key(p_service,'campanha')));
$$;
revoke all on function apoiarcred_private.campaign_actor_ok(uuid,uuid,text) from public,anon,authenticated;

create or replace function apoiarcred_private.set_campaign_paused(p_campaign_id uuid,p_service text,p_paused boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or p_paused is null then raise insufficient_privilege;end if;
 if p_service='digimais_saldo_parcela' then
  update public.consulta_lotes set paused=p_paused where id=p_campaign_id and tipo='campanha'
   and ((p_paused and user_id=auth.uid()) or apoiarcred_private.campaign_actor_ok(tenant_id,user_id,p_service));
 elsif p_service='tjba_margem' then
  update public.tjba_lotes set paused=p_paused where id=p_campaign_id and tipo='campanha'
   and ((p_paused and user_id=auth.uid()) or apoiarcred_private.campaign_actor_ok(tenant_id,user_id,p_service));
 else raise exception 'Serviço inválido.';end if;
 if not found then raise insufficient_privilege using message='Campanha não encontrada ou sem permissão para alterá-la.';end if;
end $$;

create or replace function apoiarcred_private.retry_consulta_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare retried integer;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if not exists(select 1 from public.consulta_lotes where id=p_campaign_id and tipo='campanha'
  and apoiarcred_private.campaign_actor_ok(tenant_id,user_id,'digimais_saldo_parcela')) then
  raise insufficient_privilege using message='Campanha não disponível para esta conta.';end if;
 update public.consulta_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,
  saldo_liquidacao=null,total_parcelas=null,valor_parcela=null,resultado_saldo=null,resultado_parcela=null,consultado_em=null,locked_at=null
 where lote_id=p_campaign_id and status in ('erro','revisao','interrompida');
 get diagnostics retried=row_count;
 return retried;
end $$;

create or replace function apoiarcred_private.retry_tjba_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if auth.uid() is null or not exists(select 1 from public.tjba_lotes where id=p_campaign_id and tipo='campanha'
  and apoiarcred_private.campaign_actor_ok(tenant_id,user_id,'tjba_margem')) then
  raise insufficient_privilege using message='Campanha não disponível para esta conta.';end if;
 update public.tjba_jobs set status='aguardando',progress=0,stage='Aguardando na fila',message=null,consultado_em=null,locked_at=null,
  matricula=null,tipo_servidor=null,situacao_atual=null,emprestimo_disponivel=null,cartao_disponivel=null,tjba_status=null,resultado_tjba=null
 where lote_id=p_campaign_id and status in ('erro','revisao');
 get diagnostics n=row_count;
 return n;
end $$;
