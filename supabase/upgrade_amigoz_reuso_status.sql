CREATE OR REPLACE FUNCTION public.crm_status_reuso(p_origem uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') from (
  select c.id,c.nome,c.created_at,c.resposta,
   (select count(*) from public.amigoz_jobs j where j.user_id=c.user_id and j.import_id=c.id and j.status in ('aguardando','processando')) pendentes,
   (select count(*) from public.amigoz_jobs j where j.user_id=c.user_id and j.import_id=c.id and j.status='concluida') concluidas,
   (select coalesce(j.resultado->'margem'->>'http_status',j.resultado->'saque'->>'http_status') from public.amigoz_jobs j where j.user_id=c.user_id and j.import_id=c.id and j.status in ('erro','revisao') order by j.consultado_em desc nulls last limit 1) ultimo_http,
   (select count(*) from public.amigoz_jobs j where j.user_id=c.user_id and j.import_id=c.id and j.status in ('erro','revisao')) atencao
  from public.crm_campanhas_reuso c where c.user_id=auth.uid() and c.origem=p_origem
  order by c.created_at desc limit 20
 ) x;
$function$;
