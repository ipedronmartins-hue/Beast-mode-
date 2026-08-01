-- BEAST MODE — Migração 014: descrições técnicas, mais exercícios, mais WODs, guia de corrida. (aplicada 2026-08-01)

alter table exercicios add column descricao text;

update exercicios set descricao = d.descricao from (values
  ('flexoes', 'Em prancha, descer o peito quase a tocar no chão com cotovelos a ~45° do tronco, subir em bloco mantendo o core ativo.'),
  ('agachamento_livre', 'Pés à largura dos ombros, descer flectindo anca e joelho até às coxas ficarem paralelas ao chão, subir mantendo os calcanhares no chão.'),
  ('prancha', 'Apoio em antebraços e pontas dos pés, corpo em linha reta da cabeça aos calcanhares, core contraído.'),
  ('ponte_gluteos', 'Deitado, pés apoiados, elevar a anca contraindo os glúteos no topo sem hiperextender a lombar.'),
  ('prancha_lateral', 'Apoio lateral num antebraço, corpo em linha reta, anca elevada e estável.'),
  ('elevacao_pernas', 'Deitado, lombar encostada ao chão, elevar as pernas estendidas até 90° controlando a descida.'),
  ('mountain_climbers', 'Posição de prancha alta, alternar joelhos em direção ao peito a ritmo rápido mantendo a anca estável.'),
  ('afundo_peso_corporal', 'Passo à frente, descer o joelho de trás quase a tocar o chão, ambos os joelhos a 90°, voltar à posição inicial.'),
  ('remada_halteres', 'Tronco inclinado ~45°, puxar o halter em direção à anca retraindo a escápula no topo.'),
  ('desenvolvimento_halteres', 'Halteres à altura dos ombros, empurrar verticalmente até extensão total dos braços sem arquear a lombar.'),
  ('afundo_halteres', 'Halteres nas mãos, passo à frente, descer até 90° em ambos os joelhos, subir controlado.'),
  ('rosca_biceps', 'Cotovelos fixos junto ao tronco, flectir o antebraço elevando o halter até à contração máxima do bícep.'),
  ('extensao_triceps', 'Halter acima da cabeça, flectir só o cotovelo baixando atrás da nuca, estender de volta.'),
  ('elevacao_lateral', 'Halteres ao lado do corpo, elevar lateralmente até à altura dos ombros com ligeira flexão de cotovelo.'),
  ('peso_morto_romeno', 'Joelhos com flexão ligeira e fixa, inclinar a bacia para trás descendo a carga junto às pernas até sentir os isquiotibiais.'),
  ('supino_barra', 'Deitado no banco, descer a barra ao peitoral médio com cotovelos a ~45°, empurrar até extensão total.'),
  ('remada_curvada', 'Tronco inclinado, puxar a barra em direção ao umbigo retraindo as escápulas.'),
  ('agachamento_barra', 'Barra no trapézio, descer até as coxas quebrarem o paralelo, pés bem plantados, subir em condução.'),
  ('leg_press', 'Pés à largura dos ombros na plataforma, descer controlado até 90° de flexão do joelho, empurrar sem travar a articulação.'),
  ('puxada_alta', 'Sentado, puxar a barra até ao peitoral superior mantendo o peito aberto e escápulas deprimidas.'),
  ('peck_deck', 'Sentado, cotovelos ligeiramente flectidos, aproximar os braços à frente do peito num arco controlado.'),
  ('cadeira_extensora', 'Sentado, estender o joelho até à extensão quase total, controlar a descida.'),
  ('mesa_flexora', 'Deitado de frente, flectir o joelho puxando o calcanhar em direção ao glúteo.'),
  ('remada_elastico', 'Elástico fixo à frente, puxar em direção à anca retraindo as escápulas.'),
  ('elevacao_lateral_elastico', 'Elástico sob os pés, elevar lateralmente até à altura dos ombros.'),
  ('agachamento_kettlebell', 'Kettlebell junto ao peito (goblet), descer mantendo o tronco ereto até às coxas paralelas.'),
  ('swing_kettlebell', 'Movimento de anca (não agachamento), balançar o kettlebell à altura do peito usando a explosão da anca.'),
  ('ytw_chao', 'Deitado de frente, elevar os braços em Y, depois T, depois W, contraindo a zona escapular em cada posição.'),
  ('remada_toalha_porta', 'Toalha presa numa porta fechada e segura, inclinar o corpo para trás e puxar em direção ao peito.'),
  ('remada_mesa', 'Deitado sob uma mesa firme, segurar a borda e puxar o peito em direção à mesa mantendo o corpo reto.'),
  ('puxada_elastico_porta', 'Elástico preso no topo de uma porta, puxar verticalmente para baixo mantendo o tronco estável.'),
  ('elevacao_panturrilha', 'Em pé, elevar os calcanhares o máximo possível, controlar a descida até alongamento total.'),
  ('triceps_banco', 'Mãos apoiadas na borda do banco/cadeira, descer o corpo flectindo os cotovelos a 90°, empurrar de volta.'),
  ('prancha_ombro_toque', 'Em prancha alta, tocar alternadamente o ombro oposto com a mão sem rodar a anca.')
) as d(id, descricao) where exercicios.id = d.id;

insert into exercicios (id, nome, padrao, grupo_muscular, equipamento_necessario, nivel_min, contraindicado_se, descricao) values
('aberturas_halteres', 'Aberturas com halteres (flyes)', 'isolamento', 'peito', 'Halteres', 'intermedio', '{Ombro}',
  'Deitado, braços ligeiramente flectidos, abrir lateralmente em arco controlado e voltar a juntar sobre o peito.'),
('dips_cadeira', 'Dips em cadeira/banco', 'push', null, 'Mesa ou cadeira', 'intermedio', '{Ombro}',
  'Mãos na borda da cadeira, pernas estendidas à frente, flectir os cotovelos a 90° e empurrar de volta.'),
('pull_up_barra', 'Elevações na barra (pull-up)', 'pull', null, 'Barra de porta', 'avancado', '{Ombro,Cervical}',
  'Suspenso na barra, puxar o peito em direção à barra até o queixo passar a linha da barra, descer controlado.'),
('face_pull_elastico', 'Face pull com elástico', 'pull', null, 'Elásticos', 'intermedio', '{Ombro,Cervical}',
  'Elástico à altura da cara, puxar em direção aos olhos rodando externamente os ombros no final.'),
('hip_thrust_carga', 'Hip thrust com carga', 'hinge', null, 'Halteres', 'intermedio', '{Lombar}',
  'Escápulas apoiadas num banco, carga sobre a bacia, elevar até ao alinhamento do tronco contraindo os glúteos no topo.');

insert into wods_referencia (id, nome, formato, descricao, equipamento_necessario) values
('cindy', 'Cindy', 'amrap', '20 minutos, o máximo de rondas possível: 5 elevações na barra (ou remada australiana), 10 flexões de braços, 15 agachamentos livres.', 'Sem equipamento'),
('annie', 'Annie', 'for_time', 'Para tempo, esquema decrescente 50-40-30-20-10: saltos de tesoura (ou corda) + abdominais.', 'Sem equipamento'),
('core_metcon_express', 'Core & Metcon Express', 'emom', '12 minutos (4 rondas), a cada minuto: min 1 — 15 burpees; min 2 — 20 abdominais V-up; min 3 — 45s de prancha isométrica.', 'Sem equipamento');
