-- BEAST MODE — Migração 012: corrige o gargalo de Pull/isolamento sem equipamento. (aplicada 2026-08-01)
-- A biblioteca tinha zero exercícios de padrão 'pull' e zero de 'isolamento' com
-- equipamento_necessario = 'Sem equipamento' — por isso o motor falhava ou saltava
-- esses slots em qualquer avaliação só com peso corporal.

insert into exercicios (id, nome, padrao, grupo_muscular, equipamento_necessario, nivel_min, contraindicado_se) values
('ytw_chao', 'Y-T-W no chão', 'pull', null, 'Sem equipamento', 'iniciante', '{Ombro}'),
('remada_toalha_porta', 'Remada com toalha na porta', 'pull', null, 'Sem equipamento', 'iniciante', '{Lombar}'),
('remada_mesa', 'Remada australiana debaixo da mesa', 'pull', null, 'Mesa ou cadeira', 'iniciante', '{Ombro}'),
('puxada_elastico_porta', 'Puxada vertical com elástico na porta', 'pull', null, 'Barra de porta', 'intermedio', '{Ombro}'),
('elevacao_panturrilha', 'Elevação de panturrilha em pé', 'isolamento', 'pernas', 'Sem equipamento', 'iniciante', '{}'),
('triceps_banco', 'Extensão de tríceps no banco/cadeira', 'isolamento', 'triceps', 'Mesa ou cadeira', 'iniciante', '{Ombro}'),
('prancha_ombro_toque', 'Prancha com toque de ombro', 'isolamento', 'ombros', 'Sem equipamento', 'intermedio', '{Ombro,Cervical}');
