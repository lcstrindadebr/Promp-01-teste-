-- Execute after schema.sql or upgrade_amigoz_debt_cash.sql; no persistent changes.
begin;
do $$
declare cfg jsonb; rows jsonb; row jsonb; expected numeric[]=array[3923.94,3657.15,3418.82,3203.55,3026.19,2682.35];i integer;
begin
 select config into cfg from public.amigoz_model_versions order by id desc limit 1;
 -- User's reported regression: none of the six limits covers R$ 11,131.31.
 rows=apoiarcred_private.amigoz_coefficient_calculate(320.53,11131.31,cfg,'amigoz_23');
 if jsonb_array_length(rows)<>6 then raise exception 'Six rates must execute';end if;
 for row in select value from jsonb_array_elements(rows) loop
  if (row->>'troco')::numeric<>0 or row->>'situacao'<>'limite_insuficiente' or (row->>'saque_liberado')::boolean then raise exception 'Insufficient limit produced cash: %',row;end if;
 end loop;
 rows=apoiarcred_private.amigoz_coefficient_calculate(200,200,cfg,'amigoz_23');
 for i in 0..5 loop
  if (rows->i->>'troco')::numeric<>expected[i+1] then raise exception 'Residual calculation wrong for rate %',i;end if;
 end loop;
 -- At 3%, base 200 produces a R$ 5,998 limit. Equal debt is eligible without cash.
 row=apoiarcred_private.amigoz_coefficient_calculate(200,5998,cfg,'amigoz_23')->0;
 if row->>'situacao'<>'pre_aprovada_sem_troco' or (row->>'troco')::numeric<>0 then raise exception 'Equal debt';end if;
 row=apoiarcred_private.amigoz_coefficient_calculate(200,5598,cfg,'amigoz_23')->0;
 if (row->>'saque_bruto')::numeric<>280 or row->>'situacao'<>'pre_aprovada_sem_troco' or (row->>'troco')::numeric<>0 then raise exception 'Below minimum';end if;
 row=apoiarcred_private.amigoz_coefficient_calculate(200,5548,cfg,'amigoz_23')->0;
 if (row->>'saque_bruto')::numeric<>315 or row->>'situacao'<>'pre_aprovada_com_troco' then raise exception 'Minimum boundary';end if;
 row=apoiarcred_private.amigoz_coefficient_calculate(200,null,cfg,'amigoz_23')->0;
 if row->>'troco' is not null or row->>'situacao'<>'quitacao_pendente' then raise exception 'Missing debt';end if;
 row=apoiarcred_private.amigoz_coefficient_calculate(200,0,cfg,'amigoz_23')->0;
 if (row->>'troco')::numeric<>4059.30 then raise exception 'Zero debt';end if;
 row=apoiarcred_private.amigoz_coefficient_calculate(200,200,cfg,'amigoz_23','{"3":100}'::jsonb)->0;
 if (row->>'troco')::numeric<>3958.60 then raise exception 'Bank IOF precedence';end if;
end $$;
rollback;
