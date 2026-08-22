-- BEAST MODE — Migração 050: resumo do atleta na página Treino — última sessão,
-- sessões esta semana vs. dias planeados. Tudo real, nada de "readiness" inventado
-- sem sensor nenhum por trás. (aplicada 2026-08-21)

create or replace function bm_meu_resumo()
returns table(ultima_sessao_em timestamptz, ultima_sessao_tipo text, sessoes_esta_semana bigint, dias_planeados smallint)
language sql stable security definer set search_path = public as $$
  select
    (select max(concluida_em) from sessoes_treino where cliente_id = meu_pessoa_id() and concluida_em is not null),
    (select dia_plano from sessoes_treino where cliente_id = meu_pessoa_id() and concluida_em is not null
       order by concluida_em desc limit 1),
    (select count(*) from sessoes_treino where cliente_id = meu_pessoa_id() and concluida_em is not null
       and concluida_em >= date_trunc('week', now())),
    (select (parametros->>'dias_disponiveis')::smallint from planos
       where cliente_id = meu_pessoa_id() and estado = 'publicado' order by publicado_em desc limit 1)
  where meu_pessoa_id() is not null
$$;
grant execute on function bm_meu_resumo() to authenticated;
revoke execute on function bm_meu_resumo() from anon, public;
