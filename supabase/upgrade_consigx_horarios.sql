-- Horário de atendimento dos convênios ConsigX (horário de Brasília).
-- SAEB: 07:00 às 20:00. SUPREV: 07:00 às 22:00. Convênio sem linha aqui atende a qualquer hora.
-- Fora do horário o robô não reserva consultas do convênio: campanhas e consultas individuais ficam
-- agendadas na fila e voltam sozinhas na abertura. O "Pausar" manual da campanha não é alterado.
-- A consulta que já estiver em andamento no fechamento termina normalmente.
-- Mesmos horários em dist/tjba.js (consigxHorarios), para o painel mostrar "Fora do horário".

begin;

create table public.consigx_horarios(
 convenio text primary key check(convenio in ('tjba','dpeba','embasa','saeb','suprev')),
 abre time not null,
 fecha time not null,
 check(abre<fecha)
);
alter table public.consigx_horarios enable row level security;
create policy consigx_horarios_leitura on public.consigx_horarios for select to authenticated using(true);
grant select on public.consigx_horarios to authenticated;
insert into public.consigx_horarios(convenio,abre,fecha) values('saeb','07:00','20:00'),('suprev','07:00','22:00');

create function apoiarcred_private.consigx_aberto(p_convenio text,p_em timestamptz default clock_timestamp())
returns boolean language sql stable set search_path='' as $$
 select coalesce((select (p_em at time zone 'America/Sao_Paulo')::time>=h.abre and (p_em at time zone 'America/Sao_Paulo')::time<h.fecha
  from public.consigx_horarios h where h.convenio=p_convenio),true);
$$;
revoke all on function apoiarcred_private.consigx_aberto(text,timestamptz) from public,anon,authenticated;

do $$
declare def text;
begin
 -- Robô: só reserva consultas de convênio aberto.
 def:=pg_get_functiondef('apoiarcred_private.claim_consigx_for_robot(integer)'::regprocedure);
 if position('consigx_aberto' in def)=0 then
  if (length(def)-length(replace(def,E' where not l.paused\n','')))/length(E' where not l.paused\n')<>1 then
   raise exception 'Filtro de campanha pausada de claim_consigx_for_robot não encontrado';end if;
  def:=replace(def,E' where not l.paused\n',E' where not l.paused and apoiarcred_private.consigx_aberto(l.convenio)\n');
  execute def;
 end if;
 -- Saúde da fila: consulta agendada fora do horário não conta como fila parada.
 def:=pg_get_functiondef('public.admin_queue_health()'::regprocedure);
 if position('consigx_aberto' in def)=0 then
  if (length(def)-length(replace(def,'from public.tjba_jobs j join public.tjba_lotes l on l.id=j.lote_id
     where j.status=''aguardando'' and not l.paused','')))/length('from public.tjba_jobs j join public.tjba_lotes l on l.id=j.lote_id
     where j.status=''aguardando'' and not l.paused')<>2 then raise exception 'Fila ConsigX de admin_queue_health não encontrada';end if;
  def:=replace(def,'from public.tjba_jobs j join public.tjba_lotes l on l.id=j.lote_id
     where j.status=''aguardando'' and not l.paused','from public.tjba_jobs j join public.tjba_lotes l on l.id=j.lote_id
     where j.status=''aguardando'' and not l.paused and apoiarcred_private.consigx_aberto(l.convenio)');
  execute def;
 end if;
end $$;

commit;
