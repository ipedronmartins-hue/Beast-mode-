-- BEAST MODE — Migração 021: ações de administração (aprovar/suspender/arquivar). (aplicada 2026-08-02)
-- Princípio: nada é apagado. "Eliminar" arquiva — o histórico do atleta é dele e
-- sobrevive a qualquer decisão administrativa. Reversível por design.

create type estado_conta as enum ('pendente', 'ativo', 'suspenso', 'arquivado');

alter table pessoas add column estado estado_conta not null default 'ativo';
alter table perfis_pt add column estado estado_conta not null default 'pendente';

update perfis_pt set estado = 'ativo';

create or replace function bm_admin_mudar_estado(p_pessoa_id uuid, p_estado text, p_alvo text default 'pessoa')
returns void language plpgsql security definer set search_path = public as $$
declare v_admin uuid;
begin
  if not sou_admin() then
    raise exception 'Apenas administradores';
  end if;
  if p_estado not in ('pendente','ativo','suspenso','arquivado') then
    raise exception 'Estado inválido';
  end if;
  if p_alvo not in ('pessoa','pt') then
    raise exception 'Alvo inválido';
  end if;

  v_admin := meu_pessoa_id();

  if p_alvo = 'pt' then
    if not exists (select 1 from perfis_pt where pessoa_id = p_pessoa_id) then
      raise exception 'Treinador não encontrado';
    end if;
    update perfis_pt set estado = p_estado::estado_conta where pessoa_id = p_pessoa_id;
  else
    if not exists (select 1 from pessoas where id = p_pessoa_id) then
      raise exception 'Pessoa não encontrada';
    end if;
    update pessoas set estado = p_estado::estado_conta where id = p_pessoa_id;
  end if;

  perform registar_evento('estado_alterado_admin', v_admin, p_pessoa_id,
    jsonb_build_object('alvo', p_alvo, 'novo_estado', p_estado));
end $$;

grant execute on function bm_admin_mudar_estado(uuid, text, text) to authenticated;
revoke execute on function bm_admin_mudar_estado(uuid, text, text) from anon, public;

drop function if exists bm_admin_pts();
create function bm_admin_pts()
returns table(pessoa_id uuid, nome text, email text, num_atletas bigint, estado text, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.nome, p.email,
    (select count(*) from relacoes_pt_cliente r where r.pt_id = p.id and r.estado = 'ativa'),
    pt.estado::text,
    p.criado_em
  from pessoas p
  join perfis_pt pt on pt.pessoa_id = p.id
  where sou_admin()
  order by
    case pt.estado when 'pendente' then 0 when 'ativo' then 1 when 'suspenso' then 2 else 3 end,
    p.criado_em desc
$$;

drop function if exists bm_admin_atletas();
create function bm_admin_atletas()
returns table(
  pessoa_id uuid, nome text, email text, conta_ativa boolean, estado text,
  pt_nome text, tem_avaliacao boolean, tem_plano boolean, desde timestamptz
)
language sql stable security definer set search_path = public as $$
  select
    p.id, p.nome, p.email,
    (p.auth_user_id is not null),
    p.estado::text,
    pt.nome,
    exists (select 1 from avaliacoes a where a.cliente_id = p.id),
    exists (select 1 from planos pl where pl.cliente_id = p.id and pl.estado = 'publicado'),
    r.inicio
  from relacoes_pt_cliente r
  join pessoas p on p.id = r.cliente_id
  left join pessoas pt on pt.id = r.pt_id
  where sou_admin() and r.estado = 'ativa'
  order by
    case p.estado when 'pendente' then 0 when 'ativo' then 1 when 'suspenso' then 2 else 3 end,
    r.inicio desc
$$;

grant execute on function bm_admin_pts() to authenticated;
grant execute on function bm_admin_atletas() to authenticated;
revoke execute on function bm_admin_pts() from anon, public;
revoke execute on function bm_admin_atletas() from anon, public;

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
