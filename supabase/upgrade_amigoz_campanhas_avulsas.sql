begin;
alter table public.crm_import_requests add column if not exists nome_campanha_amigoz text;
create or replace function public.crm_criar_campanha_amigoz(p_id uuid,p_uf text,p_convenio text,p_servicos text[],p_rows jsonb,p_arquivo text,p_nome text)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='45s' as $$
declare resultado jsonb; nome_salvo text;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 or p_servicos is null
  or cardinality(p_servicos)=0 or not p_servicos <@ array['amigoz_margem','amigoz_saque'] then
  raise exception 'Informe o nome e selecione margem ou saque Amigoz.';
 end if;
 resultado:=public.crm_confirm_import(p_id,p_uf,p_convenio,p_servicos,p_rows,p_arquivo);
 update public.crm_import_requests set nome_campanha_amigoz=btrim(p_nome)
 where user_id=auth.uid() and request_id=p_id and nome_campanha_amigoz is null;
 select nome_campanha_amigoz into nome_salvo from public.crm_import_requests where user_id=auth.uid() and request_id=p_id;
 if nome_salvo is distinct from btrim(p_nome) then raise exception 'A confirmação já foi usada com outro nome.';end if;
 return resultado;
end $$;
create or replace function public.crm_listar_campanhas_amigoz()
returns jsonb language sql stable security definer set search_path='' as $$
 with filas as (
  select import_id,min(created_at) criado,count(*) leads,
   count(*) filter(where status in ('aguardando','processando')) pendentes,
   count(*) filter(where status='concluida') concluidas,
   count(*) filter(where status in ('erro','revisao')) atencao
  from public.amigoz_jobs where user_id=auth.uid() group by import_id
 )
 select coalesce(jsonb_agg(to_jsonb(x) order by x.criado desc,x.id),'[]') from (
  select f.import_id id,coalesce(c.nome,i.nome_campanha_amigoz,i.arquivo,'Consulta Amigoz') nome,
   f.criado,f.leads,f.pendentes,f.concluidas,f.atencao
  from filas f
  left join public.crm_campanhas_reuso c on c.id=f.import_id and c.user_id=auth.uid()
  left join public.crm_import_requests i on i.request_id=f.import_id and i.user_id=auth.uid()
  where c.id is not null or i.request_id is not null
  order by f.criado desc,f.import_id limit 50
 ) x;
$$;
revoke all on function public.crm_criar_campanha_amigoz(uuid,text,text,text[],jsonb,text,text),public.crm_listar_campanhas_amigoz() from public,anon;
grant execute on function public.crm_criar_campanha_amigoz(uuid,text,text,text[],jsonb,text,text),public.crm_listar_campanhas_amigoz() to authenticated;
notify pgrst,'reload schema';
commit;