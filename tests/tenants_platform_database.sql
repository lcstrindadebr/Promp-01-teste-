-- Etapa 6a: a tela da equipe ApoiarCred grava na empresa; juntar parceiros leva os dados.
begin;
create temporary table tp as select gen_random_uuid() admin,gen_random_uuid() p1,gen_random_uuid() p2,gen_random_uuid() p3,gen_random_uuid() colega,
 null::uuid lot,null::uuid opp_contato,null::uuid opp_custom;
grant select,update on tp to authenticated,service_role;
insert into auth.users(id,aud,role,email)
 select x,'authenticated','authenticated',x::text||'@tenant-platform.invalid' from tp,unnest(array[admin,p1,p2,p3,colega]) x;
insert into apoiarcred_private.user_profiles(user_id,role,name,email) select admin,'admin','Equipe',admin::text||'@tenant-platform.invalid' from tp;

set local role service_role;
do $$
declare f tp; r jsonb; rules jsonb='[{"service":"digimais_saldo_parcela","enabled":true,"allow_individual":true,"allow_campaign":false,"daily_limit":0},{"service":"tjba_margem","enabled":true,"allow_individual":true,"allow_campaign":true,"daily_limit":0}]';
begin
 select * into f from tp;
 perform public.admin_partner_manage(f.admin,'create',jsonb_build_object('user_id',f.p1,'email','p1@x.invalid','name','Parceiro 1','active',true,
  'allow_integrations',true,'allow_amigoz',true,'shared_daily_limit',30,'permissions',rules));
 foreach r in array array[jsonb_build_object('u',f.p2,'n','Parceiro 2'),jsonb_build_object('u',f.p3,'n','Parceiro 3')] loop
  perform public.admin_partner_manage(f.admin,'create',jsonb_build_object('user_id',r->>'u','email',(r->>'n')||'@x.invalid','name',r->>'n','active',true,
   'shared_daily_limit',null,'permissions',rules));
 end loop;
 r:=(select x from jsonb_array_elements(public.admin_partner_manage(f.admin,'list')) x where x->>'user_id'=f.p1::text);
 if r is null or r->>'shared_daily_limit'<>'30' or not (r->>'allow_integrations')::boolean or not (r->>'allow_amigoz')::boolean
  or (r->>'members')::int<>1 then raise exception 'Platform list wrong: %',r;end if;
 if (r->'access'->'services'->0->>'allow_campaign')::boolean or not (r->'access'->'services'->1->>'allow_campaign')::boolean then
  raise exception 'Ceiling from the screen wrong: %',r->'access';end if;
 if exists(select 1 from jsonb_array_elements(public.admin_partner_manage(f.admin,'list')) x where x->>'user_id'=f.admin::text) then
  raise exception 'Platform team listed as a company';end if;
 -- Suspending the company blocks new consultations but keeps the history readable.
 perform public.admin_partner_manage(f.admin,'update',jsonb_build_object('user_id',f.p3,'name','Parceiro 3','active',false,'permissions',rules));
 if (apoiarcred_private.access_for(f.p3)->>'active')::boolean then raise exception 'Suspended company still active';end if;
 begin perform public.admin_partner_manage(f.p1,'list');raise exception 'Partner used the platform screen';
 exception when insufficient_privilege then null;end;
end $$;
reset role;

-- Parceiro 2 has a lot and two CRM cards: one in "contato", one in a custom stage.
insert into public.crm_cadastros(user_id,cpf,nome,ultima_atividade) select p2,'00000000191','CLIENTE P2',now() from tp;
set local role authenticated;
do $$
declare f tp; custom uuid; contato uuid; o1 uuid; o2 uuid; lot uuid=gen_random_uuid();
begin
 select * into f from tp;
 perform set_config('request.jwt.claim.sub',f.p2::text,true);
 insert into public.consulta_lotes(id,user_id,nome,tipo) values(lot,f.p2,'LOTE P2','individual');
 perform public.crm_listar_etapas();
 custom:=(public.crm_salvar_etapa(null,'{"nome":"Só do P2","posicao":15}')->>'id')::uuid;
 select id into contato from public.crm_etapas where codigo='contato';
 insert into public.crm_oportunidades(cpf,nome,produto) values('00000000191','CLIENTE P2','recompra') returning id into o1;
 insert into public.crm_oportunidades(cpf,nome,produto) values('00000000191','CLIENTE P2','saque') returning id into o2;
 perform public.crm_mover_etapa(o1,contato,(select etapa_id from public.crm_oportunidades where id=o1));
 perform public.crm_mover_etapa(o2,custom,(select etapa_id from public.crm_oportunidades where id=o2));
 update tp set lot=v.l,opp_contato=v.a,opp_custom=v.b from (select lot l,o1 a,o2 b) v;
 -- Only the platform team joins companies.
 begin perform public.admin_move_member(f.p2,f.p1,'gestor');raise exception 'Partner moved itself';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
delete from public.crm_movimentacoes where user_id=(select p2 from tp);

set local role authenticated;
do $$
declare f tp; r jsonb; target uuid;
begin
 select * into f from tp;
 perform set_config('request.jwt.claim.sub',f.admin::text,true);
 r:=public.admin_move_member(f.p2,f.p1,'gestor');
 target:=(r->>'tenant_id')::uuid;
 if (r->>'registros')::int<4 then raise exception 'Data not moved: %',r;end if;
end $$;
reset role;

do $$
declare f tp; target uuid; source uuid;
begin
 select * into f from tp;
 target:=apoiarcred_private.user_tenant(f.p1);
 select id into source from apoiarcred_private.tenants where legacy_owner_id=f.p2;
 if apoiarcred_private.user_tenant(f.p2)<>target then raise exception 'Member not moved';end if;
 if (select code from apoiarcred_private.tenant_roles r join apoiarcred_private.tenant_members m on m.role_id=r.id where m.user_id=f.p2)<>'gestor' then raise exception 'Role not applied';end if;
 if (select tenant_id from public.consulta_lotes where id=f.lot)<>target then raise exception 'Lot did not move';end if;
 if (select e.codigo from public.crm_oportunidades o join public.crm_etapas e on e.id=o.etapa_id where o.id=f.opp_contato)<>'contato'
  or (select e.tenant_id from public.crm_oportunidades o join public.crm_etapas e on e.id=o.etapa_id where o.id=f.opp_contato)<>target then
  raise exception 'Card did not keep its stage';end if;
 if not (select e.inicial from public.crm_oportunidades o join public.crm_etapas e on e.id=o.etapa_id where o.id=f.opp_custom) then
  raise exception 'Card from a custom stage did not go to the initial stage';end if;
 if exists(select 1 from public.crm_movimentacoes where oportunidade_id in (f.opp_contato,f.opp_custom)) then raise exception 'Move logged as card movement';end if;
 if (select active from apoiarcred_private.tenants where id=source) then raise exception 'Empty source company still active';end if;
end $$;

-- The target company's administrator now sees the moved data; the joined partner sees the company.
set local role authenticated;
do $$
declare f tp;
begin
 select * into f from tp;
 perform set_config('request.jwt.claim.sub',f.p1::text,true);
 if not exists(select 1 from public.consulta_lotes where id=f.lot) then raise exception 'Target admin does not see moved lot';end if;
 perform set_config('request.jwt.claim.sub',f.admin::text,true);
 -- A company with other active users cannot be moved by its owner alone.
 begin perform public.admin_move_member(f.p1,f.p3,'operador');raise exception 'Moved an owner with active colleagues';
 exception when invalid_parameter_value then null;end;
end $$;
reset role;
set local role service_role;
do $$
declare f tp;
begin
 select * into f from tp;
 if exists(select 1 from jsonb_array_elements(public.admin_partner_manage(f.admin,'list')) x where x->>'name'='Parceiro 2') then
  raise exception 'Empty company still listed';end if;
 if (select (x->>'members')::int from jsonb_array_elements(public.admin_partner_manage(f.admin,'list')) x where x->>'user_id'=f.p1::text)<>2 then
  raise exception 'Target company member count wrong';end if;
end $$;
reset role;
rollback;
