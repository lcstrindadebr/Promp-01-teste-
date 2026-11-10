begin;

create table if not exists public.crm_catalogo_importacao (
  uf text not null,
  codigo text not null,
  nome text not null,
  servicos text[] not null,
  primary key (uf,codigo)
);
alter table public.crm_catalogo_importacao enable row level security;
revoke all on public.crm_catalogo_importacao from public,anon,authenticated;
grant select on public.crm_catalogo_importacao to authenticated;
drop policy if exists crm_catalogo_importacao_leitura on public.crm_catalogo_importacao;
create policy crm_catalogo_importacao_leitura on public.crm_catalogo_importacao
  for select to authenticated using (true);

-- IDs Amigoz de vps/amigoz_convenios.json e códigos ConsigX de vps/tjba.py.
insert into public.crm_catalogo_importacao (uf,codigo,nome,servicos) values
  ('BA','tjba','Tribunal de Justiça da Bahia (TJBA)',array['consigx_margem','digimais_saldo']),
  ('BA','saeb','Governo do Estado da Bahia (SAEB)',array['consigx_margem','digimais_saldo']),
  ('BA','dpeba','Defensoria Pública da Bahia (DPEBA)',array['consigx_margem','digimais_saldo']),
  ('BA','embasa','EMBASA',array['consigx_margem','digimais_saldo']),
  ('BA','suprev','Superintendência de Previdência (SUPREV)',array['consigx_margem','digimais_saldo']),
  ('AC','amigoz_138','Prefeitura de Rio Branco - AC',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AL','amigoz_105','Governo de Alagoas - AL',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AL','amigoz_133','TJAL - Tribunal de Justiça de Alagoas - AL',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AM','amigoz_131','AMAZONPREV-AM',array['amigoz_saque','digimais_saldo']),
  ('AM','amigoz_132','Governo Amazonas - AM',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('AM','amigoz_73','Manausprev - AM',array['amigoz_saque','digimais_saldo']),
  ('CE','amigoz_95','Governo do Ceará - CE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('CE','amigoz_30','Prefeitura de Juazeiro do Norte - CE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_56','Governo do Espírito Santo - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_159','IPAMV - Prev. Vitória - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_154','Prefeitura de Aracruz - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_143','Prefeitura de Linhares - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('ES','amigoz_115','Prefeitura de Serra - ES',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('GO','amigoz_15','Governo de Goias',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('GO','amigoz_97','Prefeitura de Caldas Novas - GO',array['amigoz_saque','digimais_saldo']),
  ('GO','amigoz_166','Prefeitura de Valparaíso de Goiás - GO',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MA','amigoz_39','Governo do Maranhão - MA',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MA','amigoz_100','Prefeitura de São Luís - MA',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_52','Bombeiros Militar - Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_53','Defensoria - Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_48','Governo de Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_50','IPSEMG - MG - Previdencia',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_49','IPSM - MG - Militares',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_146','JFPREV - Prev. Juiz de Fora - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_51','Policia Militar - Minas Gerais - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_96','Prefeitura de Betim - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_83','Prefeitura de Contagem - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_11','Prefeitura de Juiz de Fora - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_162','Prefeitura de Mariana - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_47','Prefeitura de Nova Lima - MG',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MG','amigoz_110','Prefeitura de Sabará - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_112','Prefeitura de Uberaba - MG',array['amigoz_saque','digimais_saldo']),
  ('MG','amigoz_4','Tribunal de Justiça de Minas Gerais',array['amigoz_saque','digimais_saldo']),
  ('MS','amigoz_81','IMPCG - Inst. Mun. de Prev. de Campo Grande – MS',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('MT','amigoz_12','Prefeitura de Sorriso - MT',array['amigoz_saque','digimais_saldo']),
  ('MT','amigoz_20','Prefeitura de Tangará da Serra - MT',array['amigoz_saque','digimais_saldo']),
  ('MT','amigoz_43','Previso - MT',array['amigoz_saque','digimais_saldo']),
  ('PA','amigoz_157','Prefeitura de Belém - Compra Cliente',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PA','amigoz_156','Prefeitura de Belém - PA',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PB','amigoz_46','Governo da Paraíba - PB',array['amigoz_saque','digimais_saldo']),
  ('PB','amigoz_67','IPSEM - Instituto de Previdência Campina de Grande - PB',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PB','amigoz_3','Prefeitura de Campina Grande - PB',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PB','amigoz_2','Prefeitura de João Pessoa - PB',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_139','Governo de Pernambuco - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_160','IPMC - Prev. Carpina - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_116','Prefeitura de Carpina - PE',array['amigoz_saque','digimais_saldo']),
  ('PE','amigoz_35','Prefeitura de Jaboatão dos Guararapes - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_40','Prefeitura de Olinda - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PE','amigoz_1','Prefeitura de Recife - PE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PI','amigoz_25','Governo de Piauí',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_93','Governo do Paraná - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_142','IPMC - Prev. Cascavel - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_34','MaringaPrev - PR',array['amigoz_saque','digimais_saldo']),
  ('PR','amigoz_106','Prefeitura de Cascavel - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_122','Prefeitura de Cascavel - PR - (SEMED e SESAU)',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_45','Prefeitura de Curitiba - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_32','Prefeitura de Maringa - PR',array['amigoz_saque','digimais_saldo']),
  ('PR','amigoz_152','Prefeitura de Medianeira - PR',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('PR','amigoz_102','Prefeitura de Ponta Grossa - PR',array['amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_141','Prefeitura de Macaé - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_76','Prefeitura de Nova Iguaçu - RJ',array['amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_163','Prefeitura de Saquarema - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_124','Prefeitura de São Pedro da Aldeia - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_126','PREVINI-RJ',array['amigoz_saque','digimais_saldo']),
  ('RJ','amigoz_167','SGPREVI - Prev. São Gonçalo - RJ',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_55','Prefeitura de Macaíba - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_151','Prefeitura de Mossoró - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_19','Prefeitura de Natal - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RN','amigoz_18','Prefeitura de Parnamirim - RN',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RO','amigoz_68','Governo de Rondônia - RO',array['amigoz_saque','digimais_saldo']),
  ('RO','amigoz_145','Prefeitura de Ariquemes - RO',array['amigoz_saque','digimais_saldo']),
  ('RO','amigoz_29','Prefeitura de Porto Velho - RO',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('RR','amigoz_104','IPER - Inst. de Prev. de Roraima - RR',array['amigoz_saque','digimais_saldo']),
  ('RR','amigoz_118','Prefeitura de Boa Vista - RR',array['amigoz_saque','digimais_saldo']),
  ('SC','amigoz_148','Prefeitura de Chapecó - SC',array['amigoz_saque','digimais_saldo']),
  ('SC','amigoz_58','Prefeitura de Navegantes - SC',array['amigoz_saque','digimais_saldo']),
  ('SE','amigoz_147','Prefeitura de Aracaju - SE',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_23','Governo de São Paulo',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_135','Governo de São Paulo - Lei 500',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_26','Governo de São Paulo - Secr. da Educação',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_70','IPMO - Inst. Prev. de Osasco - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_28','IPREM - SP - APOSENTADOS',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_27','IPREM - SP - PENSIONISTAS',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_129','IPREV -  Santos - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_99','IPSA - Inst. de Prev. de Santo André - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_33','Polícia Militar - São Paulo',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_54','Prefeitura Campinas - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_140','Prefeitura de Araraquara - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_92','Prefeitura de Campinas – SP – Celetistas',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_127','Prefeitura de Ferraz de Vasconcelos - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_144','Prefeitura de Guarulhos - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_137','Prefeitura de Ilhabela - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_155','Prefeitura de Itapeva - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_158','Prefeitura de Jundiaí - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_130','Prefeitura de Mauá - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_123','Prefeitura de Praia Grande - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_85','Prefeitura de Ribeirão Preto -SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_74','Prefeitura de Santo André - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_61','Prefeitura de Santos -SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_66','Prefeitura de Sorocaba - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_41','Prefeitura de Suzano - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_164','Prefeitura de São Bernardo do Campo - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_134','Prefeitura de São José do Rio Preto - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_108','Prefeitura de São José dos Campos - SP',array['amigoz_saque','digimais_saldo']),
  ('SP','amigoz_17','Prefeitura de São Paulo - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_165','Prefeitura de Taboão da Serra - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_31','SPPREV - São Paulo - SP',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('SP','amigoz_168','TJSP - Tribunal de Justiça de São Paulo',array['amigoz_margem','amigoz_saque','digimais_saldo']),
  ('TO','amigoz_60','Prefeitura de Araguaína - TO',array['amigoz_margem','amigoz_saque','digimais_saldo'])
on conflict (uf,codigo) do update set nome=excluded.nome,servicos=excluded.servicos;

alter table public.crm_classificacoes add column if not exists servicos_planejados text[];
update public.crm_classificacoes
set servicos_planejados=case when usar_digimais then array['digimais_saldo']::text[] else '{}'::text[] end
where servicos_planejados is null;
alter table public.crm_classificacoes alter column servicos_planejados set default '{}'::text[];
alter table public.crm_classificacoes alter column servicos_planejados set not null;

create or replace function apoiarcred_private.crm_import_catalog_clients(
  p_uf text, p_convenio text, p_servicos text[], p_rows jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
  allowed text[];
  imported integer;
begin
  select servicos into allowed from public.crm_catalogo_importacao
  where uf=p_uf and codigo=p_convenio;
  if allowed is null then raise exception 'Escolha um convênio cadastrado para o estado.'; end if;
  if p_servicos is null or array_position(p_servicos,null) is not null
    or not (p_servicos <@ allowed) then
    raise exception 'Há consultas incompatíveis com o convênio selecionado.';
  end if;
  imported := apoiarcred_private.crm_import_clients(
    p_uf,p_convenio,'digimais_saldo'=any(p_servicos),p_rows
  );
  update public.crm_classificacoes c set servicos_planejados=(
    select array(select distinct s from unnest(p_servicos) as t(s) order by s)
  )
  where c.user_id=auth.uid() and c.uf=p_uf and c.convenio=p_convenio
    and exists (select 1 from jsonb_to_recordset(p_rows) as r(cpf text) where r.cpf=c.cpf);
  return imported;
end $$;
revoke all on function apoiarcred_private.crm_import_catalog_clients(text,text,text[],jsonb) from public,anon,authenticated;
grant execute on function apoiarcred_private.crm_import_catalog_clients(text,text,text[],jsonb) to authenticated;

create or replace function public.crm_import_catalog_clients(
  p_uf text, p_convenio text, p_servicos text[], p_rows jsonb
) returns integer language sql security invoker set search_path='' as $$
  select apoiarcred_private.crm_import_catalog_clients(p_uf,p_convenio,p_servicos,p_rows);
$$;
revoke all on function public.crm_import_catalog_clients(text,text,text[],jsonb) from public,anon,authenticated;
grant execute on function public.crm_import_catalog_clients(text,text,text[],jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
