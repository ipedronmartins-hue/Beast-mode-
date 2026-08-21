-- BEAST MODE — Migração 047: métricas que qualquer app/computador de ciclismo mostra
-- hoje — cadência, FC média (autodeclarada, sem sensor), calorias. Sem inventar dados
-- que exigem equipamento (potência já existia, watts_medio; FTP/TSS/IF ficam de fora,
-- exigem um medidor de potência real e um teste FTP que não temos como validar).
-- Velocidade média passa a calcular-se sozinha quando não é escrita à mão. (aplicada 2026-08-21)

alter table sessoes_treino add column cadencia_media_rpm numeric(5,1);
alter table sessoes_treino add column fc_media_bpm smallint;
alter table sessoes_treino add column calorias integer;

create or replace function bm_concluir_sessao(
  p_sessao_id uuid, p_feedback jsonb default '{}'::jsonb,
  p_km numeric default null, p_duracao_min integer default null,
  p_vel_media_kmh numeric default null, p_vel_maxima_kmh numeric default null,
  p_desnivel_acumulado_m integer default null, p_watts_medio numeric default null,
  p_cadencia_media_rpm numeric default null, p_fc_media_bpm smallint default null,
  p_calorias integer default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_cliente_id uuid; v_vel_media numeric;
begin
  v_cliente_id := meu_pessoa_id();
  if not exists (select 1 from sessoes_treino
                 where id = p_sessao_id and cliente_id = v_cliente_id and concluida_em is null) then
    raise exception 'Sessão não encontrada, não pertence a este cliente, ou já foi concluída';
  end if;

  v_vel_media := coalesce(p_vel_media_kmh,
    case when p_km is not null and p_duracao_min is not null and p_duracao_min > 0
      then round(p_km / (p_duracao_min / 60.0), 1)
    end);

  update sessoes_treino set
    concluida_em = now(),
    feedback = coalesce(p_feedback, '{}'::jsonb),
    km = p_km,
    duracao_min = p_duracao_min,
    vel_media_kmh = v_vel_media,
    vel_maxima_kmh = p_vel_maxima_kmh,
    desnivel_acumulado_m = p_desnivel_acumulado_m,
    watts_medio = p_watts_medio,
    cadencia_media_rpm = p_cadencia_media_rpm,
    fc_media_bpm = p_fc_media_bpm,
    calorias = p_calorias
  where id = p_sessao_id;

  perform registar_evento('sessao_concluida', v_cliente_id, v_cliente_id,
    jsonb_build_object('sessao_id', p_sessao_id, 'feedback', p_feedback,
      'km', p_km, 'duracao_min', p_duracao_min, 'vel_media_kmh', v_vel_media,
      'vel_maxima_kmh', p_vel_maxima_kmh, 'desnivel_acumulado_m', p_desnivel_acumulado_m,
      'watts_medio', p_watts_medio, 'cadencia_media_rpm', p_cadencia_media_rpm,
      'fc_media_bpm', p_fc_media_bpm, 'calorias', p_calorias));
end $$;
