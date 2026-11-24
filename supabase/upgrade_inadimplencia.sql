-- Inadimplência no lugar de "Já vendeu".
-- Quando o Digi+ responde que o contrato está com uma assessoria de cobrança, o cliente não vendeu a dívida:
-- está inadimplente. A consulta passa a ser "Inadimplência jurídica" (escritório ou setor jurídico) ou
-- "Inadimplência administrativa" (assessoria de cobrança comum), com o nome e o telefone da assessoria.
-- 'ja_vendeu' continua aceito para compatibilidade com integrações antigas, mas deixa de ser gravado.

begin;

alter table public.consulta_jobs drop constraint consulta_jobs_status_check;
alter table public.consulta_jobs add constraint consulta_jobs_status_check check(status in ('aguardando','processando',
 'concluida','nao_localizado','nao_cliente','erro','revisao','interrompida','ja_vendeu',
 'inadimplencia_administrativa','inadimplencia_juridica'));

-- Mesma regra do robô da API (vps/digimais_api.py, collection_agency/collection_result).
create function apoiarcred_private.inadimplencia_classificar(p_texto text)
returns table(status text,assessoria text,telefone text) language plpgsql immutable set search_path='' as $$
declare tail text; nome text; fone text;
begin
 tail:=substring(coalesce(p_texto,'') from '(?i)assessoria de cobran[cç]a\s*,?\s*\**\s*(.*)$');
 nome:=split_part(coalesce(tail,''),'**',1);
 nome:=regexp_replace(nome,'\.\s+(assim|para|o banco)\M.*$','','i');
 nome:=btrim(regexp_replace(nome,'[\s.\-]+$',''));
 fone:=substring(nome from '(\(?[0-9]{2}\)?\s*[0-9]{4,5}-?[0-9]{4}|0800[ 0-9]{7,})');
 if fone is not null then
  nome:=btrim(regexp_replace(replace(nome,fone,''),'[\s.\-]+$',''));fone:=btrim(fone);
 end if;
 status:=case when nome ~* '(jur[ií]dic|advog|advocacia|\madv\M)' then 'inadimplencia_juridica' else 'inadimplencia_administrativa' end;
 assessoria:=nullif(nome,'');telefone:=fone;
 return next;
end $$;
revoke all on function apoiarcred_private.inadimplencia_classificar(text) from public,anon,authenticated;

-- Reclassifica as consultas já gravadas como "Já vendeu", pelas mensagens já salvas.
-- Sem disparar webhooks: é uma correção de rótulo, não um resultado novo para as integrações.
alter table public.consulta_jobs disable trigger capture_webhook;
with source as (
 select j.id,(select string_agg(x,' ') from jsonb_array_elements_text(
   coalesce(j.resultado_saldo->'todasMensagens','[]')||coalesce(j.resultado_parcela->'todasMensagens','[]')||
   coalesce(j.api_handoff->'resultado_saldo'->'todasMensagens','[]')||coalesce(j.api_handoff->'resultado_parcela'->'todasMensagens','[]')) x)
   ||' '||coalesce(j.message,'') texto
 from public.consulta_jobs j where j.status='ja_vendeu'
), classified as (
 select s.id,c.* from source s cross join lateral apoiarcred_private.inadimplencia_classificar(s.texto) c
)
update public.consulta_jobs j set status=c.status,
 stage=case c.status when 'inadimplencia_juridica' then 'Inadimplência jurídica' else 'Inadimplência administrativa' end,
 message=case when c.assessoria is not null then 'Assessoria: '||c.assessoria||coalesce(' · '||c.telefone,'')
  else 'Contrato em assessoria de cobrança (assessoria não informada).' end
from classified c where c.id=j.id;
alter table public.consulta_jobs enable trigger capture_webhook;

-- Painel: números da campanha, filtro e logs passam a conhecer as duas situações.
do $$
declare def text; n integer;
begin
 def:=pg_get_functiondef('public.painel_campanha(uuid,text,text,integer,integer)'::regprocedure);
 if position('inad_adm' in def)=0 then
  n:=(length(def)-length(replace(def,'''sold'',count(*) filter (where r.status=''ja_vendeu''),','')))/length('''sold'',count(*) filter (where r.status=''ja_vendeu''),');
  if n<>2 then raise exception 'Contagem "sold" de painel_campanha não encontrada (%)',n;end if;
  def:=replace(def,'''sold'',count(*) filter (where r.status=''ja_vendeu''),',
   '''sold'',count(*) filter (where r.status=''ja_vendeu''),''inad_adm'',count(*) filter (where r.status=''inadimplencia_administrativa''),''inad_jur'',count(*) filter (where r.status=''inadimplencia_juridica''),');
  if position('when ''Revisão'' then array[''revisao'']' in def)=0 then raise exception 'Filtro de painel_campanha não encontrado';end if;
  def:=replace(def,'when ''Revisão'' then array[''revisao'']',
   'when ''Revisão'' then array[''revisao''] when ''inadimplencia'' then array[''inadimplencia_administrativa'',''inadimplencia_juridica''] when ''Inadimplência administrativa'' then array[''inadimplencia_administrativa''] when ''Inadimplência jurídica'' then array[''inadimplencia_juridica'']');
  execute def;
 end if;
 def:=pg_get_functiondef('public.painel_log_consultas(text,text,integer)'::regprocedure);
 if position('inadimplencia_juridica' in def)=0 then
  if position('''ja_vendeu'',' in def)=0 then raise exception 'Lista de encerradas de painel_log_consultas não encontrada';end if;
  def:=replace(def,'''ja_vendeu'',','''ja_vendeu'',''inadimplencia_administrativa'',''inadimplencia_juridica'',');
  execute def;
 end if;
end $$;

commit;
