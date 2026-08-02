-- BEAST MODE — Migração 019: feed de atividade do admin exclui ruído de alta frequência. (aplicada 2026-08-02)
-- serie_registada gera 1 evento por série (15-20 por treino) — inunda o feed sem
-- acrescentar sinal a um resumo de administração. Continua a existir na tabela
-- eventos para auditoria, só não entra neste digest.

create or replace function bm_admin_eventos(p_limite int default 30)
returns table(id bigint, tipo text, ator_nome text, sujeito_nome text, ocorrido_em timestamptz, dados jsonb)
language sql stable security definer set search_path = public as $$
  select e.id, e.tipo, pa.nome, ps.nome, e.ocorrido_em, e.dados
  from eventos e
  left join pessoas pa on pa.id = e.ator_id
  left join pessoas ps on ps.id = e.sujeito_id
  where sou_admin()
    and e.tipo <> 'serie_registada'
  order by e.ocorrido_em desc
  limit p_limite
$$;
