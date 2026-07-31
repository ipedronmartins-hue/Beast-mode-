-- BEAST MODE — Migração 003: tem_consentimento com âmbito (aplicada 2026-07-22, versão 20260722142207)
-- Só responde ao próprio ou a PT com relação ativa; caso contrário false.

create or replace function tem_consentimento(p_pessoa uuid, p_tipo text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_pessoa = meu_pessoa_id()
      or exists (select 1 from relacoes_pt_cliente r
                 where r.pt_id = meu_pessoa_id()
                   and r.cliente_id = p_pessoa
                   and r.estado = 'ativa')
    then coalesce(
      (select concedido from consentimentos
       where pessoa_id = p_pessoa and tipo = p_tipo
       order by registado_em desc limit 1),
      false)
    else false
  end
$$;
