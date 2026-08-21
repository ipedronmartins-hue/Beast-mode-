-- BEAST MODE — Migração 049: inscrição do atleta passa a recolher o perfil todo —
-- idade, altura, peso atual, e os mesmos campos que a avaliação do PT sempre pediu
-- (objetivo, nível, equipamento, limitações, modalidades, corrida/ciclismo). Uma
-- inscrição, um formulário, sem entrevista separada depois. O consentimento de dados
-- de saúde é pedido no mesmo ecrã, explícito, antes de gravar qualquer coisa.
-- (aplicada 2026-08-21)

alter table pessoas add column idade smallint;
alter table pessoas add column altura_cm numeric(5,1);

create or replace function bm_inscrever_atleta(
  p_nome text, p_idade smallint, p_altura_cm numeric, p_peso_kg numeric,
  p_objetivo objetivo_treino, p_nivel nivel_treino,
  p_dias_disponiveis smallint, p_minutos_por_sessao smallint,
  p_equipamento jsonb, p_limitacoes jsonb,
  p_peso_objetivo_kg numeric default null,
  p_pratica_desporto boolean default false, p_desporto_nivel text default null,
  p_modalidades jsonb default '[]'::jsonb, p_local_treino jsonb default '[]'::jsonb,
  p_frequencia_atual_semana smallint default null, p_capacidade_carga text default null,
  p_distancia_alvo_km numeric default null, p_superficie_corrida text default null,
  p_desnivel_corrida text default null, p_data_prova date default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text; v_existing uuid; v_pt_casa uuid; v_avaliacao_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if p_equipamento is null or jsonb_array_length(p_equipamento) = 0 then
    raise exception 'Seleciona pelo menos um equipamento disponível — usa "Sem equipamento" se não houver nenhum.';
  end if;
  if p_limitacoes is null or jsonb_array_length(p_limitacoes) = 0 then
    raise exception 'Seleciona pelo menos uma opção em lesões/limitações — usa "Nenhuma" se não houver.';
  end if;

  select email into v_email from auth.users where id = auth.uid();

  select id into v_id from pessoas where auth_user_id = auth.uid();
  if v_id is not null then
    raise exception 'Já tens conta criada';
  end if;

  select id into v_existing from pessoas where email = v_email and auth_user_id is null;
  if v_existing is not null then
    update pessoas set auth_user_id = auth.uid(), nome = trim(p_nome), idade = p_idade, altura_cm = p_altura_cm
      where id = v_existing;
    v_id := v_existing;
    perform registar_evento('conta_reclamada', v_id, v_id, jsonb_build_object('nome', trim(p_nome)));
  else
    select pessoa_id into v_pt_casa from perfis_pt where estado = 'ativo' and perfil_completo order by criado_em limit 1;
    if v_pt_casa is null then
      raise exception 'Sem treinador disponível de momento — contacta a administração';
    end if;

    insert into pessoas (auth_user_id, nome, email, estado, idade, altura_cm)
    values (auth.uid(), trim(p_nome), v_email, 'pendente', p_idade, p_altura_cm)
    returning id into v_id;

    insert into relacoes_pt_cliente (pt_id, cliente_id, estado) values (v_pt_casa, v_id, 'ativa');

    perform registar_evento('atleta_inscrito', v_id, v_id,
      jsonb_build_object('nome', trim(p_nome), 'pt_id', v_pt_casa));
  end if;

  insert into consentimentos (pessoa_id, tipo, concedido) values (v_id, 'dados_saude', true);
  perform registar_evento('consentimento_concedido', v_id, v_id, jsonb_build_object('tipo', 'dados_saude', 'contexto', 'inscricao'));

  if p_peso_kg is not null then
    insert into medicoes_corporais (cliente_id, tipo, valor, registado_por) values (v_id, 'peso_kg', p_peso_kg, v_id);
  end if;

  insert into avaliacoes (
    cliente_id, pt_id, objetivo, nivel, dias_disponiveis, minutos_por_sessao,
    equipamento, limitacoes, peso_objetivo_kg,
    pratica_desporto, desporto_nivel, modalidades, local_treino,
    frequencia_atual_semana, capacidade_carga,
    distancia_alvo_km, superficie_corrida, desnivel_corrida, data_prova
  ) values (
    v_id, (select pt_id from relacoes_pt_cliente where cliente_id = v_id and estado = 'ativa' order by inicio desc limit 1),
    p_objetivo, p_nivel, p_dias_disponiveis, p_minutos_por_sessao,
    p_equipamento, p_limitacoes, p_peso_objetivo_kg,
    p_pratica_desporto, p_desporto_nivel, coalesce(p_modalidades, '[]'::jsonb), coalesce(p_local_treino, '[]'::jsonb),
    p_frequencia_atual_semana, p_capacidade_carga,
    p_distancia_alvo_km, p_superficie_corrida, p_desnivel_corrida, p_data_prova
  ) returning id into v_avaliacao_id;

  insert into objetivos_cliente (cliente_id, objetivo) values (v_id, p_objetivo);

  perform registar_evento('avaliacao_criada', v_id, v_id,
    jsonb_build_object('avaliacao_id', v_avaliacao_id, 'objetivo', p_objetivo, 'nivel', p_nivel, 'contexto', 'inscricao'));

  return v_id;
end $$;

revoke execute on function bm_inscrever_atleta(text) from anon, public, authenticated;
revoke execute on function bm_inscrever_atleta(
  text, smallint, numeric, numeric, objetivo_treino, nivel_treino, smallint, smallint,
  jsonb, jsonb, numeric, boolean, text, jsonb, jsonb, smallint, text, numeric, text, text, date
) from anon, public;
grant execute on function bm_inscrever_atleta(
  text, smallint, numeric, numeric, objetivo_treino, nivel_treino, smallint, smallint,
  jsonb, jsonb, numeric, boolean, text, jsonb, jsonb, smallint, text, numeric, text, text, date
) to authenticated;
