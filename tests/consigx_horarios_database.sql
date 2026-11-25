-- Horário dos convênios ConsigX: fora do horário o robô não reserva, e a fila agendada não aparece como parada.
begin;
do $$
begin
 -- 19:59 e 20:00 em Brasília (UTC-3): SAEB fecha às 20:00, SUPREV às 22:00; TJBA não tem horário.
 if not apoiarcred_private.consigx_aberto('saeb','2026-11-25 22:59:00+00') then raise exception 'SAEB should be open at 19:59';end if;
 if apoiarcred_private.consigx_aberto('saeb','2026-11-25 23:00:00+00') then raise exception 'SAEB should close at 20:00';end if;
 if not apoiarcred_private.consigx_aberto('suprev','2026-11-26 00:59:00+00') then raise exception 'SUPREV should be open at 21:59';end if;
 if apoiarcred_private.consigx_aberto('suprev','2026-11-26 01:00:00+00') then raise exception 'SUPREV should close at 22:00';end if;
 if apoiarcred_private.consigx_aberto('saeb','2026-11-26 09:59:00+00') then raise exception 'SAEB should be closed at 06:59';end if;
 if not apoiarcred_private.consigx_aberto('saeb','2026-11-26 10:00:00+00') then raise exception 'SAEB should open at 07:00';end if;
 if not apoiarcred_private.consigx_aberto('tjba','2026-11-26 06:00:00+00') then raise exception 'TJBA has no hours';end if;
end $$;

create temporary table ch as select gen_random_uuid() owner;
grant select on ch to authenticated;
insert into auth.users(id,aud,role,email) select owner,'authenticated','authenticated',owner::text||'@ch.invalid' from ch;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select owner,'admin','P',owner::text||'@ch.invalid' from ch;
set local role authenticated;
do $$
declare f ch; lot uuid;
begin
 select * into f from ch;
 perform set_config('request.jwt.claim.sub',f.owner::text,true);
 perform public.manage_consigx_access(1,'empresa','senha-do-not-use',true);
 lot:=public.create_consigx_campaign('SAEB','[{"cpf":"00000000191"}]','saeb');
end $$;
reset role;
do $$
declare got int;
begin
 update public.consigx_horarios set abre='00:00',fecha='00:00:01' where convenio='saeb';
 select count(*) into got from public.claim_tjba_job_for_robot(1);
 if got<>0 then raise exception 'Closed SAEB was claimed';end if;
 update public.consigx_horarios set abre='00:00',fecha='23:59:59.999' where convenio='saeb';
 select count(*) into got from public.claim_tjba_job_for_robot(1);
 if got<>1 then raise exception 'Open SAEB was not claimed: %',got;end if;
end $$;
-- The queue health ignores waiting jobs of a closed agreement.
do $$
declare d text;
begin
 d:=pg_get_functiondef('public.admin_queue_health()'::regprocedure);
 if (length(d)-length(replace(d,'consigx_aberto','')))/length('consigx_aberto')<>2 then raise exception 'Queue health not patched';end if;
end $$;
rollback;
