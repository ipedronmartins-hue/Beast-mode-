-- BEAST MODE — Migração 028: paridade com o MFIT — contadores de adesão, link de
-- cadastro partilhável, painel de atenção para o PT. (aplicada 2026-08-02)

-- 1) Ativos/Inativos + adesão (% que treinou nos últimos 7 dias)
create or replace function bm_pt_resumo()
returns table(atletas_ativos bigint, atletas_inativos bigint, adesao_pct int)
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
    end
  where meu_pessoa_id() is not null
$$;
grant execute on function bm_pt_resumo() to authenticated;
revoke execute on function bm_pt_resumo() from anon, public;

-- 2) Link de cadastro: código curto por PT, junta-se sem o PT ter de saber o email antes
alter table perfis_pt add column codigo_convite text unique;

create or replace function gerar_codigo_convite() returns text
language plpgsql set search_path = public as $$
declare v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_codigo text; v_existe boolean;
begin
  loop
    v_codigo := '';
    for i in 1..6 loop
      v_codigo := v_codigo || substr(v_chars, floor(random() * length(v_chars) + 1)::int, 1);
    end loop;
    select exists(select 1 from perfis_pt where codigo_convite = v_codigo) into v_existe;
    exit when not v_existe;
  end loop;
  return v_codigo;
end $$;

update perfis_pt set codigo_convite = gerar_codigo_convite() where codigo_convite is null;
alter table perfis_pt alter column codigo_convite set default gerar_codigo_convite();

create or replace function bm_juntar_por_codigo(p_codigo text)
returns void language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid; v_cliente_id uuid; v_estado_pt estado_conta;
begin
  v_cliente_id := meu_pessoa_id();
  if v_cliente_id is null then
    raise exception 'Sem sessão';
  end if;

  select pessoa_id, estado into v_pt_id, v_estado_pt from perfis_pt where codigo_convite = upper(trim(p_codigo));
  if v_pt_id is null then
    raise exception 'Código de convite inválido';
  end if;
  if v_estado_pt <> 'ativo' then
    raise exception 'Este treinador ainda não está ativo na plataforma';
  end if;
  if v_pt_id = v_cliente_id then
    raise exception 'Não podes juntar-te a ti próprio';
  end if;

  if exists (select 1 from relacoes_pt_cliente where pt_id = v_pt_id and cliente_id = v_cliente_id and estado = 'ativa') then
    return; -- já associado, silêncioso
  end if;

  insert into relacoes_pt_cliente (pt_id, cliente_id, estado) values (v_pt_id, v_cliente_id, 'ativa');
  perform registar_evento('cliente_juntou_por_link', v_cliente_id, v_pt_id, jsonb_build_object('codigo', p_codigo));
end $$;
grant execute on function bm_juntar_por_codigo(text) to authenticated;
revoke execute on function bm_juntar_por_codigo(text) from anon, public;

create or replace function bm_meu_codigo_convite()
returns text language sql stable security definer set search_path = public as $$
  select codigo_convite from perfis_pt where pessoa_id = meu_pessoa_id()
$$;
grant execute on function bm_meu_codigo_convite() to authenticated;
revoke execute on function bm_meu_codigo_convite() from anon, public;

-- 3) Painel de atenção: quem não treina há dias, ou está com reavaliação vencida
create or replace function bm_pt_atencao()
returns table(atleta_id uuid, nome text, motivo text, dias int)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  with meus_ativos as (
    select p.id, p.nome
    from relacoes_pt_cliente r
    join pessoas p on p.id = r.cliente_id
    where r.pt_id = meu_pessoa_id() and r.estado = 'ativa' and p.estado = 'ativo'
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
grant execute on function bm_pt_atencao() to authenticated;
revoke execute on function bm_pt_atencao() from anon, public;
