-- BEAST MODE — Migração 023: preço mensal do atleta 9,90€ -> 29,90€ (aplicada 2026-08-02)

update configuracoes set valor = 29.90, atualizado_em = now() where chave = 'preco_atleta_mensal';
