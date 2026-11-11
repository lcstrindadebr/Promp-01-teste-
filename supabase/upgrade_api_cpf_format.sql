-- Format CPF at the API boundary for both existing and new campaign rows.
create or replace function apoiarcred_private.api_format_cpf(row_data jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select case
  when jsonb_typeof(row_data->'cpf')='string' and row_data->>'cpf' ~ '^[0-9]{11}$' then
   jsonb_set(row_data,'{cpf}',to_jsonb(regexp_replace(
    row_data->>'cpf','^([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{2})$','\1.\2.\3-\4')))
  else row_data
 end;
$$;
revoke all on function apoiarcred_private.api_format_cpf(jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.api_format_cpf(jsonb) to service_role;

create or replace function apoiarcred_private.api_response(code integer,data jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare field text; formatted jsonb;
begin
 data=apoiarcred_private.api_format_cpf(data);
 foreach field in array array['data','accepted','duplicates'] loop
  if jsonb_typeof(data->field)='array' then
   select coalesce(jsonb_agg(apoiarcred_private.api_format_cpf(item) order by position),'[]'::jsonb)
   into formatted
   from jsonb_array_elements(data->field) with ordinality as entries(item,position);
   data=jsonb_set(data,array[field],formatted);
  end if;
 end loop;
 return jsonb_build_object('status',code,'body',data);
end;
$$;
