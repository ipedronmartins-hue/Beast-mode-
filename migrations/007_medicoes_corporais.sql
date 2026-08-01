-- BEAST MODE — Migração 007: medições corporais + peso objetivo (aplicada 2026-08-01)

alter table avaliacoes add column peso_objetivo_kg numeric(5,2);

create or replace function bm_registar_medicoes(p_cliente_id uuid, p_medicoes jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_autor uuid;
  v_eh_pt boolean := false;
  v_chave text;
  v_valor numeric;
  v_tipos_validos text[] := array['peso_kg','altura_cm','cintura_cm','anca_cm','peito_cm','braco_cm','coxa_cm','gordura_pct','massa_muscular_kg'];
  v_count int := 0;
begin
  v_autor := meu_pessoa_id();
  if v_autor is null then
    raise exception 'Não autenticado';
  end if;

  if v_autor <> p_cliente_id then
    if not exists (select 1 from perfis_pt where pessoa_id = v_autor) then
      raise exception 'Sem permissão para registar medições deste cliente';
    end if;
    if not exists (select 1 from relacoes_pt_cliente
                   where pt_id = v_autor and cliente_id = p_cliente_id and estado = 'ativa') then
      raise exception 'Sem relação ativa com este cliente';
    end if;
    v_eh_pt := true;
  end if;

  if not tem_consentimento(p_cliente_id, 'medicoes_corporais') then
    raise exception 'Cliente ainda não deu consentimento para medições corporais';
  end if;

  for v_chave, v_valor in select key, value::numeric from jsonb_each_text(p_medicoes) loop
    if v_chave = any(v_tipos_validos) and v_valor is not null and v_valor > 0 then
      insert into medicoes_corporais (cliente_id, tipo, valor, registado_por)
      values (p_cliente_id, v_chave, v_valor, v_autor);
      v_count := v_count + 1;
    end if;
  end loop;

  if v_count > 0 then
    perform registar_evento('medicoes_registadas', v_autor, p_cliente_id,
      jsonb_build_object('campos', p_medicoes, 'por_pt', v_eh_pt));
  end if;

  return v_count;
end $$;

grant execute on function bm_registar_medicoes(uuid, jsonb) to authenticated;
revoke execute on function bm_registar_medicoes(uuid, jsonb) from public, anon;

create or replace function bm_ultimas_medicoes(p_cliente_id uuid)
returns table(tipo text, valor numeric, registado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select distinct on (m.tipo) m.tipo, m.valor, m.registado_em
  from medicoes_corporais m
  where m.cliente_id = p_cliente_id
    and (
      p_cliente_id = meu_pessoa_id()
      or exists (select 1 from relacoes_pt_cliente r
                 where r.pt_id = meu_pessoa_id() and r.cliente_id = p_cliente_id and r.estado = 'ativa')
    )
  order by m.tipo, m.registado_em desc
$$;

grant execute on function bm_ultimas_medicoes(uuid) to authenticated;
revoke execute on function bm_ultimas_medicoes(uuid) from public, anon;
