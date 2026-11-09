-- An interrupted consultation breaks the streak of consecutive errors or reviews.
create or replace function apoiarcred_private.track_campaign_failures() returns trigger
language plpgsql security definer set search_path='' as $$
declare failed boolean := new.status in ('erro','revisao');
begin
 if old.status<>'processando' or new.status in ('processando','aguardando') then return new;end if;
 if tg_table_name='consulta_jobs' then
  update public.consulta_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 else
  update public.tjba_lotes
  set failure_streak=case when failed then failure_streak+1 else 0 end,
      auto_paused=failed and failure_streak>=9,
      paused=failed and failure_streak>=9
  where id=new.lote_id and tipo='campanha' and not paused
    and (failed or failure_streak>0);
 end if;
 return new;
end $$;
