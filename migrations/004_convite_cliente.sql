-- BEAST MODE — Migração 004: convite de cliente + RLS de leitura cruzada PT↔cliente
-- (aplicada 2026-07-31)

create policy sel_pessoa_de_cliente on pessoas
  for select using (
    exists (select 1 from relacoes_pt_cliente r
            where r.cliente_id = pessoas.id
              and r.pt_id = meu_pessoa_id()
              and r.estado = 'ativa')
  );

create policy sel_pessoa_do_pt on pessoas
  for select using (
    exists (select 1 from relacoes_pt_cliente r
            where r.pt_id = pessoas.id
              and r.cliente_id = meu_pessoa_id()
              and r.estado = 'ativa')
  );

create or replace function bm_criar_pessoa(p_nome text, p_como_pt boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text; v_existing uuid;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  select email into v_email from auth.users where id = auth.uid();

  select id into v_id from pessoas where auth_user_id = auth.uid();
  if v_id is not null then
    return v_id;
  end if;

  select id into v_existing from pessoas where email = v_email and auth_user_id is null;
  if v_existing is not null then
    update pessoas set auth_user_id = auth.uid(), nome = trim(p_nome)
      where id = v_existing;
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

create or replace function bm_convidar_cliente(p_email text, p_nome text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid; v_cliente_id uuid; v_email text;
begin
  v_pt_id := meu_pessoa_id();
  if v_pt_id is null or not exists (select 1 from perfis_pt where pessoa_id = v_pt_id) then
    raise exception 'Só treinadores podem convidar clientes';
  end if;

  v_email := lower(trim(p_email));
  if v_email is null or v_email = '' or v_email not like '%@%' then
    raise exception 'Email inválido';
  end if;

  select id into v_cliente_id from pessoas where email = v_email;
  if v_cliente_id is null then
    insert into pessoas (nome, email)
    values (coalesce(nullif(trim(p_nome), ''), split_part(v_email, '@', 1)), v_email)
    returning id into v_cliente_id;
  end if;

  if v_cliente_id = v_pt_id then
    raise exception 'Não podes convidar-te a ti próprio';
  end if;

  if exists (select 1 from relacoes_pt_cliente
             where pt_id = v_pt_id and cliente_id = v_cliente_id and estado = 'ativa') then
    raise exception 'Este cliente já está associado a ti';
  end if;

  insert into relacoes_pt_cliente (pt_id, cliente_id, estado)
  values (v_pt_id, v_cliente_id, 'ativa');

  perform registar_evento('cliente_convidado', v_pt_id, v_cliente_id,
    jsonb_build_object('email', v_email));

  return v_cliente_id;
end $$;

grant execute on function bm_convidar_cliente(text, text) to authenticated;
revoke execute on function bm_convidar_cliente(text, text) from public, anon;
