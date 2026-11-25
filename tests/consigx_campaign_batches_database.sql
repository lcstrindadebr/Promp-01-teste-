-- Campanha ConsigX enviada em partes: nasce pausada, não duplica parte repetida, só libera com o total
-- confirmado, guarda o convênio e recusa campanha de outro usuário.
begin;
create temporary table cb as select gen_random_uuid() owner,gen_random_uuid() other,gen_random_uuid() camp;
grant select on cb to authenticated;
insert into auth.users(id,aud,role,email) select u,'authenticated','authenticated',u::text||'@cb.invalid' from cb,unnest(array[owner,other]) u;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select u,'admin','CB',u::text||'@cb.invalid' from cb,unnest(array[owner,other]) u;

set local role authenticated;
do $$
declare f cb; part1 jsonb; part2 jsonb; n integer; lot public.tjba_lotes;
begin
 select * into f from cb;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 select jsonb_agg(jsonb_build_object('cpf',lpad(g::text,11,'0'))) into part1 from generate_series(1,250) g;
 select jsonb_agg(jsonb_build_object('cpf',lpad(g::text,11,'0'),'nome','Nome '||g)) into part2 from generate_series(251,300) g;
 n:=public.save_consigx_campaign_batch(f.camp,'Gov BA','saeb',300,part1);
 if n<>250 then raise exception 'First part saved %',n;end if;
 select * into lot from public.tjba_lotes where id=f.camp;
 if not lot.paused or lot.convenio<>'saeb' then raise exception 'Campaign must start paused in SAEB: %',to_jsonb(lot);end if;
 -- Resending a part (connection dropped after the save) does not duplicate.
 n:=public.save_consigx_campaign_batch(f.camp,'Gov BA','saeb',300,part1);
 if n<>250 then raise exception 'Repeated part duplicated: %',n;end if;
 -- Closing before every client arrived is refused.
 begin perform public.save_consigx_campaign_batch(f.camp,'Gov BA','saeb',300,'[]');raise exception 'Early close accepted';
 exception when raise_exception then if sqlerrm not like '%ainda não recebeu%' then raise;end if;end;
 n:=public.save_consigx_campaign_batch(f.camp,'Gov BA','saeb',300,part2);
 if n<>300 then raise exception 'Second part saved %',n;end if;
 n:=public.save_consigx_campaign_batch(f.camp,'Gov BA','saeb',300,'[]');
 if (select paused from public.tjba_lotes where id=f.camp) then raise exception 'Final call must release the campaign';end if;
 if exists(select 1 from public.tjba_jobs where lote_id=f.camp and (convenio<>'saeb' or status<>'aguardando')) then raise exception 'Jobs wrong';end if;
 if (select nome from public.tjba_jobs where lote_id=f.camp and cpf='00000000001')<>'CPF 00000000001' then raise exception 'Name fallback wrong';end if;
 -- Duplicated CPF inside a part, more than 250 per part, unknown agreement.
 begin perform public.save_consigx_campaign_batch(gen_random_uuid(),'X','saeb',2,'[{"cpf":"00000000001"},{"cpf":"00000000001"}]');raise exception 'Duplicate accepted';
 exception when raise_exception then if sqlerrm not like '%duplicados%' then raise;end if;end;
 begin perform public.save_consigx_campaign_batch(gen_random_uuid(),'X','saeb',300,part1||'[{"cpf":"99999999999"}]');raise exception 'Oversized part accepted';
 exception when invalid_parameter_value then null;end;
 begin perform public.save_consigx_campaign_batch(gen_random_uuid(),'X','inss',1,'[{"cpf":"00000000001"}]');raise exception 'Unknown agreement accepted';
 exception when invalid_parameter_value then null;end;
 -- Another user cannot add to this campaign.
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 begin perform public.save_consigx_campaign_batch(f.camp,'Gov BA','saeb',300,'[{"cpf":"00000000999"}]');raise exception 'Other user accepted';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
