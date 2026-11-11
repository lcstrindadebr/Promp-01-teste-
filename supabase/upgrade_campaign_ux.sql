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
