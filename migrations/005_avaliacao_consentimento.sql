-- BEAST MODE — Migração 005: consentimento (self-service) + avaliação inicial
-- (aplicada 2026-07-31)

create or replace function bm_registar_consentimento(p_tipo text, p_concedido boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := meu_pessoa_id();
  if v_id is null then
    raise exception 'Não autenticado ou pessoa inexistente';
  end if;
  if p_tipo not in ('dados_saude', 'medicoes_corporais') then
    raise exception 'Tipo de consentimento inválido';
  end if;

  insert into consentimentos (pessoa_id, tipo, concedido)
  values (v_id, p_tipo, p_concedido);

  perform registar_evento(
    case when p_concedido then 'consentimento_concedido' else 'consentimento_revogado' end,
    v_id, v_id, jsonb_build_object('tipo', p_tipo));
end $$;

grant execute on function bm_registar_consentimento(text, boolean) to authenticated;
revoke execute on function bm_registar_consentimento(text, boolean) from public, anon;

create or replace function bm_criar_avaliacao(
  p_cliente_id uuid,
  p_objetivo objetivo_treino,
  p_nivel nivel_treino,
  p_dias_disponiveis smallint,
  p_minutos_por_sessao smallint,
  p_equipamento jsonb default '[]'::jsonb,
  p_limitacoes jsonb default '[]'::jsonb,
  p_notas_pt text default null
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
    equipamento, limitacoes, notas_pt
  ) values (
    p_cliente_id, v_pt_id, p_objetivo, p_nivel, p_dias_disponiveis, p_minutos_por_sessao,
    coalesce(p_equipamento, '[]'::jsonb), coalesce(p_limitacoes, '[]'::jsonb), p_notas_pt
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

grant execute on function bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text) to authenticated;
revoke execute on function bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text) from public, anon;
