-- BEAST MODE — Migração 038: bm_criar_avaliacao mudou de assinatura (+4 parâmetros de
-- corrida) na migração 036 — isso cria uma função NOVA em Postgres, não substitui a
-- antiga, e a nova nasce com permissões por omissão (anon incluído). Mesmo erro já visto
-- antes nesta base (migração 009). Remove o overload antigo, tranca o novo. (aplicada 2026-08-11)

drop function if exists bm_criar_avaliacao(
  uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric,
  boolean, text, jsonb, jsonb, smallint, text
);

revoke execute on function bm_criar_avaliacao(
  uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric,
  boolean, text, jsonb, jsonb, smallint, text, numeric, text, text, date
) from anon, public;
grant execute on function bm_criar_avaliacao(
  uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric,
  boolean, text, jsonb, jsonb, smallint, text, numeric, text, text, date
) to authenticated;

create or replace function bm_classificar_corrida(p_km numeric) returns text
language sql immutable set search_path = public as $$
  select case
    when p_km is null then null
    when p_km <= 0.4 then 'Sprint / Velocidade'
    when p_km <= 3 then 'Média distância'
    when p_km <= 5 then '5K'
    when p_km <= 10 then '10K'
    when p_km < 21.1 then 'Distância longa'
    when p_km = 21.1 then 'Meia-maratona'
    when p_km < 42.2 then 'Meia-maratona +'
    when p_km = 42.2 then 'Maratona'
    else 'Ultra'
  end
$$;
