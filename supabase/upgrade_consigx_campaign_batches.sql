-- Campanhas ConsigX grandes em partes, como as do Digi+ (save_digimais_campaign_batch).
-- create_consigx_campaign grava a planilha inteira num só comando; cada linha passa pelas regras da
-- tabela (cota, convênio, webhooks, CRM, painel), cerca de 4,5 ms por linha. Com 8.770 CPFs isso dá
-- ~40 s e passa do limite de 8 s por comando do painel ("canceling statement due to statement timeout").
-- Agora o painel envia partes de até 250 CPFs. A campanha nasce pausada, recebe as partes (repetir uma
-- parte não duplica) e só é liberada para os robôs quando a última chamada, sem itens, confirma o total.

begin;

-- Um CPF por campanha; também acelera a conferência de "já recebido" a cada parte.
create unique index if not exists tjba_jobs_lote_cpf_unique on public.tjba_jobs(lote_id,cpf);

create or replace function public.save_consigx_campaign_batch(p_id uuid,p_nome text,p_convenio text,p_total integer,p_items jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); campaign public.tjba_lotes; saved integer;
begin
 if actor is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_id is null or p_total is null or p_total not between 1 and 20000
  or coalesce(length(btrim(p_nome)),0) not between 1 and 160
  or p_convenio is null or p_convenio not in ('tjba','dpeba','embasa','saeb','suprev')
  or jsonb_typeof(p_items) is distinct from 'array' then raise invalid_parameter_value;end if;
 if jsonb_array_length(p_items)>250 then raise invalid_parameter_value;end if;
 if exists(select 1 from jsonb_array_elements(p_items) x(item) group by x.item->>'cpf' having count(*)>1) then
  raise exception 'Há CPFs duplicados.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into campaign from public.tjba_lotes where id=p_id for update;
 if not found then
  if jsonb_array_length(p_items)=0 then raise invalid_parameter_value;end if;
  insert into public.tjba_lotes(id,user_id,nome,tipo,convenio,paused)
  values(p_id,actor,btrim(p_nome),'campanha',p_convenio,true) returning * into campaign;
 end if;
 if campaign.user_id<>actor or campaign.tipo<>'campanha' or campaign.convenio<>p_convenio
  or campaign.nome<>btrim(p_nome) then raise insufficient_privilege;end if;
 -- Depois de liberada, a campanha não recebe mais partes.
 if jsonb_array_length(p_items)>0 and campaign.paused then
  insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone)
  select p_id,actor,coalesce(nullif(btrim(x.item->>'nome'),''),'CPF '||(x.item->>'cpf')),x.item->>'cpf',coalesce(x.item->>'telefone','')
  from jsonb_array_elements(p_items) with ordinality x(item,position)
  where not exists(select 1 from public.tjba_jobs j where j.lote_id=p_id and j.cpf=x.item->>'cpf')
  order by x.position;
 end if;
 select count(*) into saved from public.tjba_jobs where lote_id=p_id and user_id=actor;
 if saved>p_total then raise invalid_parameter_value;end if;
 if jsonb_array_length(p_items)=0 then
  if saved<>p_total then raise exception 'A campanha ainda não recebeu todos os clientes.';end if;
  if campaign.paused then update public.tjba_lotes set paused=false where id=p_id;end if;
 end if;
 return saved;
end $$;
revoke all on function public.save_consigx_campaign_batch(uuid,text,text,integer,jsonb) from public,anon;
grant execute on function public.save_consigx_campaign_batch(uuid,text,text,integer,jsonb) to authenticated;

commit;
