-- BEAST MODE — Migração 029: preço definido pelo PT (mínimo 29,90€), margem fixa
-- de 15€ líquidos para a plataforma. Substitui a comissão fixa de 14,90€. (aplicada 2026-08-02)

alter table perfis_pt add column preco_atleta numeric(6,2) not null default 29.90
  check (preco_atleta >= 29.90);

insert into configuracoes (chave, valor) values ('margem_beast_liquida', 15.00)
  on conflict (chave) do update set valor = 15.00, atualizado_em = now();

create or replace function bm_definir_preco(p_preco numeric)
returns void language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid;
begin
  v_pt_id := meu_pessoa_id();
  if v_pt_id is null or not exists (select 1 from perfis_pt where pessoa_id = v_pt_id) then
    raise exception 'Só treinadores podem definir preço';
  end if;
  if p_preco < 29.90 then
    raise exception 'O preço mínimo é 29,90€';
  end if;

  update perfis_pt set preco_atleta = p_preco where pessoa_id = v_pt_id;
  perform registar_evento('preco_definido', v_pt_id, v_pt_id, jsonb_build_object('preco', p_preco));
end $$;
grant execute on function bm_definir_preco(numeric) to authenticated;
revoke execute on function bm_definir_preco(numeric) from anon, public;

create or replace function bm_meu_preco()
returns numeric language sql stable security definer set search_path = public as $$
  select pt.preco_atleta
  from relacoes_pt_cliente r
  join perfis_pt pt on pt.pessoa_id = r.pt_id
  where r.cliente_id = meu_pessoa_id() and r.estado = 'ativa'
  order by r.inicio desc limit 1
$$;
grant execute on function bm_meu_preco() to authenticated;
revoke execute on function bm_meu_preco() from anon, public;

create or replace function bm_admin_confirmar_pagamento(p_atleta_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid; v_pt_id uuid; v_preco_pt numeric; v_margem numeric; v_comissao numeric;
begin
  if not sou_admin() then
    raise exception 'Apenas administradores';
  end if;
  v_admin := meu_pessoa_id();

  select r.pt_id, pt.preco_atleta into v_pt_id, v_preco_pt
    from relacoes_pt_cliente r
    join perfis_pt pt on pt.pessoa_id = r.pt_id
    where r.cliente_id = p_atleta_id and r.estado = 'ativa'
    order by r.inicio desc limit 1;
  if v_pt_id is null then
    raise exception 'Este atleta não tem treinador associado';
  end if;

  select valor into v_margem from configuracoes where chave = 'margem_beast_liquida';
  v_comissao := round(v_preco_pt - v_margem, 2);

  update pessoas set estado = 'ativo' where id = p_atleta_id;

  insert into comissoes_pt (pt_id, atleta_id, valor) values (v_pt_id, p_atleta_id, v_comissao);

  perform registar_evento('pagamento_confirmado_admin', v_admin, p_atleta_id,
    jsonb_build_object('pt_id', v_pt_id, 'preco', v_preco_pt, 'comissao', v_comissao));
end $$;

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
    case when (select count(*) from meus_atletas where estado = 'ativo') = 0 then 0
      else round(100.0 * (select count(*) from treinaram_7d) / (select count(*) from meus_atletas where estado = 'ativo'))::int
    end,
    (select preco_atleta from perfis_pt where pessoa_id = meu_pessoa_id())
  where meu_pessoa_id() is not null
$$;
grant execute on function bm_pt_resumo() to authenticated;
revoke execute on function bm_pt_resumo() from anon, public;

drop function if exists bm_admin_resumo();
create function bm_admin_resumo()
returns table(
  pts bigint, atletas bigint, planos_publicados bigint, sessoes_concluidas bigint,
  pagantes_mes bigint, receita_mes numeric, a_pagar_pts numeric
)
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from perfis_pt),
    (select count(distinct cliente_id) from relacoes_pt_cliente where estado = 'ativa'),
    (select count(*) from planos where estado = 'publicado'),
    (select count(*) from sessoes_treino where concluida_em is not null),
    (select count(*) from comissoes_pt where criado_em >= date_trunc('month', now())),
    (select coalesce(sum(valor), 0) + count(*) * (select valor from configuracoes where chave = 'margem_beast_liquida')
       from comissoes_pt where criado_em >= date_trunc('month', now())),
    (select coalesce(sum(valor), 0) from comissoes_pt where estado = 'pendente')
  where sou_admin()
$$;
grant execute on function bm_admin_resumo() to authenticated;
revoke execute on function bm_admin_resumo() from anon, public;

drop function if exists bm_admin_atletas();
create function bm_admin_atletas()
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
  where sou_admin() and r.estado = 'ativa'
  order by
    case p.estado when 'pendente' then 0 when 'ativo' then 1 when 'suspenso' then 2 else 3 end,
    r.inicio desc
$$;
grant execute on function bm_admin_atletas() to authenticated;
revoke execute on function bm_admin_atletas() from anon, public;
