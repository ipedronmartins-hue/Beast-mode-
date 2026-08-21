-- BEAST MODE — Migração 048: mesmo erro de sempre (migrações 009, 038) — mudar assinatura
-- de RPC cria função nova em Postgres, que nasce acessível a anon. Dois casos encontrados
-- pelo linter: bm_concluir_sessao (esta sessão) e bm_iniciar_sessao (já existia, apanhado
-- de caminho). Remove overloads antigos, tranca as versões atuais. (aplicada 2026-08-21)

drop function if exists bm_concluir_sessao(uuid, jsonb, numeric, integer, numeric, numeric, integer, numeric);
revoke execute on function bm_concluir_sessao(
  uuid, jsonb, numeric, integer, numeric, numeric, integer, numeric, numeric, smallint, integer
) from anon, public;
grant execute on function bm_concluir_sessao(
  uuid, jsonb, numeric, integer, numeric, numeric, integer, numeric, numeric, smallint, integer
) to authenticated;

drop function if exists bm_iniciar_sessao(uuid, text);
revoke execute on function bm_iniciar_sessao(uuid, text, text) from anon, public;
grant execute on function bm_iniciar_sessao(uuid, text, text) to authenticated;
