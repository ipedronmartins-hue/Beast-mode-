-- BEAST MODE — Migração 020: listagem de atletas para o admin. (aplicada 2026-08-02)
-- Prepara o terreno para ações futuras (aprovar/suspender/eliminar) devolvendo já
-- o estado de cada atleta: conta reclamada, avaliação feita, plano ativo.

create or replace function bm_admin_atletas()
returns table(
  pessoa_id uuid, nome text, email text, conta_ativa boolean,
  pt_nome text, tem_avaliacao boolean, tem_plano boolean, desde timestamptz
)
language sql stable security definer set search_path = public as $$
  select
    p.id, p.nome, p.email,
    (p.auth_user_id is not null),
    pt.nome,
    exists (select 1 from avaliacoes a where a.cliente_id = p.id),
    exists (select 1 from planos pl where pl.cliente_id = p.id and pl.estado = 'publicado'),
    r.inicio
  from relacoes_pt_cliente r
  join pessoas p on p.id = r.cliente_id
  left join pessoas pt on pt.id = r.pt_id
  where sou_admin() and r.estado = 'ativa'
  order by r.inicio desc
$$;

grant execute on function bm_admin_atletas() to authenticated;
revoke execute on function bm_admin_atletas() from anon, public;
