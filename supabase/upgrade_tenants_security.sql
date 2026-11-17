-- Segurança (Fase 4): alertas do Supabase e a permissão "importar bases de clientes".
-- 1. clientes.importar passa a valer: só quem tem a permissão importa (Administrador e Gestor por
--    padrão; o Operador e o Leitura não). A conferência é feita na entrada de cada importação, então
--    vale para o painel e para a API. A equipe ApoiarCred continua podendo importar.
-- 2. Funções sem search_path fixo apontadas pelo Supabase.

do $$
declare fn text; def text; body_at integer; begin_at integer; guard text:=
 E'\n if auth.uid() is null or not (apoiarcred_private.has_permission(auth.uid(),''clientes.importar'') or apoiarcred_private.is_admin(auth.uid())) then\n  raise insufficient_privilege using message=''Seu papel na empresa não permite importar bases de clientes.'';\n end if;';
begin
 foreach fn in array array['apoiarcred_private.crm_import_and_start(uuid,text,text,text[],jsonb)',
  'apoiarcred_private.crm_import_catalog_clients(text,text,text[],jsonb)',
  'apoiarcred_private.crm_import_clients(text,text,boolean,jsonb)',
  'public.crm_preview_import(text,text,text[],jsonb)'] loop
  def:=pg_get_functiondef(fn::regprocedure);
  if position('clientes.importar' in def)>0 then continue;end if;
  body_at:=position('$function$' in def);
  if body_at=0 then raise exception 'Corpo de % não encontrado',fn;end if;
  -- Primeiro "begin" do corpo (depois do declare): a conferência entra logo em seguida.
  begin_at:=body_at+(regexp_instr(substr(def,body_at),'\mbegin\M','1','1','0','i'))-1;
  if begin_at<=body_at then raise exception 'Início do corpo de % não encontrado',fn;end if;
  def:=substr(def,1,begin_at+4)||guard||substr(def,begin_at+5);
  execute def;
 end loop;
end $$;

alter function apoiarcred_private.today_sp() set search_path='';
alter function apoiarcred_private.consult_key(text,text) set search_path='';
