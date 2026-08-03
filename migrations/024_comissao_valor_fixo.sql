-- BEAST MODE — Migração 024: comissão do PT passa de percentagem para valor fixo (aplicada 2026-08-02)
-- 29,90€ preço do atleta - 14,90€ PT = 15,00€ para a plataforma, por atleta ativo.

delete from configuracoes where chave = 'comissao_pt_percentagem';
insert into configuracoes (chave, valor) values ('comissao_pt_valor', 14.90)
  on conflict (chave) do update set valor = 14.90, atualizado_em = now();

create or replace function bm_admin_confirmar_pagamento(p_atleta_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid; v_pt_id uuid; v_comissao numeric;
begin
  if not sou_admin() then
    raise exception 'Apenas administradores';
  end if;
  v_admin := meu_pessoa_id();

  select pt_id into v_pt_id from relacoes_pt_cliente
    where cliente_id = p_atleta_id and estado = 'ativa'
    order by inicio desc limit 1;
  if v_pt_id is null then
    raise exception 'Este atleta não tem treinador associado';
  end if;

  select valor into v_comissao from configuracoes where chave = 'comissao_pt_valor';

  update pessoas set estado = 'ativo' where id = p_atleta_id;

  insert into comissoes_pt (pt_id, atleta_id, valor) values (v_pt_id, p_atleta_id, v_comissao);

  perform registar_evento('pagamento_confirmado_admin', v_admin, p_atleta_id,
    jsonb_build_object('pt_id', v_pt_id, 'comissao', v_comissao));
end $$;
