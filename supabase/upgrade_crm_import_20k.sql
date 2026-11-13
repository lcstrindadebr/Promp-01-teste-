begin;
CREATE OR REPLACE FUNCTION public.create_consigx_campaign(p_nome text, p_items jsonb, p_convenio text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>20000 then raise exception 'Envie até 20.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo,convenio) values(btrim(p_nome),'campanha',p_convenio) returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.item->>'nome'),''),'CPF '||(x.item->>'cpf')),x.item->>'cpf',coalesce(x.item->>'telefone','') from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return cid;
end $function$;
CREATE OR REPLACE FUNCTION public.create_consulta_campaign(p_nome text, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare campaign_id uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.'; end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe um nome de campanha com até 160 caracteres.'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.'; end if;
 if jsonb_array_length(p_items)=0 then raise exception 'Envie pelo menos um cliente.'; end if;
 if jsonb_array_length(p_items)>20000 then raise exception 'Envie até 20.000 clientes por planilha.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados na campanha.'; end if;
 insert into public.consulta_lotes(nome,tipo) values(btrim(p_nome),'campanha') returning id into campaign_id;
 insert into public.consulta_jobs(lote_id,user_id,nome,cpf,telefone)
 select campaign_id,auth.uid(),x.item->>'nome',x.item->>'cpf',x.item->>'telefone' from jsonb_array_elements(p_items) with ordinality x(item,position) order by x.position;
 return campaign_id;
end $function$;
CREATE OR REPLACE FUNCTION apoiarcred_private.crm_import_clients(p_uf text, p_convenio text, p_usar_digimais boolean, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  owner_id uuid := auth.uid();
  account_access jsonb;
  state_code text := upper(btrim(p_uf));
  agreement text := lower(regexp_replace(btrim(p_convenio), '[[:space:]]+', ' ', 'g'));
begin
  account_access := apoiarcred_private.access_for(owner_id);
  if owner_id is null or not coalesce((account_access->>'active')::boolean, false)
      or coalesce((account_access->>'trial_expired')::boolean, false) then
    raise exception 'Importação indisponível para esta conta.' using errcode='42501';
  end if;
  if state_code is null or state_code not in
      ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')
      or agreement is null or length(agreement) not between 1 and 120 or p_usar_digimais is null then
    raise exception 'Informe estado, convênio e a preferência de uso do Digi+.';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Envie uma lista de clientes.';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 20000 then
    raise exception 'Envie entre 1 e 20.000 clientes por arquivo.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_rows) as r(cpf text, nome text, telefone text)
    where cpf is null or cpf !~ '^[0-9]{11}$' or cpf='00000000000'
       or length(btrim(nome)) > 160 or coalesce(telefone,'') !~ '^([0-9]{10,13})?$'
  ) then raise exception 'A lista contém CPF, nome ou telefone inválido.'; end if;
  if exists (select 1 from jsonb_to_recordset(p_rows) as r(cpf text) group by cpf having count(*)>1) then
    raise exception 'A lista contém CPFs repetidos.';
  end if;

  insert into public.crm_cadastros as c
    (user_id, cpf, nome, telefone, nome_atualizado_em, telefone_atualizado_em, ultima_atividade)
  select owner_id, r.cpf, nullif(btrim(r.nome),''), nullif(r.telefone,''),
         case when nullif(btrim(r.nome),'') is not null then now() end,
         case when nullif(r.telefone,'') is not null then now() end, now()
  from jsonb_to_recordset(p_rows) as r(cpf text, nome text, telefone text)
  order by r.cpf
  on conflict (user_id, cpf) do update set
    nome=coalesce(excluded.nome,c.nome),
    telefone=coalesce(excluded.telefone,c.telefone),
    nome_atualizado_em=coalesce(excluded.nome_atualizado_em,c.nome_atualizado_em),
    telefone_atualizado_em=coalesce(excluded.telefone_atualizado_em,c.telefone_atualizado_em),
    ultima_atividade=greatest(c.ultima_atividade,excluded.ultima_atividade);

  insert into public.crm_classificacoes (user_id, cpf, uf, convenio, usar_digimais)
  select owner_id, r.cpf, state_code, agreement, p_usar_digimais
  from jsonb_to_recordset(p_rows) as r(cpf text)
  order by r.cpf
  on conflict (user_id, cpf, uf, convenio) do update set
    usar_digimais=excluded.usar_digimais, importado_em=excluded.importado_em;
  return jsonb_array_length(p_rows);
end $function$;
CREATE OR REPLACE FUNCTION apoiarcred_private.crm_import_errors(p_uf text, p_convenio text, p_servicos text[], p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare errors jsonb:='[]'; row jsonb; idx bigint; field record; message text; fields text[]; services text[];
begin
 select servicos into services from public.crm_catalogo_importacao where uf=p_uf and codigo=p_convenio;
 if services is null or p_servicos is null or array_position(p_servicos,null) is not null or not p_servicos<@services then
  return '[{"linha":0,"mensagem":"Convênio ou consultas incompatíveis."}]';end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then return '[{"linha":0,"mensagem":"Envie uma lista de clientes."}]';end if;
 if jsonb_array_length(p_rows) not between 1 and 20000 then return '[{"linha":0,"mensagem":"Envie de 1 a 20.000 registros."}]';end if;
 for row,idx in select value,ordinality from jsonb_array_elements(p_rows) with ordinality loop
  message:=null;
  begin
   if jsonb_typeof(row)<>'object' then raise exception 'Registro deve ser um objeto.';end if;
   if jsonb_typeof(row->'cpf') is distinct from 'string' or coalesce(row->>'cpf','')!~'^[0-9]{11}$' or row->>'cpf'='00000000000' then raise exception 'CPF inválido.';end if;
   if length(row->>'nome')>160 or coalesce(row->>'telefone','')!~'^([0-9]{10,13})?$' then raise exception 'Nome ou telefone inválido.';end if;
   if 'digimais_saldo'=any(p_servicos) and (nullif(btrim(row->>'nome'),'') is null or nullif(row->>'telefone','') is null) then raise exception 'Digi+ exige nome e telefone com DDD.';end if;
   if length(row->>'numero_matricula')>256 or length(row->>'instituicao')>80 then raise exception 'Matrícula ou instituição excede o limite.';end if;
   if row->>'data_nascimento' is not null then
    if row->>'data_nascimento' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Nascimento deve usar AAAA-MM-DD.';end if;
    perform (row->>'data_nascimento')::date;
   end if;
   if row->>'data_dados' is not null then
    if row->>'data_dados' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}(T.*(Z|[+-][0-9]{2}:[0-9]{2}))?$'
      or (row->>'data_dados')::timestamptz>now() then raise exception 'Data dos dados inválida ou futura.';end if;
   end if;
   for field in select * from jsonb_each(row) where value<>'null'::jsonb loop
    if field.key in ('margem_livre','margem_emprestimo','margem_cartao','margem_beneficio','margem_consignado','saque_amigoz_valor') then
     if jsonb_typeof(field.value)<>'number' then raise exception 'O campo % deve ser numérico.',field.key;end if;
     if abs(field.value::text::numeric)>999999999999.99 then raise exception 'Valor fora do limite em %.',field.key;end if;
     if field.key like 'margem_%' and not services && array['amigoz_margem','consigx_margem'] then raise exception 'Margem indisponível neste convênio.';end if;
    elsif field.key in ('nome','telefone','numero_matricula','instituicao','data_dados','data_nascimento') and jsonb_typeof(field.value)<>'string' then
     raise exception 'O campo % deve ser texto.',field.key;
    end if;
   end loop;
   if row->'saque_amigoz_elegivel' is not null and row->'saque_amigoz_elegivel'<>'null'::jsonb
    and jsonb_typeof(row->'saque_amigoz_elegivel')<>'boolean' then raise exception 'Elegibilidade Amigoz deve ser booleana.';end if;
   if (row->>'saque_amigoz_valor')::numeric<0 or (row->>'saque_amigoz_elegivel'='false' and (row->>'saque_amigoz_valor')::numeric>0) then raise exception 'Saque Amigoz incompatível.';end if;
   if (row->>'saque_amigoz_valor' is not null or row->>'saque_amigoz_elegivel' is not null) and not 'amigoz_saque'=any(services) then raise exception 'Saque Amigoz indisponível neste convênio.';end if;
  exception when others then message:=sqlerrm;end;
  if message is not null then errors:=errors||jsonb_build_array(jsonb_build_object('linha',idx+1,'mensagem',message));end if;
 end loop;
 select errors||coalesce(jsonb_agg(jsonb_build_object('linha',ord+1,'mensagem','CPF, matrícula e instituição repetidos.')),'[]')
 into errors from (
  select ord,row_number() over(partition by x->>'cpf',coalesce(x->>'numero_matricula',''),coalesce(nullif(x->>'instituicao',''),'informada') order by ord) n
  from jsonb_array_elements(p_rows) with ordinality r(x,ord)
 ) d where n>1;
 return errors;
end $function$;
notify pgrst,'reload schema';
commit;
