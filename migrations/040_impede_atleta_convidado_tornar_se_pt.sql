-- BEAST MODE — Migração 040: um atleta já convidado por email conseguia marcar
-- "Sou Personal Trainer" no ecrã de primeira entrada e tornar-se PT por engano —
-- foi o que aconteceu ao Barbosa. bm_criar_pessoa nunca distinguia "conta nova" de
-- "a reivindicar um convite de atleta que já existe com uma relação ativa".
-- (aplicada 2026-08-12)

-- 1) Corrige o Barbosa: remove o perfil de PT que nunca devia ter existido.
delete from perfis_pt where pessoa_id = 'fd21ad2e-0b0d-471d-8855-51fc8ac454cb';

-- 2) Corrige a causa: quem está a reivindicar um convite de atleta já existente
-- (linha pendente sem auth_user_id, com relação ativa como cliente de algum PT)
-- nunca pode tornar-se PT nesse momento, seja qual for o valor de p_como_pt.
create or replace function bm_criar_pessoa(p_nome text, p_como_pt boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text; v_existing uuid; v_ja_e_atleta_convidado boolean;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  select email into v_email from auth.users where id = auth.uid();

  select id into v_id from pessoas where auth_user_id = auth.uid();
  if v_id is not null then
    return v_id; -- chamada duplicada, idempotente
  end if;

  select id into v_existing from pessoas where email = v_email and auth_user_id is null;
  if v_existing is not null then
    v_ja_e_atleta_convidado := exists (
      select 1 from relacoes_pt_cliente where cliente_id = v_existing and estado = 'ativa'
    );

    update pessoas set auth_user_id = auth.uid(), nome = trim(p_nome)
      where id = v_existing;

    if p_como_pt and v_ja_e_atleta_convidado then
      raise exception 'Esta conta já foi convidada como atleta por um treinador — não pode também ser conta de treinador. Contacta a administração se isto estiver errado.';
    end if;

    if p_como_pt and not exists (select 1 from perfis_pt where pessoa_id = v_existing) then
      insert into perfis_pt (pessoa_id) values (v_existing);
    end if;
    perform registar_evento('conta_reclamada', v_existing, v_existing, jsonb_build_object('nome', trim(p_nome)));
    return v_existing;
  end if;

  insert into pessoas (auth_user_id, nome, email)
  values (auth.uid(), trim(p_nome), v_email)
  returning id into v_id;
  if p_como_pt then
    insert into perfis_pt (pessoa_id) values (v_id);
  end if;
  perform registar_evento(
    case when p_como_pt then 'pt_registado' else 'pessoa_registada' end,
    v_id, v_id, jsonb_build_object('nome', trim(p_nome)));
  return v_id;
end $$;
