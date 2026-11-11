alter table public.tjba_lotes add column convenio text not null default 'tjba' check(convenio in ('tjba','dpeba','embasa','saeb','suprev'));
alter table public.tjba_jobs add column convenio text not null default 'tjba' check(convenio in ('tjba','dpeba','embasa','saeb','suprev'));
create function apoiarcred_private.assign_consigx_convenio() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 select l.convenio into new.convenio from public.tjba_lotes l where l.id=new.lote_id and l.user_id=new.user_id;
 if new.convenio is null then raise exception 'Campanha ou proprietário inválido.';end if;
 return new;
end $$;
revoke all on function apoiarcred_private.assign_consigx_convenio() from public,anon,authenticated,service_role;
create trigger assign_consigx_convenio before insert on public.tjba_jobs for each row execute function apoiarcred_private.assign_consigx_convenio();
create function public.create_consigx_campaign(p_nome text,p_items jsonb,p_convenio text) returns uuid language plpgsql security invoker set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='Entre na sua conta.';end if;
 if p_nome is null or length(btrim(p_nome)) not between 1 and 160 then raise exception 'Informe o nome da campanha.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Envie uma lista de clientes.';end if;
 if jsonb_array_length(p_items) not between 1 and 1000 then raise exception 'Envie de 1 a 1.000 clientes.';end if;
 if exists(select 1 from jsonb_to_recordset(p_items) x(cpf text) group by cpf having count(*)>1) then raise exception 'Há CPFs duplicados.';end if;
 insert into public.tjba_lotes(nome,tipo,convenio) values(btrim(p_nome),'campanha',p_convenio) returning id into cid;
 insert into public.tjba_jobs(lote_id,user_id,nome,cpf,telefone) select cid,auth.uid(),coalesce(nullif(btrim(x.nome),''),'CPF '||x.cpf),x.cpf,coalesce(x.telefone,'') from jsonb_to_recordset(p_items) x(nome text,cpf text,telefone text);
 return cid;
end $$;
revoke all on function public.create_consigx_campaign(text,jsonb,text) from public,anon;
grant execute on function public.create_consigx_campaign(text,jsonb,text) to authenticated;
