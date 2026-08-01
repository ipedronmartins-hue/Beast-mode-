-- BEAST MODE — Migração 013: frequência atual de treino + capacidade de carga na avaliação (aplicada 2026-08-01)

alter table avaliacoes add column frequencia_atual_semana smallint check (frequencia_atual_semana between 0 and 7);
alter table avaliacoes add column capacidade_carga text check (capacidade_carga in ('peso_corporal','leve_ate_10kg','pesada_ginasio'));

create or replace function bm_criar_avaliacao(
  p_cliente_id uuid,
  p_objetivo objetivo_treino,
  p_nivel nivel_treino,
  p_dias_disponiveis smallint,
  p_minutos_por_sessao smallint,
  p_equipamento jsonb default '[]'::jsonb,
  p_limitacoes jsonb default '[]'::jsonb,
  p_notas_pt text default null,
  p_peso_objetivo_kg numeric default null,
  p_pratica_desporto boolean default false,
  p_desporto_nivel text default null,
  p_modalidades jsonb default '[]'::jsonb,
  p_local_treino jsonb default '[]'::jsonb,
  p_frequencia_atual_semana smallint default null,
  p_capacidade_carga text default null
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
    equipamento, limitacoes, notas_pt, peso_objetivo_kg,
    pratica_desporto, desporto_nivel, modalidades, local_treino,
    frequencia_atual_semana, capacidade_carga
  ) values (
    p_cliente_id, v_pt_id, p_objetivo, p_nivel, p_dias_disponiveis, p_minutos_por_sessao,
    coalesce(p_equipamento, '[]'::jsonb), coalesce(p_limitacoes, '[]'::jsonb), p_notas_pt, p_peso_objetivo_kg,
    p_pratica_desporto, p_desporto_nivel, coalesce(p_modalidades, '[]'::jsonb), coalesce(p_local_treino, '[]'::jsonb),
    p_frequencia_atual_semana, p_capacidade_carga
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

drop function if exists bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric, boolean, text, jsonb, jsonb);
revoke execute on function bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric, boolean, text, jsonb, jsonb, smallint, text) from anon, public;
