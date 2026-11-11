begin;
do $$
declare actor uuid:=gen_random_uuid(); h text:=encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'); r jsonb;
 ba jsonb:='{"uf":"BA","convenio":"saeb","clientes":[{"cpf":"000.000.008-92","numero_matricula":"000123","data_nascimento":"1985-04-23","margem_emprestimo":120.50,"margem_cartao":0}]}';
begin
 insert into auth.users(id,aud,role,email) values(actor,'authenticated','authenticated',actor::text||'@api-test.invalid');
 insert into apoiarcred_private.user_profiles(user_id,role,name,email) values(actor,'admin','Fixture',actor::text||'@api-test.invalid') on conflict(user_id) do update set role='admin';
 insert into apoiarcred_private.api_tokens(user_id,name,token_hash,prefix,scopes) values(actor,'Fixture',h,'apc_fixture',array['read','campanhas:write']);
 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claim.role','service_role',true);
 execute 'set local role service_role';
 r:=public.api_execute(h,'GET','/clientes/convenios','{"uf":"ba"}');
 if not (r->'body'->'data' @> '[{"id":"saeb","servicos":["consigx_margem"],"campos_opcionais":["margem_emprestimo","margem_cartao"]}]') then raise exception 'Catálogo BA: %',r; end if;
 r:=public.api_execute(h,'GET','/clientes/convenios','{"uf":"SP"}');
 if not (r->'body'->'data' @> '[{"id":"amigoz_23","requisitos_servicos":{"digimais_saldo":["cpf","nome","telefone"]}}]') then raise exception 'Catálogo SP: %',r; end if;
 r:=public.api_execute(h,'POST','/clientes/importacoes',ba,'ba-test');
 if (r->>'status')::int<>201 or (r#>>'{body,data,consultas}')::int<>0 then raise exception 'Import BA: %',r; end if;
 r:=public.api_execute(h,'POST','/clientes/importacoes',ba,'ba-test');
 if (r->>'replayed')::boolean is distinct from true then raise exception 'Replay: %',r; end if;
 r:=public.api_execute(h,'POST','/clientes/importacoes',ba||'{"servicos":["digimais_saldo"]}','ba-invalid');
 if (r->>'status')::int<>422 then raise exception 'Incompatibilidade SAEB: %',r; end if;
 r:=public.api_execute(h,'POST','/clientes/importacoes','{"uf":"SP","convenio":"amigoz_23","servicos":["digimais_saldo"],"clientes":[{"cpf":"00000000892","nome":"Pessoa Exemplo","telefone":"11900000000"}]}','sp-test');
 if (r->>'status')::int<>201 or (r#>>'{body,data,consultas}')::int<>1 then raise exception 'Import SP: %',r; end if;
 execute 'reset role';
 if not exists(select 1 from public.crm_dados_cliente where user_id=actor and convenio='saeb' and origem='importacao' and dados @> '{"margem_emprestimo":120.50,"margem_cartao":0}') then raise exception 'Margens não persistidas'; end if;
 if not exists(select 1 from public.crm_vinculos where user_id=actor and convenio='saeb' and matricula='000123') then raise exception 'Matrícula não persistida'; end if;
end $$;
rollback;
select 'BA, SP, importação, margens, matrícula e idempotência verificados' as teste;
