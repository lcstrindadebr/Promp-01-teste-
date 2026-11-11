begin;
create function public.start_amigoz_individual(p_actor uuid,p_cpf text,p_convenio text,p_uf text,p_modo text,p_matricula text default null)
returns public.amigoz_jobs language plpgsql security invoker set search_path='' as $$
declare job public.amigoz_jobs;
begin
 if p_cpf is null or p_cpf!~'^[0-9]{11}$' or p_modo is null or p_modo not in ('saque','margem','ambos') then raise exception 'Consulta inválida';end if;
 if not exists(select 1 from public.crm_catalogo_importacao where codigo=p_convenio and uf=p_uf) and p_uf<>'BR' then raise exception 'Convênio inválido';end if;
 perform public.authorize_amigoz(p_actor,true);
 insert into public.crm_cadastros(user_id,cpf,ultima_atividade) values(p_actor,p_cpf,now())
 on conflict(user_id,cpf) do update set ultima_atividade=excluded.ultima_atividade;
 insert into public.amigoz_jobs(user_id,cpf,convenio,uf,modo,numero_matricula,import_id,status,lease,locked_at,message)
 values(p_actor,p_cpf,p_convenio,p_uf,p_modo,nullif(p_matricula,''),gen_random_uuid(),'processando',gen_random_uuid(),now(),'Consultando…') returning * into job;
 return job;
end $$;
revoke all on function public.start_amigoz_individual(uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.start_amigoz_individual(uuid,text,text,text,text,text) to service_role;
notify pgrst,'reload schema';
commit;
