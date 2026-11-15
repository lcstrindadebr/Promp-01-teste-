create or replace function public.save_digimais_campaign_batch(
 p_id uuid,p_nome text,p_total integer,p_items jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); campaign public.consulta_lotes; saved integer;
begin
 if actor is null then raise insufficient_privilege;end if;
 if p_id is null or p_total is null or p_total not between 1 and 11000
  or coalesce(length(btrim(p_nome)),0) not between 1 and 160
  or jsonb_typeof(p_items) is distinct from 'array' then raise invalid_parameter_value;end if;
 if jsonb_array_length(p_items)>100 then raise invalid_parameter_value;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into campaign from public.consulta_lotes where id=p_id for update;
 if not found then
  if jsonb_array_length(p_items)=0 then raise invalid_parameter_value;end if;
  insert into public.consulta_lotes(id,user_id,nome,tipo,paused)
  values(p_id,actor,btrim(p_nome),'campanha',true) returning * into campaign;
 end if;
 if campaign.user_id<>actor or campaign.tipo<>'campanha'
  or campaign.servico<>'digimais_saldo_parcela' or campaign.nome<>btrim(p_nome) then raise insufficient_privilege;end if;
 if jsonb_array_length(p_items)>0 and campaign.paused then
  insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone)
  select p_id,actor,x.item->>'nome',x.item->>'cpf',x.item->>'telefone'
  from jsonb_array_elements(p_items) with ordinality x(item,position)
  where not exists(select 1 from public.consulta_jobs j where j.lote_id=p_id and j.cpf=x.item->>'cpf')
  order by x.position;
 end if;
 select count(*) into saved from public.consulta_jobs where lote_id=p_id and user_id=actor;
 if saved>p_total then raise invalid_parameter_value;end if;
 if jsonb_array_length(p_items)=0 then
  if saved<>p_total then raise exception 'A campanha ainda não recebeu todos os leads.';end if;
  if campaign.paused then update public.consulta_lotes set paused=false where id=p_id;end if;
 end if;
 return saved;
end $$;
revoke all on function public.save_digimais_campaign_batch(uuid,text,integer,jsonb) from public,anon;
grant execute on function public.save_digimais_campaign_batch(uuid,text,integer,jsonb) to authenticated;
