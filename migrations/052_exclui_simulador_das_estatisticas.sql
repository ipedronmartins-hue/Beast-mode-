-- BEAST MODE — Migração 052: o atleta-simulador não pode contar para estatísticas de
-- negócio reais (contagem de atletas, adesão, receita) — senão os números de resumo
-- ficam sempre errados por causa de uma conta de teste. (aplicada 2026-08-21)

alter table pessoas add column is_teste boolean not null default false;
update pessoas set is_teste = true where email = 'simulador-interno@beastmode.teste';

create or replace function bm_pt_resumo()
returns table(atletas_ativos bigint, atletas_inativos bigint, adesao_pct int, preco_atual numeric)
language sql stable security definer set search_path = public as $$
  with meus_atletas as (
    select p.id, p.estado
    from relacoes_pt_cliente r
    join pessoas p on p.id = r.cliente_id
    where r.pt_id = meu_pessoa_id() and r.estado = 'ativa' and not p.is_teste
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

create or replace function bm_admin_resumo()
returns table(
  pts bigint, atletas bigint, planos_publicados bigint, sessoes_concluidas bigint,
  pagantes_mes bigint, receita_mes numeric, a_pagar_pts numeric
)
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from perfis_pt),
    (select count(distinct r.cliente_id) from relacoes_pt_cliente r join pessoas p on p.id = r.cliente_id
       where r.estado = 'ativa' and not p.is_teste),
    (select count(*) from planos pl join pessoas p on p.id = pl.cliente_id where pl.estado = 'publicado' and not p.is_teste),
    (select count(*) from sessoes_treino s join pessoas p on p.id = s.cliente_id where s.concluida_em is not null and not p.is_teste),
    (select count(*) from comissoes_pt c join pessoas p on p.id = c.atleta_id
       where c.criado_em >= date_trunc('month', now()) and not p.is_teste),
    (select coalesce(sum(c.valor), 0) + count(*) * (select valor from configuracoes where chave = 'margem_beast_liquida')
       from comissoes_pt c join pessoas p on p.id = c.atleta_id
       where c.criado_em >= date_trunc('month', now()) and not p.is_teste),
    (select coalesce(sum(c.valor), 0) from comissoes_pt c join pessoas p on p.id = c.atleta_id
       where c.estado = 'pendente' and not p.is_teste)
  where sou_admin()
$$;
grant execute on function bm_admin_resumo() to authenticated;
revoke execute on function bm_admin_resumo() from anon, public;

create or replace function bm_admin_atletas()
returns table(
  pessoa_id uuid, nome text, email text, conta_ativa boolean, estado text,
  pt_nome text, preco_pt numeric, tem_avaliacao boolean, tem_plano boolean, desde timestamptz
)
language sql stable security definer set search_path = public as $$
  select
    p.id, p.nome, p.email,
    (p.auth_user_id is not null),
    p.estado::text,
    pt_pessoa.nome, pt.preco_atleta,
    exists (select 1 from avaliacoes a where a.cliente_id = p.id),
    exists (select 1 from planos pl where pl.cliente_id = p.id and pl.estado = 'publicado'),
    r.inicio
  from relacoes_pt_cliente r
  join pessoas p on p.id = r.cliente_id
  left join pessoas pt_pessoa on pt_pessoa.id = r.pt_id
  left join perfis_pt pt on pt.pessoa_id = r.pt_id
  where sou_admin() and r.estado = 'ativa' and not p.is_teste
  order by
    case p.estado when 'pendente' then 0 when 'ativo' then 1 when 'suspenso' then 2 else 3 end,
    r.inicio desc
$$;
grant execute on function bm_admin_atletas() to authenticated;
revoke execute on function bm_admin_atletas() from anon, public;
