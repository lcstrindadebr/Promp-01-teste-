begin;
create function public.crm_listar_exportacao(p_uf text,p_convenio text,p_tipos text[],p_etapa text,p_after uuid default null,p_reexportar boolean default false)
returns setof public.crm_opportunity_cards language sql stable security invoker set search_path='' as $$
 select o.* from public.crm_opportunity_cards o
 where o.user_id=auth.uid()
 and exists(select 1 from public.crm_etapas e where e.user_id=o.user_id and e.id=o.etapa_id and not e.arquivada and case when p_reexportar then (e.destino_exportacao or e.codigo='exportada') else e.tipo='aberta' and not e.destino_exportacao and e.codigo<>'exportada' end)
 and (p_etapa='' or o.etapa=p_etapa)
 and o.produto=any(p_tipos)
 and (p_after is null or o.id>p_after)
 and ((p_uf='' and p_convenio='') or exists(
  select 1 from public.crm_classificacao_filtros v
  where v.user_id=o.user_id and v.cpf=o.cpf
   and (p_uf='' or v.uf=p_uf) and (p_convenio='' or v.convenio=p_convenio)
   and (o.convenio='' or v.convenio=o.convenio)
   and (not exists(select 1 from jsonb_object_keys(o.sinais_consulta) k where k<>'digimais')
        or exists(select 1 from jsonb_object_keys(o.sinais_consulta) k
           where regexp_replace(k,'^(amigoz_(margem|saque)|consigx_margem|margem_importada)_','')=v.convenio))
 ))
 order by o.id limit 500
$$;
revoke all on function public.crm_listar_exportacao(text,text,text[],text,uuid,boolean) from public,anon;
grant execute on function public.crm_listar_exportacao(text,text,text[],text,uuid,boolean) to authenticated;

create function public.crm_convenios_exportacao(p_cpfs text[]) returns table(cpf text,convenios jsonb)
language sql stable security invoker set search_path='' as $$
 select c.cpf,coalesce(jsonb_agg(jsonb_build_object('codigo',x.codigo,'nome',coalesce(a.nome,x.codigo),'uf',x.uf)
  order by x.codigo,x.uf) filter(where x.codigo is not null),'[]')
 from public.crm_cadastros c
 left join lateral (
  select v.convenio as codigo,v.uf from public.crm_classificacoes v where v.user_id=c.user_id and v.cpf=c.cpf
  union select v.convenio,v.uf from public.crm_vinculos v where v.user_id=c.user_id and v.cpf=c.cpf
  union select m.convenio,coalesce(k.uf,'') from public.crm_margens_vinculo m
   left join public.crm_catalogo_importacao k on k.codigo=m.convenio
   where m.user_id=c.user_id and m.cpf=c.cpf
 ) x on true
 left join public.crm_catalogo_importacao a on a.codigo=x.codigo and a.uf=x.uf
 where c.user_id=auth.uid() and c.cpf=any(p_cpfs)
 group by c.cpf
$$;
revoke all on function public.crm_convenios_exportacao(text[]) from public,anon;
grant execute on function public.crm_convenios_exportacao(text[]) to authenticated;

create or replace function public.amigoz_exportar_estimativas(p_items jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare item jsonb; result jsonb='[]'; output jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege;end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100 then raise exception 'Envie até 100 clientes por lote';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  begin
   output=public.amigoz_simular_coeficientes(item||jsonb_build_object('mode','auto','use_saved',true),false);
   if jsonb_array_length(output->'tabelas')=0 and output->>'motivo' like 'Simulação salva desatualizada%' then
    output=public.amigoz_simular_coeficientes(item||jsonb_build_object('mode','auto','use_saved',false),false);
   end if;
  exception when others then
   output=jsonb_build_object('tabelas','[]'::jsonb,'motivo','Dados indisponíveis ou incompatíveis para simular.');
  end;
  result=result||jsonb_build_array(output);
 end loop;
 return result;
end $$;

create function public.crm_selecionar_etapa(p_etapa_id uuid,p_produto text,p_convenio text,p_responsavel text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'etapa_id',o.etapa_id,'etapa',o.etapa) order by o.id),'[]')
 from public.crm_oportunidades o
  where o.user_id=auth.uid() and o.etapa_id=p_etapa_id
  and (p_produto='' or o.produto=p_produto)
  and (p_responsavel='' or position(lower(p_responsavel) in lower(coalesce(o.responsavel,'')))>0)
  and (p_convenio='' or o.convenio=p_convenio or (o.convenio='' and exists(
   select 1 from public.crm_classificacao_filtros v where v.user_id=o.user_id and v.cpf=o.cpf and v.convenio=p_convenio
   and (not exists(select 1 from jsonb_object_keys(o.sinais_consulta) k where k<>'digimais')
    or exists(select 1 from jsonb_object_keys(o.sinais_consulta) k
     where regexp_replace(k,'^(amigoz_(margem|saque)|consigx_margem|margem_importada)_','')=v.convenio))
  )))
$$;
revoke all on function public.crm_selecionar_etapa(uuid,text,text,text) from public,anon;
grant execute on function public.crm_selecionar_etapa(uuid,text,text,text) to authenticated;

alter table public.crm_exportacoes alter column oportunidade_referencia drop not null;
alter table public.crm_exportacoes drop constraint crm_exportacoes_oportunidade_referencia_fkey;
alter table public.crm_exportacoes add constraint crm_exportacoes_oportunidade_referencia_fkey
 foreign key(oportunidade_referencia) references public.crm_oportunidades(id) on delete set null;

create function public.crm_acao_lote(p_itens jsonb,p_destino uuid default null,p_excluir boolean default false)
returns integer language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); total integer; validos integer; afetados integer;
begin
 if uid is null or not coalesce((apoiarcred_private.access_for(uid)->>'active')::boolean,false) then raise insufficient_privilege;end if;
 if (p_destino is null and not p_excluir) or (p_destino is not null and p_excluir)
  or jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens)<1 then
  raise exception using errcode='22023',message='Selecione as oportunidades e uma ação.';
 end if;
 total=jsonb_array_length(p_itens);
 select count(*) into validos from (
  select o.id from public.crm_oportunidades o join jsonb_to_recordset(p_itens) i(id uuid,etapa_id uuid)
   on i.id=o.id and i.etapa_id=o.etapa_id
   where o.user_id=uid order by o.id for update of o
 ) locked;
 if validos<>total or (select count(distinct x->>'id') from jsonb_array_elements(p_itens) x)<>total then
  raise exception using errcode='PT409',message='A seleção mudou. Atualize o quadro e selecione os cartões novamente.';
 end if;
 if p_excluir then
  delete from public.crm_oportunidades o using jsonb_to_recordset(p_itens) i(id uuid)
   where o.user_id=uid and o.id=i.id;
 else
  if not exists(select 1 from public.crm_etapas where user_id=uid and id=p_destino and not arquivada) then
   raise exception using errcode='22023',message='Etapa de destino indisponível.';
  end if;
  update public.crm_oportunidades o set etapa_id=p_destino from jsonb_to_recordset(p_itens) i(id uuid)
   where o.user_id=uid and o.id=i.id and o.etapa_id<>p_destino;
 end if;
 get diagnostics afetados=row_count;
 return afetados;
end $$;
revoke all on function public.crm_acao_lote(jsonb,uuid,boolean) from public,anon,authenticated;
grant execute on function public.crm_acao_lote(jsonb,uuid,boolean) to authenticated;
notify pgrst,'reload schema';

commit;
