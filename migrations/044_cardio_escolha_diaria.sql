-- BEAST MODE — Migração 044: escolha diária de cardio + reavaliação diferenciada.
--
-- Duas mudanças de comportamento pedidas pelo fundador:
-- 1) Quando o plano tem ginásio + corrida + ciclismo, o motor deixa de fixar
--    antecipadamente "este dia é corrida" — gera as DUAS prescrições no mesmo
--    slot de complemento cardio, e o atleta escolhe ao vivo qual faz nesse dia
--    ("Hoje faço: Corrida / Ciclismo"). bm_iniciar_sessao ganha p_tipo_escolhido
--    para o cliente dizer explicitamente qual das opções escolheu — sem isso o
--    tipo_treino guardado na sessão ficaria ambíguo (não dá para adivinhar a
--    partir do nome do dia, que agora é só "Complemento Cardio").
-- 2) Planos puros de corrida/ciclismo reavaliam a cada 4 semanas, não 12 — o
--    ciclo de ginásio (mesociclo de 4 semanas x 3 = 12) mantém-se "os 3 meses
--    da praxe". Cardio puro muda de fase mais depressa, não faz sentido esperar
--    um trimestre para reagir. (aplicada 2026-08-18)

create or replace function bm_iniciar_sessao(p_plano_id uuid, p_dia_plano text, p_tipo_escolhido text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_cliente_id uuid; v_sessao_id uuid; v_conteudo jsonb; v_dia jsonb; v_tipo text;
begin
  v_cliente_id := meu_pessoa_id();
  select conteudo into v_conteudo from planos
    where id = p_plano_id and cliente_id = v_cliente_id and estado = 'publicado';
  if v_conteudo is null then
    raise exception 'Plano não encontrado ou não publicado para este cliente';
  end if;

  select d into v_dia
    from jsonb_array_elements(coalesce(v_conteudo->'dias', '[]'::jsonb)) d
    where d->>'nome' = p_dia_plano
    limit 1;

  if v_dia->>'tipo' = 'cardio_escolha' then
    if p_tipo_escolhido not in ('corrida', 'ciclismo') then
      raise exception 'Escolhe corrida ou ciclismo para o complemento cardio de hoje';
    end if;
    if not exists (
      select 1 from jsonb_array_elements(coalesce(v_dia->'opcoes', '[]'::jsonb)) o
      where o->>'tipo' = p_tipo_escolhido
    ) then
      raise exception 'Essa opção não está disponível no complemento cardio de hoje';
    end if;
    v_tipo := p_tipo_escolhido;
  else
    v_tipo := v_dia->>'tipo';
  end if;

  insert into sessoes_treino (plano_id, cliente_id, dia_plano, tipo_treino)
  values (p_plano_id, v_cliente_id, p_dia_plano, v_tipo)
  returning id into v_sessao_id;

  perform registar_evento('sessao_iniciada', v_cliente_id, v_cliente_id,
    jsonb_build_object('sessao_id', v_sessao_id, 'plano_id', p_plano_id, 'dia_plano', p_dia_plano, 'tipo_treino', v_tipo));

  return v_sessao_id;
end $$;

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
  v_dia_exibicao text;
  v_dia_subtitulo text;
  v_padroes text[];
  v_padrao text;
  v_exercicios_dia jsonb;
  v_usados text[];
  v_ex record;
  v_plano_id uuid;
  v_planos_anteriores int;
  v_count_elegiveis int;
  v_wod record;
  v_formato_corrida text;
  v_local_corrida text;
  v_desc_corrida text;
  v_so_corrida boolean;
  v_formato_ciclismo text;
  v_local_ciclismo text;
  v_desc_ciclismo text;
  v_so_ciclismo boolean;
  v_perfil_ciclismo text;
  v_categoria_ciclismo text;
  v_opcoes_cardio jsonb;
  v_formatos_semana text[];
  v_perfil_corrida text;
  v_categoria_corrida text;
  v_em_taper boolean;
  v_dias_para_prova int;
  v_reavaliar_semanas int;
  v_principais_usados int;
  v_fase text;
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
  select count(*) into v_planos_anteriores from planos where cliente_id = p_cliente_id;

  v_nivel_rank := case v_aval.nivel when 'iniciante' then 1 when 'intermedio' then 2 else 3 end;
  v_series := v_par.series + (case when v_aval.nivel = 'avancado' then 1 when v_aval.nivel = 'iniciante' then -1 else 0 end);
  v_series := greatest(v_series, 2);
  v_descanso := v_par.descanso_seg + (case when v_aval.nivel = 'iniciante' then 15 else 0 end);
  v_num_ex := greatest(3, least(7, (v_aval.minutos_por_sessao / 10) - 1));

  v_categoria_corrida := bm_classificar_corrida(v_aval.distancia_alvo_km);
  v_perfil_corrida := case
    when v_aval.distancia_alvo_km is null then null
    when v_aval.distancia_alvo_km <= 5 then 'curta'
    when v_aval.distancia_alvo_km <= 15 then 'media'
    when v_aval.distancia_alvo_km <= 42.2 then 'longa'
    else 'ultra'
  end;
  v_dias_para_prova := case when v_aval.data_prova is not null then (v_aval.data_prova - current_date) else null end;
  v_em_taper := (v_dias_para_prova is not null and v_dias_para_prova between 0 and 10);
  v_local_corrida := case
    when v_aval.superficie_corrida = 'trail' then 'trilho'
    when v_aval.local_treino ? 'rua' then 'rua'
    when v_aval.local_treino ? 'ginasio' then 'passadeira (ginásio)'
    else 'rua'
  end;

  v_categoria_ciclismo := bm_classificar_ciclismo(v_aval.distancia_alvo_km);
  v_perfil_ciclismo := case
    when v_aval.distancia_alvo_km is null then null
    when v_aval.distancia_alvo_km <= 30 then 'curta'
    when v_aval.distancia_alvo_km <= 80 then 'media'
    when v_aval.distancia_alvo_km <= 160 then 'longa'
    else 'ultra'
  end;
  v_local_ciclismo := case
    when v_aval.superficie_corrida = 'trail' then 'trilho (BTT/gravel)'
    when v_aval.local_treino ? 'ginasio' then 'rolo (ginásio)'
    else 'estrada'
  end;

  -- Corrida e ciclismo em simultâneo, sem ginásio/casa, é o caso raro de duplo
  -- desporto de resistência — a corrida ganha a semana "pura" (simplificação
  -- deliberada; com ginásio no meio, ambos entram juntos no complemento cardio
  -- mais abaixo, e aí sim o atleta escolhe).
  v_so_corrida := (v_aval.modalidades ? 'corrida')
    and not (v_aval.local_treino ? 'ginasio')
    and not (v_aval.local_treino ? 'casa');
  v_so_ciclismo := (v_aval.modalidades ? 'ciclismo')
    and not (v_aval.modalidades ? 'corrida')
    and not (v_aval.local_treino ? 'ginasio')
    and not (v_aval.local_treino ? 'casa');
  v_reavaliar_semanas := case when (v_so_corrida or v_so_ciclismo) then 4 else 12 end;

  if v_so_corrida then
    if v_perfil_corrida is not null then
      v_formatos_semana := case v_perfil_corrida
        when 'curta' then array['intervalada','continua','fartlek','intervalada','continua','fartlek','intervalada']
        when 'media' then array['continua','intervalada','continua','fartlek','longa','continua','intervalada']
        when 'longa' then array['continua','intervalada','continua','fartlek','longa','continua','longa']
        else array['continua','fartlek','continua','longa','longa','continua','longa']
      end;
    else
      v_formatos_semana := case
        when v_aval.dias_disponiveis <= 2 then array['continua','continua']
        when v_aval.dias_disponiveis = 3 then array['continua','fartlek','continua']
        when v_aval.dias_disponiveis = 4 then array['continua','intervalada','fartlek','continua']
        else array['continua','intervalada','fartlek','continua','intervalada','continua','fartlek']
      end;
    end if;
    v_formatos_semana := v_formatos_semana[1:v_aval.dias_disponiveis];

    if (v_aval.desnivel_corrida = 'alto' or v_aval.superficie_corrida = 'trail') then
      for i in 1 .. array_length(v_formatos_semana, 1) loop
        if v_formatos_semana[i] in ('intervalada','fartlek') then
          v_formatos_semana[i] := 'ladeira';
          exit;
        end if;
      end loop;
    end if;

    for i in 1 .. array_length(v_formatos_semana, 1) loop
      v_formato_corrida := v_formatos_semana[i];
      v_desc_corrida := desc_formato_corrida(v_formato_corrida, v_em_taper);
      v_dias := v_dias || jsonb_build_object(
        'nome', 'Corrida ' || chr(64 + i),
        'nome_exibicao', 'Treino ' || i || coalesce(' — ' || v_categoria_corrida, ' — Corrida'),
        'subtitulo', case v_formato_corrida
          when 'longa' then 'Corrida longa'
          when 'ladeira' then 'Trabalho de subida'
          when 'intervalada' then 'Velocidade'
          when 'fartlek' then 'Ritmo variado'
          else 'Base aeróbica'
        end,
        'tipo', 'corrida', 'formato', v_formato_corrida, 'descricao', v_desc_corrida,
        'local', v_local_corrida, 'duracao_min', v_aval.minutos_por_sessao,
        'aquecimento', '10 min de trote muito leve + mobilidade dinâmica (calf raises, leg swings, skips).',
        'arrefecimento', '5-10 min de caminhada + alongamento estático das pernas.'
      );
    end loop;

  elsif v_so_ciclismo then
    if v_perfil_ciclismo is not null then
      v_formatos_semana := case v_perfil_ciclismo
        when 'curta' then array['intervalada','continua','fartlek','intervalada','continua','fartlek','intervalada']
        when 'media' then array['continua','intervalada','continua','fartlek','longa','continua','intervalada']
        when 'longa' then array['continua','intervalada','continua','fartlek','longa','continua','longa']
        else array['continua','fartlek','continua','longa','longa','continua','longa']
      end;
    else
      v_formatos_semana := case
        when v_aval.dias_disponiveis <= 2 then array['continua','continua']
        when v_aval.dias_disponiveis = 3 then array['continua','fartlek','continua']
        when v_aval.dias_disponiveis = 4 then array['continua','intervalada','fartlek','continua']
        else array['continua','intervalada','fartlek','continua','intervalada','continua','fartlek']
      end;
    end if;
    v_formatos_semana := v_formatos_semana[1:v_aval.dias_disponiveis];

    if (v_aval.desnivel_corrida = 'alto' or v_aval.superficie_corrida = 'trail') then
      for i in 1 .. array_length(v_formatos_semana, 1) loop
        if v_formatos_semana[i] in ('intervalada','fartlek') then
          v_formatos_semana[i] := 'subida';
          exit;
        end if;
      end loop;
    end if;

    for i in 1 .. array_length(v_formatos_semana, 1) loop
      v_formato_ciclismo := v_formatos_semana[i];
      v_desc_ciclismo := desc_formato_ciclismo(v_formato_ciclismo, v_em_taper);
      v_dias := v_dias || jsonb_build_object(
        'nome', 'Ciclismo ' || chr(64 + i),
        'nome_exibicao', 'Treino ' || i || coalesce(' — ' || v_categoria_ciclismo, ' — Ciclismo'),
        'subtitulo', case v_formato_ciclismo
          when 'longa' then 'Saída longa'
          when 'subida' then 'Trabalho de subida'
          when 'intervalada' then 'Séries de potência'
          when 'fartlek' then 'Ritmo variado'
          else 'Base aeróbica'
        end,
        'tipo', 'ciclismo', 'formato', v_formato_ciclismo, 'descricao', v_desc_ciclismo,
        'local', v_local_ciclismo, 'duracao_min', v_aval.minutos_por_sessao,
        'aquecimento', '10-15 min a rotação livre e fácil, subindo cadência gradualmente nos últimos minutos.',
        'arrefecimento', '5-10 min a rotação muito leve + alongamento das pernas fora da bike.'
      );
    end loop;

  else
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

      v_dia_exibicao := 'Treino ' || i;
      v_dia_subtitulo := case
        when v_dia_nome like 'Full Body%' then 'Corpo inteiro'
        when v_dia_nome like 'Upper%' then 'Parte de cima'
        when v_dia_nome like 'Lower%' then 'Parte de baixo'
        when v_dia_nome = 'Push' then 'Empurrar (peito, ombros, tríceps)'
        when v_dia_nome = 'Pull' then 'Puxar (costas, bíceps)'
        when v_dia_nome = 'Legs' then 'Pernas'
        else 'Corpo inteiro'
      end;

      v_exercicios_dia := '[]'::jsonb;
      v_usados := '{}';
      v_principais_usados := 0;

      for j in 1 .. v_num_ex loop
        v_padrao := v_padroes[((j - 1) % array_length(v_padroes, 1)) + 1];

        select count(*) into v_count_elegiveis from exercicios ex
          where ex.padrao = v_padrao::padrao_exercicio
            and (v_aval.equipamento ? ex.equipamento_necessario)
            and not (v_aval.limitacoes ?| ex.contraindicado_se)
            and (case ex.nivel_min when 'iniciante' then 1 when 'intermedio' then 2 else 3 end) <= v_nivel_rank
            and not (ex.id = any(v_usados));
        select * into v_ex from exercicios ex
          where ex.padrao = v_padrao::padrao_exercicio
            and (v_aval.equipamento ? ex.equipamento_necessario)
            and not (v_aval.limitacoes ?| ex.contraindicado_se)
            and (case ex.nivel_min when 'iniciante' then 1 when 'intermedio' then 2 else 3 end) <= v_nivel_rank
            and not (ex.id = any(v_usados))
          order by ex.id
          offset (case when v_count_elegiveis > 0 then v_planos_anteriores % v_count_elegiveis else 0 end)
          limit 1;

        if v_ex.id is null then
          select * into v_ex from exercicios ex
            where ex.padrao = v_padrao::padrao_exercicio
              and (v_aval.equipamento ? ex.equipamento_necessario)
              and not (v_aval.limitacoes ?| ex.contraindicado_se)
              and not (ex.id = any(v_usados))
            order by ex.id limit 1;
        end if;

        if v_ex.id is null then
          select * into v_ex from exercicios ex
            where ex.padrao = v_padrao::padrao_exercicio
              and ex.equipamento_necessario = 'Sem equipamento'
              and not (v_aval.limitacoes ?| ex.contraindicado_se)
              and not (ex.id = any(v_usados))
            order by ex.id limit 1;
        end if;

        if v_ex.id is not null then
          v_usados := array_append(v_usados, v_ex.id);

          if v_padrao in ('squat','hinge','push','pull') and v_principais_usados < 2 then
            v_fase := 'principal';
            v_principais_usados := v_principais_usados + 1;
          elsif v_padrao = 'core' then
            v_fase := 'core';
          else
            v_fase := 'acessorio';
          end if;

          v_exercicios_dia := v_exercicios_dia || jsonb_build_object(
            'exercicio_id', v_ex.id, 'nome', v_ex.nome, 'padrao', v_ex.padrao, 'descricao', v_ex.descricao,
            'series', v_series, 'reps_min', v_par.reps_min, 'reps_max', v_par.reps_max,
            'descanso_seg', v_descanso, 'fase', v_fase
          );
        end if;
      end loop;

      v_dias := v_dias || jsonb_build_object(
        'nome', v_dia_nome, 'nome_exibicao', v_dia_exibicao, 'subtitulo', v_dia_subtitulo,
        'tipo', 'forca', 'exercicios', v_exercicios_dia,
        'aquecimento', '5 min de mobilidade geral + 1-2 séries leves do primeiro exercício, sem chegar perto do RPE alvo.',
        'arrefecimento', '3-5 min de alongamento estático nos grupos trabalhados + respiração controlada.'
      );
    end loop;

    -- Complemento cardio: um único dia, com as opções disponíveis (corrida e/ou
    -- ciclismo) — o atleta escolhe ao vivo qual faz, não o motor antecipadamente.
    v_opcoes_cardio := '[]'::jsonb;

    if v_aval.modalidades ? 'corrida' then
      if v_perfil_corrida is not null then
        v_formato_corrida := case v_perfil_corrida when 'curta' then 'intervalada' when 'ultra' then 'longa' else 'fartlek' end;
      else
        v_formato_corrida := case v_aval.desporto_nivel
          when 'competitivo' then 'intervalada' when 'recreativo' then 'fartlek' else 'continua'
        end;
      end if;
      if (v_aval.desnivel_corrida = 'alto' or v_aval.superficie_corrida = 'trail') and v_formato_corrida in ('intervalada','fartlek') then
        v_formato_corrida := 'ladeira';
      end if;
      v_desc_corrida := desc_formato_corrida(v_formato_corrida, v_em_taper);
      v_opcoes_cardio := v_opcoes_cardio || jsonb_build_object(
        'tipo', 'corrida', 'nome_exibicao', 'Corrida' || coalesce(' (' || v_categoria_corrida || ')', ''),
        'formato', v_formato_corrida, 'descricao', v_desc_corrida,
        'local', v_local_corrida, 'duracao_min', v_aval.minutos_por_sessao,
        'aquecimento', '10 min de trote muito leve + mobilidade dinâmica.',
        'arrefecimento', '5-10 min de caminhada + alongamento estático das pernas.'
      );
    end if;

    if v_aval.modalidades ? 'ciclismo' then
      if v_perfil_ciclismo is not null then
        v_formato_ciclismo := case v_perfil_ciclismo when 'curta' then 'intervalada' when 'ultra' then 'longa' else 'fartlek' end;
      else
        v_formato_ciclismo := case v_aval.desporto_nivel
          when 'competitivo' then 'intervalada' when 'recreativo' then 'fartlek' else 'continua'
        end;
      end if;
      if (v_aval.desnivel_corrida = 'alto' or v_aval.superficie_corrida = 'trail') and v_formato_ciclismo in ('intervalada','fartlek') then
        v_formato_ciclismo := 'subida';
      end if;
      v_desc_ciclismo := desc_formato_ciclismo(v_formato_ciclismo, v_em_taper);
      v_opcoes_cardio := v_opcoes_cardio || jsonb_build_object(
        'tipo', 'ciclismo', 'nome_exibicao', 'Ciclismo' || coalesce(' (' || v_categoria_ciclismo || ')', ''),
        'formato', v_formato_ciclismo, 'descricao', v_desc_ciclismo,
        'local', v_local_ciclismo, 'duracao_min', v_aval.minutos_por_sessao,
        'aquecimento', '10-15 min a rotação livre e fácil.',
        'arrefecimento', '5-10 min a rotação muito leve + alongamento das pernas.'
      );
    end if;

    if jsonb_array_length(v_opcoes_cardio) > 0 then
      v_dias := v_dias || jsonb_build_object(
        'nome', 'Complemento Cardio', 'nome_exibicao', 'Complemento Cardio',
        'subtitulo', 'Escolhes o que fazes hoje',
        'tipo', 'cardio_escolha', 'opcoes', v_opcoes_cardio
      );
    end if;
  end if;

  select * into v_wod from wods_referencia order by id offset (v_planos_anteriores % 7) limit 1;
  v_dias := v_dias || jsonb_build_object(
    'nome', 'Dia de Estímulo (a cada 15 dias)', 'nome_exibicao', 'Dia de Estímulo', 'subtitulo', 'A cada 15 dias',
    'tipo', 'estimulo', 'wod_nome', v_wod.nome, 'wod_formato', v_wod.formato, 'wod_descricao', v_wod.descricao,
    'aquecimento', '5 min de mobilidade geral + 1 ronda leve do formato do dia para sentir o movimento.',
    'arrefecimento', '3-5 min de respiração controlada + alongamento leve.'
  );

  insert into planos (cliente_id, pt_id, avaliacao_id, nome, estado, parametros, conteudo)
  values (
    p_cliente_id, v_pt_id, v_aval.id,
    'Plano ' || v_aval.objetivo::text || ' — ' || to_char(now(), 'DD/MM/YYYY'),
    'rascunho',
    jsonb_build_object(
      'objetivo', v_aval.objetivo, 'nivel', v_aval.nivel,
      'series', coalesce(v_series, 0), 'reps_min', coalesce(v_par.reps_min,0), 'reps_max', coalesce(v_par.reps_max,0),
      'descanso_seg', coalesce(v_descanso,0), 'rpe_alvo', v_par.rpe_alvo, 'progressao', v_par.progressao,
      'dias_disponiveis', v_aval.dias_disponiveis, 'minutos_por_sessao', v_aval.minutos_por_sessao,
      'so_corrida', v_so_corrida, 'so_ciclismo', v_so_ciclismo,
      'categoria_corrida', v_categoria_corrida, 'categoria_ciclismo', v_categoria_ciclismo, 'em_taper', v_em_taper,
      'reavaliar_em', to_char(now() + (v_reavaliar_semanas || ' weeks')::interval, 'YYYY-MM-DD')
    ),
    jsonb_build_object('dias', v_dias)
  ) returning id into v_plano_id;

  perform registar_evento('plano_gerado', v_pt_id, p_cliente_id,
    jsonb_build_object('plano_id', v_plano_id, 'objetivo', v_aval.objetivo, 'so_corrida', v_so_corrida, 'so_ciclismo', v_so_ciclismo));

  return v_plano_id;
end $$;
