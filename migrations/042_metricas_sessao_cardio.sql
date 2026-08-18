-- BEAST MODE — Migração 042: sessões passam a guardar métricas estruturadas de
-- corrida/ciclismo (km, duração, velocidade média/máxima, desnível acumulado, watts)
-- em vez de tudo cair num jsonb de feedback livre — sem isto não há como calcular
-- evolução trimestral real (peso, cargas, tempos, repetições, agora também isto).
-- tipo_treino é capturado no arranque da sessão (snapshot do dia do plano), para o
-- histórico não depender do plano não ter sido regenerado entretanto — o mesmo
-- problema que a academia↔atleta da YTB já ensinou: posse/facto tem de ser guardado,
-- não recalculado a partir de algo que muda. (aplicada 2026-08-18)

alter table sessoes_treino add column tipo_treino text;
alter table sessoes_treino add column km numeric(6,2) check (km >= 0);
alter table sessoes_treino add column duracao_min integer check (duracao_min >= 0);
alter table sessoes_treino add column vel_media_kmh numeric(5,2) check (vel_media_kmh >= 0);
alter table sessoes_treino add column vel_maxima_kmh numeric(5,2) check (vel_maxima_kmh >= 0);
alter table sessoes_treino add column desnivel_acumulado_m integer check (desnivel_acumulado_m >= 0);
alter table sessoes_treino add column watts_medio numeric(5,1) check (watts_medio >= 0);

create or replace function bm_iniciar_sessao(p_plano_id uuid, p_dia_plano text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_cliente_id uuid; v_sessao_id uuid; v_conteudo jsonb; v_tipo text;
begin
  v_cliente_id := meu_pessoa_id();
  select conteudo into v_conteudo from planos
    where id = p_plano_id and cliente_id = v_cliente_id and estado = 'publicado';
  if v_conteudo is null then
    raise exception 'Plano não encontrado ou não publicado para este cliente';
  end if;

  select d->>'tipo' into v_tipo
    from jsonb_array_elements(coalesce(v_conteudo->'dias', '[]'::jsonb)) d
    where d->>'nome' = p_dia_plano
    limit 1;

  insert into sessoes_treino (plano_id, cliente_id, dia_plano, tipo_treino)
  values (p_plano_id, v_cliente_id, p_dia_plano, v_tipo)
  returning id into v_sessao_id;

  perform registar_evento('sessao_iniciada', v_cliente_id, v_cliente_id,
    jsonb_build_object('sessao_id', v_sessao_id, 'plano_id', p_plano_id, 'dia_plano', p_dia_plano, 'tipo_treino', v_tipo));

  return v_sessao_id;
end $$;

drop function if exists bm_concluir_sessao(uuid, jsonb);

create or replace function bm_concluir_sessao(
  p_sessao_id uuid,
  p_feedback jsonb default '{}'::jsonb,
  p_km numeric default null,
  p_duracao_min integer default null,
  p_vel_media_kmh numeric default null,
  p_vel_maxima_kmh numeric default null,
  p_desnivel_acumulado_m integer default null,
  p_watts_medio numeric default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_cliente_id uuid;
begin
  v_cliente_id := meu_pessoa_id();
  if not exists (select 1 from sessoes_treino
                 where id = p_sessao_id and cliente_id = v_cliente_id and concluida_em is null) then
    raise exception 'Sessão não encontrada, não pertence a este cliente, ou já foi concluída';
  end if;

  update sessoes_treino set
    concluida_em = now(),
    feedback = coalesce(p_feedback, '{}'::jsonb),
    km = p_km,
    duracao_min = p_duracao_min,
    vel_media_kmh = p_vel_media_kmh,
    vel_maxima_kmh = p_vel_maxima_kmh,
    desnivel_acumulado_m = p_desnivel_acumulado_m,
    watts_medio = p_watts_medio
  where id = p_sessao_id;

  perform registar_evento('sessao_concluida', v_cliente_id, v_cliente_id,
    jsonb_build_object('sessao_id', p_sessao_id, 'feedback', p_feedback,
      'km', p_km, 'duracao_min', p_duracao_min, 'vel_media_kmh', p_vel_media_kmh,
      'vel_maxima_kmh', p_vel_maxima_kmh, 'desnivel_acumulado_m', p_desnivel_acumulado_m,
      'watts_medio', p_watts_medio));
end $$;

grant execute on function bm_concluir_sessao(uuid, jsonb, numeric, integer, numeric, numeric, integer, numeric) to authenticated;
revoke execute on function bm_concluir_sessao(uuid, jsonb, numeric, integer, numeric, numeric, integer, numeric) from public, anon;

drop function if exists bm_sessoes_cliente(uuid, int);

create or replace function bm_sessoes_cliente(p_cliente_id uuid, p_limite int default 10)
returns table(
  sessao_id uuid, dia_plano text, tipo_treino text, iniciada_em timestamptz, concluida_em timestamptz,
  feedback jsonb, num_series bigint,
  km numeric, duracao_min integer, vel_media_kmh numeric, vel_maxima_kmh numeric,
  desnivel_acumulado_m integer, watts_medio numeric
)
language sql stable security definer set search_path = public as $$
  select s.id, s.dia_plano, s.tipo_treino, s.iniciada_em, s.concluida_em, s.feedback,
    (select count(*) from registos_serie rs where rs.sessao_id = s.id),
    s.km, s.duracao_min, s.vel_media_kmh, s.vel_maxima_kmh, s.desnivel_acumulado_m, s.watts_medio
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
