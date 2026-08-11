-- BEAST MODE — Migração 034: a carga/reps/RPE que o atleta regista série a série
-- eram capturadas mas nunca surgiam em lado nenhum da interface — nem para o PT,
-- nem no "Ver como atleta". Só existia um contador ("5 séries registadas"). (aplicada 2026-08-11)

create or replace function bm_registos_sessao(p_sessao_id uuid)
returns table(exercicio text, numero_serie smallint, carga_kg numeric, repeticoes smallint, rpe numeric)
language sql stable security definer set search_path = public as $$
  select r.exercicio, r.numero_serie, r.carga_kg, r.repeticoes, r.rpe
  from registos_serie r
  join sessoes_treino s on s.id = r.sessao_id
  where r.sessao_id = p_sessao_id
    and (
      s.cliente_id = meu_pessoa_id()
      or exists (select 1 from relacoes_pt_cliente rel
                 where rel.pt_id = meu_pessoa_id() and rel.cliente_id = s.cliente_id and rel.estado = 'ativa')
      or sou_admin()
    )
  order by r.exercicio, r.numero_serie
$$;
grant execute on function bm_registos_sessao(uuid) to authenticated;
revoke execute on function bm_registos_sessao(uuid) from anon, public;
