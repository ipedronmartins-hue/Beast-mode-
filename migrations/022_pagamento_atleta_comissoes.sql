-- BEAST MODE — Migração 022: atleta paga, PT recebe comissão, admin confirma via MBWay manual. (aplicada 2026-08-02)
-- Modelo: atleta trancado até pagar (sem acesso nenhum). PT nunca paga — é quem traz o
-- atleta. Comissão gerada automaticamente quando o admin confirma o pagamento.

create table configuracoes (
  chave text primary key,
  valor numeric not null,
  atualizado_em timestamptz not null default now()
);
alter table configuracoes enable row level security;
create policy sel_config on configuracoes for select using (true);

insert into configuracoes (chave, valor) values
  ('preco_atleta_mensal', 9.90),
  ('comissao_pt_percentagem', 30);

create table comissoes_pt (
  id uuid primary key default gen_random_uuid(),
  pt_id uuid not null references perfis_pt(pessoa_id),
  atleta_id uuid not null references pessoas(id),
  valor numeric(6,2) not null,
  estado text not null default 'pendente' check (estado in ('pendente','paga')),
  criado_em timestamptz not null default now(),
  paga_em timestamptz
);
alter table comissoes_pt enable row level security;
create policy admin_sel_comissoes on comissoes_pt for select using (sou_admin());
create policy pt_sel_proprias_comissoes on comissoes_pt for select using (pt_id = meu_pessoa_id());

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

create or replace function bm_admin_confirmar_pagamento(p_atleta_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid; v_pt_id uuid; v_preco numeric; v_pct numeric; v_comissao numeric;
begin
  if not sou_admin() then
    raise exception 'Apenas administradores';
  end if;
  v_admin := meu_pessoa_id();

  select pt_id into v_pt_id from relacoes_pt_cliente
    where cliente_id = p_atleta_id and estado = 'ativa'
    order by inicio desc limit 1;
  if v_pt_id is null then
    raise exception 'Este atleta não tem treinador associado';
  end if;

  select valor into v_preco from configuracoes where chave = 'preco_atleta_mensal';
  select valor into v_pct from configuracoes where chave = 'comissao_pt_percentagem';
  v_comissao := round(v_preco * v_pct / 100, 2);

  update pessoas set estado = 'ativo' where id = p_atleta_id;

  insert into comissoes_pt (pt_id, atleta_id, valor) values (v_pt_id, p_atleta_id, v_comissao);

  perform registar_evento('pagamento_confirmado_admin', v_admin, p_atleta_id,
    jsonb_build_object('pt_id', v_pt_id, 'comissao', v_comissao));
end $$;

grant execute on function bm_admin_confirmar_pagamento(uuid) to authenticated;
revoke execute on function bm_admin_confirmar_pagamento(uuid) from anon, public;

create or replace function bm_admin_marcar_comissao_paga(p_comissao_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not sou_admin() then
    raise exception 'Apenas administradores';
  end if;
  update comissoes_pt set estado = 'paga', paga_em = now() where id = p_comissao_id;
end $$;

grant execute on function bm_admin_marcar_comissao_paga(uuid) to authenticated;
revoke execute on function bm_admin_marcar_comissao_paga(uuid) from anon, public;

create or replace function bm_admin_comissoes()
returns table(id uuid, pt_nome text, atleta_nome text, valor numeric, estado text, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, p1.nome, p2.nome, c.valor, c.estado, c.criado_em
  from comissoes_pt c
  join pessoas p1 on p1.id = c.pt_id
  join pessoas p2 on p2.id = c.atleta_id
  where sou_admin()
  order by (c.estado = 'pendente') desc, c.criado_em desc
$$;

grant execute on function bm_admin_comissoes() to authenticated;
revoke execute on function bm_admin_comissoes() from anon, public;

-- Grandfather: quem já tinha conta antes desta migração mantém-se ativo
-- (a Sofia continua a testar sem interrupção). O gate só se aplica a
-- convites novos a partir de agora.
update pessoas set estado = 'ativo' where estado = 'pendente';
