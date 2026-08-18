-- BEAST MODE — Migração 045: inscrição direta do atleta, sem convite de PT.
--
-- Até aqui só havia um caminho para um atleta entrar: um PT convidava-o por
-- email (bm_convidar_cliente). Isso já não bate certo com o modelo atual —
-- a app é o treinador, não faz sentido exigir um treinador humano a convidar
-- primeiro. bm_inscrever_atleta cobre o caminho direto: a pessoa autentica-se
-- (magic link, como sempre), inscreve-se sozinha, fica 'pendente' — trancada,
-- sem acesso nenhum — e liga-se automaticamente ao único treinador ativo da
-- plataforma (hoje só há um). A aprovação em si não é nova: bm_admin_confirmar_
-- pagamento já existe e já faz exatamente isto (confirma pagamento, ativa a
-- conta, gera a comissão) — só precisava de uma relação para funcionar, e é
-- isso que esta migração garante que existe desde o primeiro segundo.
-- (aplicada 2026-08-18)

create or replace function bm_inscrever_atleta(p_nome text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text; v_existing uuid; v_pt_casa uuid;
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
    -- Já havia conta (ex: convidada por um PT antes) — reivindica-a, não duplica.
    update pessoas set auth_user_id = auth.uid(), nome = trim(p_nome) where id = v_existing;
    perform registar_evento('conta_reclamada', v_existing, v_existing, jsonb_build_object('nome', trim(p_nome)));
    return v_existing;
  end if;

  select pessoa_id into v_pt_casa from perfis_pt where estado = 'ativo' and perfil_completo order by criado_em limit 1;
  if v_pt_casa is null then
    raise exception 'Sem treinador disponível de momento — contacta a administração';
  end if;

  insert into pessoas (auth_user_id, nome, email, estado)
  values (auth.uid(), trim(p_nome), v_email, 'pendente')
  returning id into v_id;

  insert into relacoes_pt_cliente (pt_id, cliente_id, estado) values (v_pt_casa, v_id, 'ativa');

  perform registar_evento('atleta_inscrito', v_id, v_id,
    jsonb_build_object('nome', trim(p_nome), 'pt_id', v_pt_casa));

  return v_id;
end $$;

grant execute on function bm_inscrever_atleta(text) to authenticated;
revoke execute on function bm_inscrever_atleta(text) from public, anon;
