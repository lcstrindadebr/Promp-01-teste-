begin;
do $$
declare fixture uuid := gen_random_uuid();
begin
  if not exists (select 1 from public.crm_catalogo_importacao where uf='BA' and codigo='tjba')
    or not exists (select 1 from public.crm_catalogo_importacao where uf='BA' and codigo='saeb')
    or not exists (select 1 from public.crm_catalogo_importacao where uf='SP' and codigo='amigoz_33'
      and array['amigoz_saque','amigoz_margem','digimais_saldo'] <@ servicos)
  then raise exception 'Catálogo incompleto'; end if;
  insert into auth.users(id,aud,role,email) values(fixture,'authenticated','authenticated',fixture||'@crm-test.invalid');
  insert into apoiarcred_private.user_profiles(user_id,role,name,email) values(fixture,'admin','Teste',fixture||'@crm-test.invalid');
  perform set_config('request.jwt.claim.sub',fixture::text,true);
end $$;
set local role authenticated;
do $$
declare records jsonb := '[{"cpf":"00000000101"}]';
begin
  if public.crm_import_catalog_clients('SP','amigoz_33',array['amigoz_margem','amigoz_saque'],records) <> 1
  then raise exception 'Importação falhou'; end if;
  if not exists (select 1 from public.crm_classificacoes where convenio='amigoz_33'
    and servicos_planejados=array['amigoz_margem','amigoz_saque'] and not usar_digimais)
    or exists (select 1 from public.consulta_lotes)
    or exists (select 1 from public.tjba_lotes)
  then raise exception 'Preferências ou efeitos na fila incorretos'; end if;
  begin
    perform public.crm_import_catalog_clients('BA','amigoz_33',array['amigoz_saque'],records);
    raise exception 'Convênio de outro estado aceito';
  exception when raise_exception then
    if sqlerrm <> 'Escolha um convênio cadastrado para o estado.' then raise; end if;
  end;
  begin
    perform public.crm_import_catalog_clients('BA','tjba',array['amigoz_saque'],records);
    raise exception 'Serviço incompatível aceito';
  exception when raise_exception then
    if sqlerrm <> 'Há consultas incompatíveis com o convênio selecionado.' then raise; end if;
  end;
end $$;
reset role;
select 'PASS: convênios BA e SP, preferências independentes, validação e ausência de filas' as resultado;
rollback;
