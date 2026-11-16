-- A conferência consulta os dados existentes sem gravar cadastros ou filas.
create or replace function public.crm_preview_import(
 p_uf text,p_convenio text,p_servicos text[],p_rows jsonb
) returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='45s'
as $function$
declare
 uid uuid:=auth.uid();
 account_access jsonb;
 profile apoiarcred_private.user_profiles;
 errors jsonb;
 clients integer;
 existing_clients integer;
 consultations integer:=0;
 shared_consultations integer:=0;
 used_today integer;
 today date:=(now() at time zone 'America/Sao_Paulo')::date;
 service_id text;
 allowed boolean;
begin
 if uid is null then raise insufficient_privilege;end if;
 account_access:=apoiarcred_private.access_for(uid);
 if not coalesce((account_access->>'active')::boolean,false)
    or coalesce((account_access->>'trial_expired')::boolean,false) then
  raise insufficient_privilege using message='Importação indisponível para esta conta.';
 end if;

 errors:=apoiarcred_private.crm_import_errors(p_uf,p_convenio,p_servicos,p_rows);
 if errors<>'[]' then return jsonb_build_object('valido',false,'erros',errors);end if;

 select count(*),count(c.cpf) into clients,existing_clients
 from (select distinct item->>'cpf' as cpf from jsonb_array_elements(p_rows) item) imported
 left join public.crm_cadastros c on c.user_id=uid and c.cpf=imported.cpf;

 select * into profile from apoiarcred_private.user_profiles where user_id=uid;
 for service_id in
  select service from (values ('digimais_saldo','digimais_saldo_parcela'),
                              ('consigx_margem','tjba_margem')) s(option_name,service)
  where option_name=any(p_servicos)
 loop
  consultations:=consultations+clients;
  if profile.role='admin' then continue;end if;
  select enabled and allow_campaign into allowed
  from apoiarcred_private.partner_permissions where user_id=uid and service=service_id;
  if not coalesce(allowed,false) then
   raise insufficient_privilege using message='Campanhas não estão habilitadas para este tipo de higienização.';
  end if;
  if profile.shared_quota then shared_consultations:=shared_consultations+clients;end if;
 end loop;

 if p_servicos && array['amigoz_margem','amigoz_saque'] then
  consultations:=consultations+jsonb_array_length(p_rows);
  if profile.role<>'admin' then
   if not coalesce(profile.allow_amigoz and profile.shared_quota,false) then
    raise insufficient_privilege using message='Acesso Amigoz não liberado.';
   end if;
   shared_consultations:=shared_consultations+jsonb_array_length(p_rows);
  end if;
 end if;

 if shared_consultations>0 and profile.shared_daily_limit is not null then
  select used into used_today from apoiarcred_private.partner_daily_usage
  where user_id=uid and service='shared' and day=today;
  if coalesce(used_today,0)+shared_consultations>profile.shared_daily_limit then
   raise sqlstate 'PT429' using message='A planilha excede o saldo de consultas da cota diária compartilhada.';
  end if;
 end if;

 return jsonb_build_object('valido',true,'uf',p_uf,'convenio',p_convenio,
  'registros',jsonb_array_length(p_rows),'clientes',clients,
  'clientes_novos',clients-existing_clients,'clientes_atualizados',existing_clients,
  'consultas',consultations);
exception when raise_exception or insufficient_privilege or sqlstate 'PT429' then
 return jsonb_build_object('valido',false,'erros',
  jsonb_build_array(jsonb_build_object('linha',0,'mensagem',sqlerrm)));
end
$function$;
