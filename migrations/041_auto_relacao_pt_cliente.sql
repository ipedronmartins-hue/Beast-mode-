-- BEAST MODE — Migração 041: permite que um PT seja cliente de si próprio — a app
-- deixa de obrigar sempre a um treinador humano no meio; um PT a prescrever-se a si
-- mesmo é a versão mais simples do modelo sem intermediário. Reflete a direção real
-- do produto, não é workaround. (aplicada 2026-08-18)

create or replace function bm_convidar_cliente(p_email text, p_nome text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid; v_cliente_id uuid; v_email text; v_estado_pt estado_conta;
begin
  v_pt_id := meu_pessoa_id();
  select estado into v_estado_pt from perfis_pt where pessoa_id = v_pt_id;
  if v_estado_pt is null then
    raise exception 'Só treinadores podem convidar atletas';
  end if;
  if v_estado_pt <> 'ativo' then
    raise exception 'A tua conta de treinador está % — contacta a administração', v_estado_pt;
  end if;

  v_email := lower(trim(p_email));
  if v_email is null or v_email = '' or v_email not like '%@%' then
    raise exception 'Email inválido';
  end if;

  select id into v_cliente_id from pessoas where email = v_email;
  if v_cliente_id is null then
    insert into pessoas (nome, email, estado)
    values (coalesce(nullif(trim(p_nome), ''), split_part(v_email, '@', 1)), v_email, 'pendente')
    returning id into v_cliente_id;
  end if;

  if exists (select 1 from relacoes_pt_cliente
             where pt_id = v_pt_id and cliente_id = v_cliente_id and estado = 'ativa') then
    raise exception 'Este cliente já está associado a ti';
  end if;

  insert into relacoes_pt_cliente (pt_id, cliente_id, estado)
  values (v_pt_id, v_cliente_id, 'ativa');

  perform registar_evento('cliente_convidado', v_pt_id, v_cliente_id,
    jsonb_build_object('email', v_email, 'auto_relacao', v_cliente_id = v_pt_id));

  return v_cliente_id;
end $$;

-- Bootstrap: liga o fundador a si próprio como cliente. Conta já existe e já está
-- ativa (é o dono da plataforma) — não passa pelo fluxo de convite/pagamento.
do $$
declare v_id uuid; v_ja_existe boolean;
begin
  select id into v_id from pessoas where email = 'ipedronmartins@gmail.com';
  if v_id is null then
    raise notice 'Conta do fundador não encontrada — skip bootstrap';
    return;
  end if;
  select exists(
    select 1 from relacoes_pt_cliente where pt_id = v_id and cliente_id = v_id and estado = 'ativa'
  ) into v_ja_existe;
  if not v_ja_existe then
    insert into relacoes_pt_cliente (pt_id, cliente_id, estado) values (v_id, v_id, 'ativa');
    perform registar_evento('cliente_convidado', v_id, v_id,
      jsonb_build_object('email', 'ipedronmartins@gmail.com', 'auto_relacao', true, 'nota', 'bootstrap fundador'));
  end if;
end $$;
