-- BEAST MODE — Migração 010: periodização (reavaliação 12 semanas + dia de estímulo 15 dias),
-- modalidade corrida, e biblioteca mínima de formatos sem carga em casa. (aplicada 2026-08-01)

alter table avaliacoes add column pratica_desporto boolean not null default false;
alter table avaliacoes add column desporto_nivel text check (desporto_nivel in ('nao_pratica','iniciante','recreativo','competitivo'));
alter table avaliacoes add column modalidades jsonb not null default '[]'::jsonb;
alter table avaliacoes add column local_treino jsonb not null default '[]'::jsonb;

create table wods_referencia (
  id text primary key,
  nome text not null,
  formato text not null,
  descricao text not null,
  equipamento_necessario text not null default 'Sem equipamento'
);
alter table wods_referencia enable row level security;
create policy sel_wods on wods_referencia for select using (true);

insert into wods_referencia (id, nome, formato, descricao, equipamento_necessario) values
('tabata_generico', 'Tabata', 'tabata', '8 rondas de 20s trabalho / 10s descanso (4 min). Escolhe um exercício: burpees, agachamento salto, mountain climbers ou prancha alta/baixa.', 'Sem equipamento'),
('amrap7_burpees', 'AMRAP 7 — Burpees', 'amrap', '7 minutos, o máximo de burpees possível, mantendo boa forma até ao fim.', 'Sem equipamento'),
('murph', 'Murph', 'for_time', 'Para tempo: 1,6 km de corrida, 100 flexões de tração (ou remada em porta/toalha), 200 flexões de braços, 300 agachamentos, 1,6 km de corrida. Pode partir-se em blocos (ex: 20 rondas de 5-10-15) se for a primeira vez.', 'Sem equipamento'),
('couplet_15_9_7', 'Couplet 15-9-7', 'for_time', 'Para tempo, esquema decrescente 15-9-7: burpees + agachamento com salto. Ex: 15 burpees + 15 agachamento salto, depois 9+9, depois 7+7.', 'Sem equipamento');

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
  p_local_treino jsonb default '[]'::jsonb
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
    pratica_desporto, desporto_nivel, modalidades, local_treino
  ) values (
    p_cliente_id, v_pt_id, p_objetivo, p_nivel, p_dias_disponiveis, p_minutos_por_sessao,
    coalesce(p_equipamento, '[]'::jsonb), coalesce(p_limitacoes, '[]'::jsonb), p_notas_pt, p_peso_objetivo_kg,
    p_pratica_desporto, p_desporto_nivel, coalesce(p_modalidades, '[]'::jsonb), coalesce(p_local_treino, '[]'::jsonb)
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

drop function if exists bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric);
revoke execute on function bm_criar_avaliacao(uuid, objetivo_treino, nivel_treino, smallint, smallint, jsonb, jsonb, text, numeric, boolean, text, jsonb, jsonb) from anon, public;
