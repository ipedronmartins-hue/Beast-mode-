-- BEAST MODE — Migração 009: remove overload antigo de bm_criar_avaliacao e fecha anon (aplicada 2026-08-01)

drop function if exists bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text);

revoke execute on function bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric) from anon, public;
