-- BEAST MODE — Migração 008: execução do treino (módulo 4) + peso_objetivo na avaliação (aplicada 2026-08-01)

create or replace function bm_criar_avaliacao(
  p_cliente_id uuid,
  p_objetivo objetivo_treino,
  p_nivel nivel_treino,
  p_dias_disponiveis smallint,
  p_minutos_por_sessao smallint,
  p_equipamento jsonb default '[]'::jsonb,
  p_limitacoes jsonb default '[]'::jsonb,
  p_notas_pt text default null,
  p_peso_objetivo_kg numeric default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid; v_avaliacao_id uuid; v_objetivo_anterior objetivo_treino;
begin
  v_pt_id := meu_pessoa_id();
  if v_pt_id is null or not exists (select 1 from perfis_pt where pessoa_id = v_pt_id) then
    raise exception 'Só treinadores podem criar avaliações';
  end if;
  if not exists (select 1 from relacoes_pt_cliente
                 where pt_id = v_pt_id and cliente_id = p_cliente_id and estado = 'ativa') then
    raise exception 'Sem relação ativa com este cliente';
  end if;
  if not tem_consentimento(p_cliente_id, 'dados_saude') then
    raise exception 'Cliente ainda não deu consentimento para dados de saúde';
  end if;

  insert into avaliacoes (
    cliente_id, pt_id, objetivo, nivel, dias_disponiveis, minutos_por_sessao,
    equipamento, limitacoes, notas_pt, peso_objetivo_kg
  ) values (
    p_cliente_id, v_pt_id, p_objetivo, p_nivel, p_dias_disponiveis, p_minutos_por_sessao,
    coalesce(p_equipamento, '[]'::jsonb), coalesce(p_limitacoes, '[]'::jsonb), p_notas_pt, p_peso_objetivo_kg
  ) returning id into v_avaliacao_id;

  select objetivo into v_objetivo_anterior
    from objetivos_cliente
    where cliente_id = p_cliente_id and ativo_ate is null
    order by ativo_desde desc limit 1;

  if v_objetivo_anterior is null or v_objetivo_anterior <> p_objetivo then
    update objetivos_cliente set ativo_ate = now()
      where cliente_id = p_cliente_id and ativo_ate is null;
    insert into objetivos_cliente (cliente_id, objetivo) values (p_cliente_id, p_objetivo);
  end if;

  perform registar_evento('avaliacao_criada', v_pt_id, p_cliente_id,
    jsonb_build_object('avaliacao_id', v_avaliacao_id, 'objetivo', p_objetivo, 'nivel', p_nivel));

  return v_avaliacao_id;
end $$;

create or replace function bm_iniciar_sessao(p_plano_id uuid, p_dia_plano text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_cliente_id uuid; v_sessao_id uuid;
begin
  v_cliente_id := meu_pessoa_id();
  if not exists (select 1 from planos where id = p_plano_id and cliente_id = v_cliente_id and estado = 'publicado') then
    raise exception 'Plano não encontrado ou não publicado para este cliente';
  end if;

  insert into sessoes_treino (plano_id, cliente_id, dia_plano)
  values (p_plano_id, v_cliente_id, p_dia_plano)
  returning id into v_sessao_id;

  perform registar_evento('sessao_iniciada', v_cliente_id, v_cliente_id,
    jsonb_build_object('sessao_id', v_sessao_id, 'plano_id', p_plano_id, 'dia_plano', p_dia_plano));

  return v_sessao_id;
end $$;

grant execute on function bm_iniciar_sessao(uuid, text) to authenticated;
revoke execute on function bm_iniciar_sessao(uuid, text) from public, anon;

create or replace function bm_registar_serie(
  p_sessao_id uuid, p_exercicio text, p_numero_serie smallint,
  p_carga_kg numeric, p_repeticoes smallint, p_rpe numeric
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_cliente_id uuid; v_registo_id uuid;
begin
  v_cliente_id := meu_pessoa_id();
  if not exists (select 1 from sessoes_treino
                 where id = p_sessao_id and cliente_id = v_cliente_id and concluida_em is null) then
    raise exception 'Sessão não encontrada, não pertence a este cliente, ou já foi concluída';
  end if;

  insert into registos_serie (sessao_id, exercicio, numero_serie, carga_kg, repeticoes, rpe)
  values (p_sessao_id, p_exercicio, p_numero_serie, p_carga_kg, p_repeticoes, p_rpe)
  returning id into v_registo_id;

  perform registar_evento('serie_registada', v_cliente_id, v_cliente_id,
    jsonb_build_object('sessao_id', p_sessao_id, 'exercicio', p_exercicio,
      'numero_serie', p_numero_serie, 'carga_kg', p_carga_kg, 'repeticoes', p_repeticoes, 'rpe', p_rpe));

  return v_registo_id;
end $$;

grant execute on function bm_registar_serie(uuid, text, smallint, numeric, smallint, numeric) to authenticated;
revoke execute on function bm_registar_serie(uuid, text, smallint, numeric, smallint, numeric) from public, anon;

create or replace function bm_concluir_sessao(p_sessao_id uuid, p_feedback jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_cliente_id uuid;
begin
  v_cliente_id := meu_pessoa_id();
  if not exists (select 1 from sessoes_treino
                 where id = p_sessao_id and cliente_id = v_cliente_id and concluida_em is null) then
    raise exception 'Sessão não encontrada, não pertence a este cliente, ou já foi concluída';
  end if;

  update sessoes_treino set concluida_em = now(), feedback = p_feedback where id = p_sessao_id;

  perform registar_evento('sessao_concluida', v_cliente_id, v_cliente_id,
    jsonb_build_object('sessao_id', p_sessao_id, 'feedback', p_feedback));
end $$;

grant execute on function bm_concluir_sessao(uuid, jsonb) to authenticated;
revoke execute on function bm_concluir_sessao(uuid, jsonb) from public, anon;

create or replace function bm_sessoes_cliente(p_cliente_id uuid, p_limite int default 10)
returns table(
  sessao_id uuid, dia_plano text, iniciada_em timestamptz, concluida_em timestamptz,
  feedback jsonb, num_series bigint
)
language sql stable security definer set search_path = public as $$
  select s.id, s.dia_plano, s.iniciada_em, s.concluida_em, s.feedback,
    (select count(*) from registos_serie rs where rs.sessao_id = s.id)
  from sessoes_treino s
  where s.cliente_id = p_cliente_id
    and (
      p_cliente_id = meu_pessoa_id()
      or exists (select 1 from relacoes_pt_cliente r
                 where r.pt_id = meu_pessoa_id() and r.cliente_id = p_cliente_id and r.estado = 'ativa')
    )
  order by s.iniciada_em desc
  limit p_limite
$$;

grant execute on function bm_sessoes_cliente(uuid, int) to authenticated;
revoke execute on function bm_sessoes_cliente(uuid, int) from public, anon;
