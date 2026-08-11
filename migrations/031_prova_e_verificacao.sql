-- BEAST MODE — Migração 031: dois bugs reais de "número falso quando não há dado". (aplicada 2026-08-11)
-- 1) adesao_pct mostrava 0% com zero atletas ativos (devia ser NULL/—, não um "mau" real).
-- 2) medições não distinguiam quem registou (PT vs. o próprio atleta) — o dado já existia
--    na tabela (registado_por), só não saía das funções.

drop function if exists bm_pt_resumo();
create function bm_pt_resumo()
returns table(atletas_ativos bigint, atletas_inativos bigint, adesao_pct int, preco_atual numeric)
language sql stable security definer set search_path = public as $$
  with meus_atletas as (
    select p.id, p.estado
    from relacoes_pt_cliente r
    join pessoas p on p.id = r.cliente_id
    where r.pt_id = meu_pessoa_id() and r.estado = 'ativa'
  ),
  treinaram_7d as (
    select distinct s.cliente_id
    from sessoes_treino s
    where s.cliente_id in (select id from meus_atletas where estado = 'ativo')
      and s.concluida_em >= now() - interval '7 days'
  )
  select
    (select count(*) from meus_atletas where estado = 'ativo'),
    (select count(*) from meus_atletas where estado != 'ativo'),
    case when (select count(*) from meus_atletas where estado = 'ativo') = 0 then null
      else round(100.0 * (select count(*) from treinaram_7d) / (select count(*) from meus_atletas where estado = 'ativo'))::int
    end,
    (select preco_atleta from perfis_pt where pessoa_id = meu_pessoa_id())
  where meu_pessoa_id() is not null
$$;
grant execute on function bm_pt_resumo() to authenticated;
revoke execute on function bm_pt_resumo() from anon, public;

drop function if exists bm_ultimas_medicoes(uuid);
create function bm_ultimas_medicoes(p_cliente_id uuid)
returns table(tipo text, valor numeric, registado_em timestamptz, autodeclarado boolean)
language sql stable security definer set search_path = public as $$
  select distinct on (m.tipo) m.tipo, m.valor, m.registado_em, (m.registado_por = m.cliente_id)
  from medicoes_corporais m
  where m.cliente_id = p_cliente_id
    and (
      p_cliente_id = meu_pessoa_id()
      or exists (select 1 from relacoes_pt_cliente r
                 where r.pt_id = meu_pessoa_id() and r.cliente_id = p_cliente_id and r.estado = 'ativa')
    )
  order by m.tipo, m.registado_em desc
$$;
grant execute on function bm_ultimas_medicoes(uuid) to authenticated;
revoke execute on function bm_ultimas_medicoes(uuid) from anon, public;
