-- BEAST MODE — Migração 027: contacto MBWay para o ecrã de bloqueio do atleta. (aplicada 2026-08-02)
-- configuracoes.valor é numeric — precisa de um sítio para texto também.

alter table configuracoes add column valor_texto text;

insert into configuracoes (chave, valor, valor_texto) values ('mbway_contacto', 0, '913 695 846')
  on conflict (chave) do update set valor_texto = '913 695 846', atualizado_em = now();
