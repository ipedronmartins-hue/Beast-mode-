-- BEAST MODE — Migração 053: o simulador não pode aparecer em "Precisam de atenção"
-- como um alarme falso permanente ("ainda sem primeiro treino" para sempre).
-- (aplicada 2026-08-21)

create or replace function bm_pt_atencao()
returns table(atleta_id uuid, nome text, motivo text, dias int)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  with meus_ativos as (
    select p.id, p.nome
    from relacoes_pt_cliente r
    join pessoas p on p.id = r.cliente_id
    where r.pt_id = meu_pessoa_id() and r.estado = 'ativa' and p.estado = 'ativo' and not p.is_teste
  ),
  ultima_sessao as (
    select cliente_id, max(concluida_em) as ultima
    from sessoes_treino where concluida_em is not null
    group by cliente_id
  ),
  plano_ativo as (
    select distinct on (cliente_id) cliente_id, publicado_em, parametros
    from planos where estado = 'publicado'
    order by cliente_id, publicado_em desc
  )
  select a.id, a.nome,
    case
      when us.ultima is null and pa.publicado_em is not null and pa.publicado_em < now() - interval '3 days'
        then 'Ainda sem primeiro treino'
      when us.ultima is not null and us.ultima < now() - interval '5 days'
        then 'Sem treinar há dias'
      when pa.parametros->>'reavaliar_em' is not null
        and (pa.parametros->>'reavaliar_em')::date < current_date
        then 'Reavaliação em atraso'
      else null
    end as motivo,
    case
      when us.ultima is null and pa.publicado_em is not null then extract(day from now() - pa.publicado_em)::int
      when us.ultima is not null then extract(day from now() - us.ultima)::int
      else null
    end as dias
  from meus_ativos a
  left join ultima_sessao us on us.cliente_id = a.id
  left join plano_ativo pa on pa.cliente_id = a.id
  where (
      (us.ultima is null and pa.publicado_em is not null and pa.publicado_em < now() - interval '3 days')
      or (us.ultima is not null and us.ultima < now() - interval '5 days')
      or (pa.parametros->>'reavaliar_em' is not null and (pa.parametros->>'reavaliar_em')::date < current_date)
    )
  order by dias desc nulls last;
end $$;
