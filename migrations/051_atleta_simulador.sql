-- BEAST MODE — Migração 051: atleta-simulador — uma conta de teste permanente, sem
-- email real (nunca vai fazer login, é só para o PT avaliar/gerar planos contra ela e
-- ver o que o motor prescreve de verdade), estado ativo desde já (sem fricção de
-- pagamento), consentimento pré-concedido, ligada ao Ivo como PT. Aparece na aba
-- Atletas normal — reaproveita 100% das ferramentas já testadas (Avaliar, Gerar
-- plano, Ver como atleta), sem duplicar lógica do motor nem construir simulador à parte.
-- (aplicada 2026-08-21)

do $$
declare v_pt_id uuid := 'cde0c66a-0258-4067-b559-64da72c3623d'; v_id uuid;
begin
  insert into pessoas (nome, email, estado)
  values ('🧪 Simulador (teste)', 'simulador-interno@beastmode.teste', 'ativo')
  returning id into v_id;

  insert into relacoes_pt_cliente (pt_id, cliente_id, estado) values (v_pt_id, v_id, 'ativa');
  insert into consentimentos (pessoa_id, tipo, concedido) values (v_id, 'dados_saude', true);
  insert into consentimentos (pessoa_id, tipo, concedido) values (v_id, 'medicoes_corporais', true);

  perform registar_evento('atleta_simulador_criado', v_pt_id, v_id, jsonb_build_object('motivo', 'testar prescrições'));
end $$;
