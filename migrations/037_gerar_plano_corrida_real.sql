-- BEAST MODE — Migração 037: bm_gerar_plano usa distância-alvo/superfície/desnível/
-- data de prova para gerar semanas de corrida a sério (longa, ladeira, taper), em vez
-- de só rodar entre 3 formatos fixos. Sem distância definida, mantém o comportamento
-- anterior (retrocompatível). (aplicada 2026-08-11)

create or replace function desc_formato_corrida(p_formato text, p_taper boolean) returns text
language plpgsql set search_path = public as $$
declare v_base text;
begin
  v_base := case p_formato
    when 'intervalada' then 'Séries de VO2 máx: 8-10x 1 min a ritmo máximo sustentável, recuperação de 1 min entre séries.'
    when 'fartlek' then 'Alternância contínua: 10x (1 min rápido + 1 min lento), sem parar.'
    when 'longa' then 'Corrida longa a ritmo fácil e conversacional — o objetivo é tempo em pé, aumenta a duração 5-10% por semana.'
    when 'ladeira' then 'Repetições em subida: 6-8x 60-90s a esforço forte a subir, descer a trotar como recuperação — força específica para desnível.'
    else 'Ritmo contínuo e conversacional (zona 2), foco em construir base aeróbica, não velocidade.'
  end;
  if p_taper then
    v_base := v_base || ' Semana de taper — reduz o volume em ~40%, mantém alguma intensidade, não acumules fadiga nova.';
  end if;
  return v_base;
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
  v_formatos_semana text[];
  v_perfil_corrida text;
  v_categoria_corrida text;
  v_em_taper boolean;
  v_dias_para_prova int;
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

  v_so_corrida := (v_aval.modalidades ? 'corrida')
    and not (v_aval.local_treino ? 'ginasio')
    and not (v_aval.local_treino ? 'casa');

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
        'local', v_local_corrida, 'duracao_min', v_aval.minutos_por_sessao
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
          v_exercicios_dia := v_exercicios_dia || jsonb_build_object(
            'exercicio_id', v_ex.id, 'nome', v_ex.nome, 'padrao', v_ex.padrao, 'descricao', v_ex.descricao,
            'series', v_series, 'reps_min', v_par.reps_min, 'reps_max', v_par.reps_max,
            'descanso_seg', v_descanso
          );
        end if;
      end loop;

      v_dias := v_dias || jsonb_build_object(
        'nome', v_dia_nome, 'nome_exibicao', v_dia_exibicao, 'subtitulo', v_dia_subtitulo,
        'tipo', 'forca', 'exercicios', v_exercicios_dia
      );
    end loop;

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
      v_dias := v_dias || jsonb_build_object(
        'nome', 'Corrida', 'nome_exibicao', 'Corrida' || coalesce(' (' || v_categoria_corrida || ')', ''),
        'subtitulo', 'Complemento cardio',
        'tipo', 'corrida', 'formato', v_formato_corrida, 'descricao', v_desc_corrida,
        'local', v_local_corrida, 'duracao_min', v_aval.minutos_por_sessao
      );
    end if;
  end if;

  select * into v_wod from wods_referencia order by id offset (v_planos_anteriores % 7) limit 1;
  v_dias := v_dias || jsonb_build_object(
    'nome', 'Dia de Estímulo (a cada 15 dias)', 'nome_exibicao', 'Dia de Estímulo', 'subtitulo', 'A cada 15 dias',
    'tipo', 'estimulo', 'wod_nome', v_wod.nome, 'wod_formato', v_wod.formato, 'wod_descricao', v_wod.descricao
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
      'so_corrida', v_so_corrida,
      'categoria_corrida', v_categoria_corrida, 'em_taper', v_em_taper,
      'reavaliar_em', to_char(now() + interval '12 weeks', 'YYYY-MM-DD')
    ),
    jsonb_build_object('dias', v_dias)
  ) returning id into v_plano_id;

  perform registar_evento('plano_gerado', v_pt_id, p_cliente_id,
    jsonb_build_object('plano_id', v_plano_id, 'objetivo', v_aval.objetivo, 'so_corrida', v_so_corrida));

  return v_plano_id;
end $$;
