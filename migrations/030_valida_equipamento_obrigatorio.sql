-- BEAST MODE — Migração 030: avaliação sem nenhum equipamento selecionado gerava
-- planos vazios em silêncio ("Sem exercícios elegíveis" em todos os dias). (aplicada 2026-08-11)
-- Bloqueia na origem — a única mudança real são as duas validações a seguir ao consentimento.

CREATE OR REPLACE FUNCTION public.bm_criar_avaliacao(
  p_cliente_id uuid, p_objetivo objetivo_treino, p_nivel nivel_treino,
  p_dias_disponiveis smallint, p_minutos_por_sessao smallint,
  p_equipamento jsonb DEFAULT '[]'::jsonb, p_limitacoes jsonb DEFAULT '[]'::jsonb,
  p_notas_pt text DEFAULT NULL::text, p_peso_objetivo_kg numeric DEFAULT NULL::numeric,
  p_pratica_desporto boolean DEFAULT false, p_desporto_nivel text DEFAULT NULL::text,
  p_modalidades jsonb DEFAULT '[]'::jsonb, p_local_treino jsonb DEFAULT '[]'::jsonb,
  p_frequencia_atual_semana smallint DEFAULT NULL::smallint, p_capacidade_carga text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
  if p_equipamento is null or jsonb_array_length(p_equipamento) = 0 then
    raise exception 'Seleciona pelo menos um equipamento disponível — usa "Sem equipamento" se não houver nenhum, o motor precisa de saber isso para escolher exercícios.';
  end if;
  if p_limitacoes is null or jsonb_array_length(p_limitacoes) = 0 then
    raise exception 'Seleciona pelo menos uma opção em lesões/limitações — usa "Nenhuma" se não houver.';
  end if;

  insert into avaliacoes (
    cliente_id, pt_id, objetivo, nivel, dias_disponiveis, minutos_por_sessao,
    equipamento, limitacoes, notas_pt, peso_objetivo_kg,
    pratica_desporto, desporto_nivel, modalidades, local_treino,
    frequencia_atual_semana, capacidade_carga
  ) values (
    p_cliente_id, v_pt_id, p_objetivo, p_nivel, p_dias_disponiveis, p_minutos_por_sessao,
    p_equipamento, p_limitacoes, p_notas_pt, p_peso_objetivo_kg,
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
end $function$;

-- Correção pontual: a avaliação da Sofia criada em 2026-08-11 tinha equipamento
-- vazio (bug acima). Definido como "Sem equipamento" para destravar — confirmar
-- se está correto, ou refazer a avaliação com as opções reais dela.
update avaliacoes set equipamento = '["Sem equipamento"]'::jsonb
  where id = '3aee5cb1-9590-4bd7-8871-ddb8c998f9f5';
