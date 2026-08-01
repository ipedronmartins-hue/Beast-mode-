-- BEAST MODE — Migração 015: rotação de WODs passa de 4 para 7, dia de corrida ganha
-- descrição de estrutura, exercícios devolvem descricao (técnica). (aplicada 2026-08-01)

create or replace function bm_gerar_plano(p_cliente_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_pt_id uuid;
  v_aval record;
  v_par record;
  v_nivel_rank int;
  v_series smallint;
  v_descanso smallint;
  v_num_ex int;
  v_dias jsonb := '[]'::jsonb;
  v_dia_nomes text[];
  v_dia_nome text;
  v_padroes text[];
  v_padrao text;
  v_exercicios_dia jsonb;
  v_usados text[];
  v_ex record;
  v_plano_id uuid;
  v_planos_anteriores int;
  v_wod record;
  v_formato_corrida text;
  v_local_corrida text;
  v_desc_corrida text;
  i int;
  j int;
begin
  v_pt_id := meu_pessoa_id();
  if v_pt_id is null or not exists (select 1 from perfis_pt where pessoa_id = v_pt_id) then
    raise exception 'Só treinadores podem gerar planos';
  end if;
  if not exists (select 1 from relacoes_pt_cliente
                 where pt_id = v_pt_id and cliente_id = p_cliente_id and estado = 'ativa') then
    raise exception 'Sem relação ativa com este cliente';
  end if;
  if not tem_consentimento(p_cliente_id, 'dados_saude') then
    raise exception 'Cliente ainda não deu consentimento para dados de saúde';
  end if;

  select * into v_aval from avaliacoes
    where cliente_id = p_cliente_id order by criado_em desc limit 1;
  if v_aval is null then
    raise exception 'Sem avaliação para este cliente';
  end if;

  select * into v_par from motor_parametros_objetivo where objetivo = v_aval.objetivo;

  v_nivel_rank := case v_aval.nivel when 'iniciante' then 1 when 'intermedio' then 2 else 3 end;
  v_series := v_par.series + (case when v_aval.nivel = 'avancado' then 1 when v_aval.nivel = 'iniciante' then -1 else 0 end);
  v_series := greatest(v_series, 2);
  v_descanso := v_par.descanso_seg + (case when v_aval.nivel = 'iniciante' then 15 else 0 end);
  v_num_ex := greatest(3, least(7, (v_aval.minutos_por_sessao / 10) - 1));

  if v_aval.dias_disponiveis <= 2 then
    v_dia_nomes := array_fill('Full Body', array[v_aval.dias_disponiveis]);
  elsif v_aval.dias_disponiveis = 3 then
    v_dia_nomes := array['Full Body A','Full Body B','Full Body C'];
  elsif v_aval.dias_disponiveis = 4 then
    v_dia_nomes := array['Upper A','Lower A','Upper B','Lower B'];
  else
    v_dia_nomes := array['Push','Pull','Legs','Push','Pull','Legs'];
    v_dia_nomes := v_dia_nomes[1:v_aval.dias_disponiveis];
  end if;

  for i in 1 .. array_length(v_dia_nomes, 1) loop
    v_dia_nome := v_dia_nomes[i];
    v_padroes := case
      when v_dia_nome like 'Full Body%' then array['squat','hinge','push','pull','core','isolamento']
      when v_dia_nome like 'Upper%' then array['push','pull','push','pull','isolamento']
      when v_dia_nome like 'Lower%' then array['squat','hinge','isolamento','core']
      when v_dia_nome = 'Push' then array['push','push','isolamento','isolamento']
      when v_dia_nome = 'Pull' then array['pull','pull','isolamento']
      when v_dia_nome = 'Legs' then array['squat','hinge','isolamento','core']
      else array['squat','hinge','push','pull','core']
    end;

    v_exercicios_dia := '[]'::jsonb;
    v_usados := '{}';

    for j in 1 .. v_num_ex loop
      v_padrao := v_padroes[((j - 1) % array_length(v_padroes, 1)) + 1];

      select * into v_ex from exercicios ex
        where ex.padrao = v_padrao::padrao_exercicio
          and (v_aval.equipamento ? ex.equipamento_necessario)
          and not (v_aval.limitacoes ?| ex.contraindicado_se)
          and (case ex.nivel_min when 'iniciante' then 1 when 'intermedio' then 2 else 3 end) <= v_nivel_rank
          and not (ex.id = any(v_usados))
        order by ex.id
        limit 1;

      if v_ex.id is not null then
        v_usados := array_append(v_usados, v_ex.id);
        v_exercicios_dia := v_exercicios_dia || jsonb_build_object(
          'exercicio_id', v_ex.id, 'nome', v_ex.nome, 'padrao', v_ex.padrao, 'descricao', v_ex.descricao,
          'series', v_series, 'reps_min', v_par.reps_min, 'reps_max', v_par.reps_max,
          'descanso_seg', v_descanso
        );
      end if;
    end loop;

    v_dias := v_dias || jsonb_build_object('nome', v_dia_nome, 'tipo', 'forca', 'exercicios', v_exercicios_dia);
  end loop;

  if v_aval.modalidades ? 'corrida' then
    v_formato_corrida := case v_aval.desporto_nivel
      when 'competitivo' then 'intervalada'
      when 'recreativo' then 'fartlek'
      else 'continua'
    end;
    v_local_corrida := case
      when v_aval.local_treino ? 'rua' then 'rua'
      when v_aval.local_treino ? 'ginasio' then 'passadeira (ginásio)'
      else 'rua'
    end;
    v_desc_corrida := case v_formato_corrida
      when 'intervalada' then 'Séries de VO2 máx: 8-10x 1 min a ritmo máximo sustentável, recuperação de 1 min entre séries.'
      when 'fartlek' then 'Alternância contínua: 10x (1 min rápido + 1 min lento), sem parar.'
      else 'Ritmo contínuo e conversacional (zona 2), foco em construir base aeróbica, não velocidade.'
    end;
    v_dias := v_dias || jsonb_build_object(
      'nome', 'Corrida', 'tipo', 'corrida',
      'formato', v_formato_corrida, 'descricao', v_desc_corrida,
      'local', v_local_corrida, 'duracao_min', v_aval.minutos_por_sessao
    );
  end if;

  select count(*) into v_planos_anteriores from planos where cliente_id = p_cliente_id;
  select * into v_wod from wods_referencia order by id offset (v_planos_anteriores % 7) limit 1;
  v_dias := v_dias || jsonb_build_object(
    'nome', 'Dia de Estímulo (a cada 15 dias)', 'tipo', 'estimulo',
    'wod_nome', v_wod.nome, 'wod_formato', v_wod.formato, 'wod_descricao', v_wod.descricao
  );

  insert into planos (cliente_id, pt_id, avaliacao_id, nome, estado, parametros, conteudo)
  values (
    p_cliente_id, v_pt_id, v_aval.id,
    'Plano ' || v_aval.objetivo::text || ' — ' || to_char(now(), 'DD/MM/YYYY'),
    'rascunho',
    jsonb_build_object(
      'objetivo', v_aval.objetivo, 'nivel', v_aval.nivel, 'series', v_series,
      'reps_min', v_par.reps_min, 'reps_max', v_par.reps_max, 'descanso_seg', v_descanso,
      'rpe_alvo', v_par.rpe_alvo, 'progressao', v_par.progressao,
      'dias_disponiveis', v_aval.dias_disponiveis, 'minutos_por_sessao', v_aval.minutos_por_sessao,
      'reavaliar_em', to_char(now() + interval '12 weeks', 'YYYY-MM-DD')
    ),
    jsonb_build_object('dias', v_dias)
  ) returning id into v_plano_id;

  perform registar_evento('plano_gerado', v_pt_id, p_cliente_id,
    jsonb_build_object('plano_id', v_plano_id, 'objetivo', v_aval.objetivo));

  return v_plano_id;
end $$;
