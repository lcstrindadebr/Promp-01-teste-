begin;
create temp table crm_fixture_users as
select gen_random_uuid() as id, role from (values ('admin'),('partner')) as fixture(role);
insert into auth.users(id,aud,role,email)
select id,'authenticated','authenticated',id||'@crm-test.invalid' from crm_fixture_users;
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
select id,role,'Fixture',id||'@crm-test.invalid' from crm_fixture_users;
grant select on crm_fixture_users to authenticated;

select set_config('request.jwt.claim.sub',(select id::text from crm_fixture_users where role='partner'),true);
set local role authenticated;
do $$
begin
  if public.crm_import_clients('SP','PM SP',true,'[{"cpf":"00000000101","nome":"Outro titular"}]') <> 1 then
    raise exception 'Importação do parceiro falhou';
  end if;
  begin
    perform public.crm_reset_account('ZERAR MINHA CONTA');
    raise exception 'Parceiro conseguiu zerar a conta';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select set_config('request.jwt.claim.sub',(select id::text from crm_fixture_users where role='admin'),true);
set local role authenticated;
do $$
begin
  perform public.crm_import_clients('BA','TJBA',true,'[{"cpf":"00000000101","nome":"Titular","telefone":"75999999999"}]');
  perform public.crm_import_clients('BA','TJBA',false,'[{"cpf":"00000000101"}]');
  if (select count(*) from public.crm_filter_clients('','BA','tjba')) <> 1
    or not exists (select 1 from public.crm_cadastros where cpf='00000000101' and nome='Titular' and telefone='75999999999')
    or not exists (select 1 from public.crm_classificacoes where cpf='00000000101' and not usar_digimais)
    or exists (select 1 from public.crm_classificacoes where uf='SP')
    or exists (select 1 from public.consulta_lotes)
    or exists (select 1 from public.tjba_lotes)
    or exists (select 1 from public.crm_vinculos)
  then raise exception 'Importação incorreta ou com efeitos na fila'; end if;
  begin
    perform public.crm_reset_account('CANCELAR');
    raise exception 'Confirmação incorreta aceita';
  exception when raise_exception then
    if sqlerrm <> 'Digite ZERAR MINHA CONTA para confirmar.' then raise; end if;
  end;
  perform public.create_consulta_campaign('Fixture reset','[{"cpf":"00000000101","nome":"Titular","telefone":"75999999999"}]');
  insert into public.crm_oportunidades(cpf,nome,produto) values('00000000101','Fixture','recompra');
end $$;
reset role;
update public.consulta_jobs set status='processando'
where user_id=(select id from crm_fixture_users where role='admin');

set local role authenticated;
do $$
begin
  begin
    perform public.crm_reset_account('ZERAR MINHA CONTA');
    raise exception 'Reset aceito com consulta em andamento';
  exception when raise_exception then
    if sqlerrm not like 'Aguarde as consultas%' then raise; end if;
  end;
end $$;
reset role;
update public.consulta_jobs set status='aguardando'
where user_id=(select id from crm_fixture_users where role='admin');

set local role authenticated;
do $$
declare result jsonb;
begin
  result := public.crm_reset_account('ZERAR MINHA CONTA');
  if result->>'clientes' <> '1' or result->>'consultas' <> '1' or result->>'oportunidades' <> '1'
    or exists (select 1 from public.crm_cadastros) or exists (select 1 from public.crm_classificacoes)
    or exists (select 1 from public.consulta_lotes) or exists (select 1 from public.crm_oportunidades)
  then raise exception 'Reset incompleto: %', result; end if;
end $$;
reset role;
do $$
begin
  if not exists (
    select 1 from public.crm_cadastros
    where user_id=(select id from crm_fixture_users where role='partner') and nome='Outro titular'
  ) or (select count(*) from apoiarcred_private.user_profiles
         where user_id in (select id from crm_fixture_users)) <> 2
  then raise exception 'O reset afetou outra conta ou removeu o perfil'; end if;
end $$;
select 'PASS: importação isolada, filtros, reset admin, confirmação, bloqueio de tarefas ativas, isolamento' as resultado;
rollback;
