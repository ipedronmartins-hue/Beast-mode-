-- BEAST MODE — Migração 046: reset das contas de atleta em beta (Sofia, Barbosa, Vítor),
-- confirmado explicitamente pelo fundador. As tabelas append-only (eventos,
-- registos_serie, medicoes_corporais) desativam o próprio guardrail de imutabilidade
-- só durante esta transação, e voltam a ficar trancadas no fim — não é uma alteração
-- permanente à proteção. (aplicada 2026-08-21)

alter table eventos disable trigger trg_eventos_imutavel;
alter table registos_serie disable trigger trg_registos_imutavel;
alter table medicoes_corporais disable trigger trg_medicoes_imutavel;

do $$
declare v_ids uuid[] := array['376b48b9-bece-4f43-aa11-0c61e775dbb6','fd21ad2e-0b0d-471d-8855-51fc8ac454cb','600ea617-2afd-4f06-8d27-5b28a4e1baaa'];
begin
  delete from comentarios_pt where sessao_id in (select id from sessoes_treino where cliente_id = any(v_ids));
  delete from registos_serie where sessao_id in (select id from sessoes_treino where cliente_id = any(v_ids));
  delete from sessoes_treino where cliente_id = any(v_ids);
  delete from comissoes_pt where atleta_id = any(v_ids);
  delete from medicoes_corporais where cliente_id = any(v_ids);
  delete from consentimentos where pessoa_id = any(v_ids);
  delete from objetivos_cliente where cliente_id = any(v_ids);
  delete from planos where cliente_id = any(v_ids);
  delete from avaliacoes where cliente_id = any(v_ids);
  delete from relacoes_pt_cliente where cliente_id = any(v_ids);
  delete from eventos where sujeito_id = any(v_ids) or ator_id = any(v_ids);
  delete from pessoas where id = any(v_ids);
end $$;

alter table eventos enable trigger trg_eventos_imutavel;
alter table registos_serie enable trigger trg_registos_imutavel;
alter table medicoes_corporais enable trigger trg_medicoes_imutavel;
