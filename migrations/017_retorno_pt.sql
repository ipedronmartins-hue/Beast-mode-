-- BEAST MODE — Migração 017: retorno do PT (comentários a sessões) — módulo 6 do MVP (aplicada 2026-08-02)

create or replace function bm_comentar_sessao(p_sessao_id uuid, p_texto text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid; v_cliente_id uuid; v_comentario_id uuid;
begin
  v_pt_id := meu_pessoa_id();
  if v_pt_id is null or not exists (select 1 from perfis_pt where pessoa_id = v_pt_id) then
    raise exception 'Só treinadores podem comentar sessões';
  end if;
  if p_texto is null or trim(p_texto) = '' then
    raise exception 'Comentário vazio';
  end if;

  select cliente_id into v_cliente_id from sessoes_treino where id = p_sessao_id;
  if v_cliente_id is null then
    raise exception 'Sessão não encontrada';
  end if;
  if not exists (select 1 from relacoes_pt_cliente
                 where pt_id = v_pt_id and cliente_id = v_cliente_id and estado = 'ativa') then
    raise exception 'Sem relação ativa com este atleta';
  end if;

  insert into comentarios_pt (sessao_id, pt_id, texto)
  values (p_sessao_id, v_pt_id, trim(p_texto))
  returning id into v_comentario_id;

  perform registar_evento('sessao_comentada', v_pt_id, v_cliente_id,
    jsonb_build_object('sessao_id', p_sessao_id, 'comentario_id', v_comentario_id));

  return v_comentario_id;
end $$;

grant execute on function bm_comentar_sessao(uuid, text) to authenticated;
revoke execute on function bm_comentar_sessao(uuid, text) from public, anon;
