-- BEAST MODE — Migração 006: motor de prescrição determinístico (aplicada 2026-08-01)
-- Biblioteca de exercícios + parâmetros por objetivo + função geradora.

create type padrao_exercicio as enum ('push','pull','squat','hinge','core','isolamento');

create table exercicios (
  id text primary key,
  nome text not null,
  padrao padrao_exercicio not null,
  grupo_muscular text,
  equipamento_necessario text not null,
  nivel_min nivel_treino not null default 'iniciante',
  contraindicado_se text[] not null default '{}'
);

create table motor_parametros_objetivo (
  objetivo objetivo_treino primary key,
  series smallint not null,
  reps_min smallint not null,
  reps_max smallint not null,
  descanso_seg smallint not null,
  rpe_alvo numeric(3,1) not null,
  progressao text not null
);

alter table exercicios enable row level security;
alter table motor_parametros_objetivo enable row level security;
create policy sel_exercicios on exercicios for select using (true);
create policy sel_motor_parametros on motor_parametros_objetivo for select using (true);

insert into exercicios (id, nome, padrao, grupo_muscular, equipamento_necessario, nivel_min, contraindicado_se) values
('flexoes','Flexões de braços','push',null,'Sem equipamento','iniciante','{Ombro}'),
('agachamento_livre','Agachamento livre','squat',null,'Sem equipamento','iniciante','{Joelho}'),
('prancha','Prancha','core',null,'Sem equipamento','iniciante','{Lombar}'),
('ponte_gluteos','Ponte de glúteos','hinge',null,'Sem equipamento','iniciante','{}'),
('prancha_lateral','Prancha lateral','core',null,'Sem equipamento','intermedio','{Ombro}'),
('elevacao_pernas','Elevação de pernas','core',null,'Sem equipamento','intermedio','{Lombar}'),
('mountain_climbers','Mountain climbers','core',null,'Sem equipamento','intermedio','{Ombro,Cervical}'),
('afundo_peso_corporal','Afundo (peso do corpo)','squat',null,'Sem equipamento','iniciante','{Joelho,Anca}'),
('remada_halteres','Remada com halteres','pull',null,'Halteres','iniciante','{Lombar}'),
('desenvolvimento_halteres','Desenvolvimento com halteres','push',null,'Halteres','intermedio','{Ombro}'),
('afundo_halteres','Afundo com halteres','squat',null,'Halteres','intermedio','{Joelho,Anca}'),
('rosca_biceps','Rosca de bíceps com halteres','isolamento','biceps','Halteres','iniciante','{}'),
('extensao_triceps','Extensão de tríceps com halteres','isolamento','triceps','Halteres','iniciante','{Ombro}'),
('elevacao_lateral','Elevação lateral com halteres','isolamento','ombros','Halteres','intermedio','{Ombro}'),
('peso_morto_romeno','Peso morto romeno com barra','hinge',null,'Barra e discos','avancado','{Lombar}'),
('supino_barra','Supino com barra','push',null,'Barra e discos','intermedio','{Ombro}'),
('remada_curvada','Remada curvada com barra','pull',null,'Barra e discos','avancado','{Lombar}'),
('agachamento_barra','Agachamento com barra','squat',null,'Barra e discos','avancado','{Joelho,Lombar}'),
('leg_press','Leg press','squat',null,'Máquinas','iniciante','{Joelho}'),
('puxada_alta','Puxada alta','pull',null,'Máquinas','iniciante','{Ombro}'),
('peck_deck','Peck deck','push',null,'Máquinas','iniciante','{Ombro}'),
('cadeira_extensora','Cadeira extensora','isolamento','pernas','Máquinas','iniciante','{Joelho}'),
('mesa_flexora','Mesa flexora','isolamento','pernas','Máquinas','iniciante','{Joelho}'),
('remada_elastico','Remada com elástico','pull',null,'Elásticos','iniciante','{Lombar}'),
('elevacao_lateral_elastico','Elevação lateral com elástico','isolamento','ombros','Elásticos','iniciante','{Ombro}'),
('agachamento_kettlebell','Agachamento com kettlebell (goblet)','squat',null,'Kettlebell','intermedio','{Joelho}'),
('swing_kettlebell','Swing com kettlebell','hinge',null,'Kettlebell','avancado','{Lombar,Ombro}');

insert into motor_parametros_objetivo (objetivo, series, reps_min, reps_max, descanso_seg, rpe_alvo, progressao) values
('hipertrofia', 3, 8, 12, 75, 7.5, 'dupla_progressao'),
('forca', 4, 3, 6, 150, 8.5, 'carga_linear'),
('perda_peso', 3, 12, 15, 40, 7.0, 'densidade'),
('definicao', 3, 10, 15, 50, 7.5, 'dupla_progressao'),
('saude_geral', 2, 10, 15, 60, 6.5, 'manutencao'),
('manutencao', 2, 10, 12, 60, 6.0, 'manutencao'),
('reabilitacao', 2, 12, 15, 75, 5.5, 'gradual'),
('performance', 4, 5, 8, 105, 8.0, 'ondulada');

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
          'exercicio_id', v_ex.id, 'nome', v_ex.nome, 'padrao', v_ex.padrao,
          'series', v_series, 'reps_min', v_par.reps_min, 'reps_max', v_par.reps_max,
          'descanso_seg', v_descanso
        );
      end if;
    end loop;

    v_dias := v_dias || jsonb_build_object('nome', v_dia_nome, 'exercicios', v_exercicios_dia);
  end loop;

  insert into planos (cliente_id, pt_id, avaliacao_id, nome, estado, parametros, conteudo)
  values (
    p_cliente_id, v_pt_id, v_aval.id,
    'Plano ' || v_aval.objetivo::text || ' — ' || to_char(now(), 'DD/MM/YYYY'),
    'rascunho',
    jsonb_build_object(
      'objetivo', v_aval.objetivo, 'nivel', v_aval.nivel, 'series', v_series,
      'reps_min', v_par.reps_min, 'reps_max', v_par.reps_max, 'descanso_seg', v_descanso,
      'rpe_alvo', v_par.rpe_alvo, 'progressao', v_par.progressao,
      'dias_disponiveis', v_aval.dias_disponiveis, 'minutos_por_sessao', v_aval.minutos_por_sessao
    ),
    jsonb_build_object('dias', v_dias)
  ) returning id into v_plano_id;

  perform registar_evento('plano_gerado', v_pt_id, p_cliente_id,
    jsonb_build_object('plano_id', v_plano_id, 'objetivo', v_aval.objetivo));

  return v_plano_id;
end $$;

grant execute on function bm_gerar_plano(uuid) to authenticated;
revoke execute on function bm_gerar_plano(uuid) from public, anon;

create or replace function bm_publicar_plano(p_plano_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid; v_plano record;
begin
  v_pt_id := meu_pessoa_id();
  select * into v_plano from planos where id = p_plano_id and pt_id = v_pt_id;
  if v_plano.id is null then
    raise exception 'Plano não encontrado ou não pertence a este treinador';
  end if;
  if v_plano.estado = 'publicado' then
    raise exception 'Plano já está publicado';
  end if;

  update planos set estado = 'arquivado'
    where cliente_id = v_plano.cliente_id and estado = 'publicado';

  update planos set estado = 'publicado', publicado_em = now() where id = p_plano_id;

  perform registar_evento('plano_publicado', v_pt_id, v_plano.cliente_id,
    jsonb_build_object('plano_id', p_plano_id));
end $$;

grant execute on function bm_publicar_plano(uuid) to authenticated;
revoke execute on function bm_publicar_plano(uuid) from public, anon;
