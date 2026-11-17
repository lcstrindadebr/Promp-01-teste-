-- Etapa 3b: funil do CRM compartilhado pela empresa; ações conforme o papel; nada vaza entre empresas.
begin;
create temporary table tc as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() other,null::uuid opp;
grant select,update on tc to authenticated;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-crm.invalid' from tc,unnest(array[a,b,c,other]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
 select a,'partner','Empresa A',a::text||'@tenant-crm.invalid' from tc
 union all select other,'partner','Empresa B',other::text||'@tenant-crm.invalid' from tc;
insert into apoiarcred_private.tenant_members(tenant_id,user_id,role_id)
 select m.tenant_id,x.id,r.id from tc join apoiarcred_private.tenant_members m on m.user_id=tc.a
 cross join lateral (values(tc.b,'gestor'),(tc.c,'operador')) x(id,code)
 join apoiarcred_private.tenant_roles r on r.tenant_id=m.tenant_id and r.code=x.code;
insert into public.crm_cadastros(user_id,cpf,nome,ultima_atividade)
 select c,'00000000191','CRM TENANT C',now() from tc union all select other,'00000000191','CRM TENANT B',now() from tc;

set local role authenticated;
do $$
declare f tc; stages_a uuid[]; stages_c uuid[]; stage uuid; opp uuid; board jsonb;
begin
 select * into f from tc;
 -- One funnel per company, whoever opens it first.
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 select array_agg(id order by posicao) into stages_c from public.crm_listar_etapas();
 perform set_config('request.jwt.claim.sub',f.a::text,true);
 select array_agg(id order by posicao) into stages_a from public.crm_listar_etapas();
 if stages_a is distinct from stages_c or cardinality(stages_a)<>7 then raise exception 'Company funnel not shared';end if;
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 if exists(select 1 from public.crm_listar_etapas() where id=any(stages_a)) then raise exception 'Funnel leaked across companies';end if;
 -- Only funil.configurar edits stages (Gestor yes, Operador no).
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 begin perform public.crm_salvar_etapa(null,'{"nome":"Operador stage"}');raise exception 'Operador edited the funnel';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 stage:=(public.crm_salvar_etapa(null,'{"nome":"Retorno","posicao":35}')->>'id')::uuid;
 -- The Operador's card lands in the company funnel; the Gestor sees it on the board.
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 insert into public.crm_oportunidades(cpf,nome,produto) values('00000000191','CRM TENANT C','recompra') returning id into opp;
 update tc set opp=crm_tenant_card.v from (select opp v) crm_tenant_card;
 if (select etapa_id from public.crm_oportunidades where id=opp)<>stages_a[1] then raise exception 'Card not in the company initial stage';end if;
 if (public.crm_mover_etapa(opp,stage,stages_a[1])->>'etapa_id')::uuid<>stage then raise exception 'Operador could not move own card';end if;
 begin perform public.crm_acao_lote(jsonb_build_array(jsonb_build_object('id',opp,'etapa_id',stage)),null,true);
  raise exception 'Operador deleted cards';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',f.b::text,true);
 board:=public.crm_kanban();
 if not exists(select 1 from jsonb_array_elements(board) e,jsonb_array_elements(e->'cartoes') card where card->>'id'=opp::text)
  then raise exception 'Gestor does not see the company card';end if;
 if (public.crm_mover_etapa(opp,stages_a[1],stage)->>'etapa_id')::uuid<>stages_a[1] then raise exception 'Gestor could not move company card';end if;
 -- Company B neither sees nor moves it.
 perform set_config('request.jwt.claim.sub',f.other::text,true);
 if public.crm_mover_etapa(opp,stage,stages_a[1]) is not null then raise exception 'Other company moved the card';end if;
 if exists(select 1 from jsonb_array_elements(public.crm_kanban()) e,jsonb_array_elements(e->'cartoes') card where card->>'id'=opp::text)
  then raise exception 'Other company sees the card';end if;
 -- Card settings belong to the company: the administrator saves, everyone reads, the Operador cannot change.
 perform set_config('request.jwt.claim.sub',f.a::text,true);
 insert into public.crm_card_settings(visible,fields) values(array['cpf'],'[]');
 perform set_config('request.jwt.claim.sub',f.c::text,true);
 if (select count(*) from public.crm_card_settings)<>1 then raise exception 'Operador does not read company settings';end if;
 update public.crm_card_settings set visible=array['cpf','produto'];
 if (select visible from public.crm_card_settings)<>array['cpf'] then raise exception 'Operador changed company settings';end if;
end $$;
reset role;
rollback;
