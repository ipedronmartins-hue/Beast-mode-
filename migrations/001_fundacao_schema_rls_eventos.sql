-- BEAST MODE — Migração 001: Fundação (aplicada 2026-07-22, versão 20260722142124)
-- Schema mínimo MVP + RLS deny-by-default + livro de eventos imutável.
-- Escrita apenas por RPC (SECURITY DEFINER com verificação de papel).

create type papel as enum ('pt', 'cliente', 'admin');
create type estado_relacao as enum ('ativa', 'arquivada');
create type objetivo_treino as enum (
  'hipertrofia', 'forca', 'perda_peso', 'definicao',
  'saude_geral', 'manutencao', 'reabilitacao', 'performance'
);
create type nivel_treino as enum ('iniciante', 'intermedio', 'avancado');
create type estado_plano as enum ('rascunho', 'publicado', 'arquivado');

create table pessoas (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  nome text not null,
  email text not null unique,
  criado_em timestamptz not null default now()
);

create table perfis_pt (
  pessoa_id uuid primary key references pessoas(id) on delete cascade,
  bio text,
  criado_em timestamptz not null default now()
);

create table relacoes_pt_cliente (
  id uuid primary key default gen_random_uuid(),
  pt_id uuid not null references perfis_pt(pessoa_id),
  cliente_id uuid not null references pessoas(id),
  estado estado_relacao not null default 'ativa',
  inicio timestamptz not null default now(),
  fim timestamptz,
  unique (pt_id, cliente_id, inicio)
);
create index idx_relacoes_pt on relacoes_pt_cliente(pt_id) where estado = 'ativa';
create index idx_relacoes_cliente on relacoes_pt_cliente(cliente_id);

create table consentimentos (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references pessoas(id) on delete cascade,
  tipo text not null check (tipo in ('dados_saude', 'medicoes_corporais')),
  concedido boolean not null,
  registado_em timestamptz not null default now()
);
create index idx_consentimentos_pessoa on consentimentos(pessoa_id, tipo, registado_em desc);

create table avaliacoes (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references pessoas(id),
  pt_id uuid not null references perfis_pt(pessoa_id),
  objetivo objetivo_treino not null,
  nivel nivel_treino not null,
  dias_disponiveis smallint not null check (dias_disponiveis between 1 and 7),
  minutos_por_sessao smallint not null check (minutos_por_sessao between 15 and 240),
  equipamento jsonb not null default '[]'::jsonb,
  limitacoes jsonb not null default '[]'::jsonb,
  notas_pt text,
  criado_em timestamptz not null default now()
);
create index idx_avaliacoes_cliente on avaliacoes(cliente_id, criado_em desc);

create table objetivos_cliente (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references pessoas(id),
  objetivo objetivo_treino not null,
  ativo_desde timestamptz not null default now(),
  ativo_ate timestamptz
);
create index idx_objetivos_cliente on objetivos_cliente(cliente_id, ativo_desde desc);

create table planos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references pessoas(id),
  pt_id uuid not null references perfis_pt(pessoa_id),
  avaliacao_id uuid references avaliacoes(id),
  nome text not null,
  estado estado_plano not null default 'rascunho',
  parametros jsonb not null default '{}'::jsonb,
  conteudo jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  publicado_em timestamptz
);
create index idx_planos_cliente on planos(cliente_id, criado_em desc);
create index idx_planos_pt on planos(pt_id, estado);

create table sessoes_treino (
  id uuid primary key default gen_random_uuid(),
  plano_id uuid not null references planos(id),
  cliente_id uuid not null references pessoas(id),
  dia_plano text not null,
  iniciada_em timestamptz not null default now(),
  concluida_em timestamptz,
  feedback jsonb
);
create index idx_sessoes_cliente on sessoes_treino(cliente_id, iniciada_em desc);

create table registos_serie (
  id uuid primary key default gen_random_uuid(),
  sessao_id uuid not null references sessoes_treino(id),
  exercicio text not null,
  numero_serie smallint not null check (numero_serie between 1 and 20),
  carga_kg numeric(6,2) check (carga_kg >= 0),
  repeticoes smallint check (repeticoes between 0 and 200),
  rpe numeric(3,1) check (rpe between 1 and 10),
  registado_em timestamptz not null default now()
);
create index idx_registos_sessao on registos_serie(sessao_id);

create table medicoes_corporais (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references pessoas(id),
  tipo text not null check (tipo in ('peso_kg','altura_cm','cintura_cm','anca_cm','peito_cm','braco_cm','coxa_cm','gordura_pct','massa_muscular_kg')),
  valor numeric(6,2) not null check (valor > 0),
  registado_em timestamptz not null default now(),
  registado_por uuid not null references pessoas(id)
);
create index idx_medicoes_cliente on medicoes_corporais(cliente_id, tipo, registado_em desc);

create table comentarios_pt (
  id uuid primary key default gen_random_uuid(),
  sessao_id uuid not null references sessoes_treino(id),
  pt_id uuid not null references perfis_pt(pessoa_id),
  texto text not null,
  criado_em timestamptz not null default now()
);

create table eventos (
  id bigint generated always as identity primary key,
  tipo text not null,
  ator_id uuid,
  sujeito_id uuid,
  dados jsonb not null default '{}'::jsonb,
  ocorrido_em timestamptz not null default now()
);
create index idx_eventos_sujeito on eventos(sujeito_id, ocorrido_em desc);
create index idx_eventos_tipo on eventos(tipo, ocorrido_em desc);

create or replace function bloquear_mutacao() returns trigger
language plpgsql as $$
begin
  raise exception 'Tabela % é append-only: % proibido', tg_table_name, tg_op;
end $$;

create trigger trg_eventos_imutavel
  before update or delete on eventos
  for each row execute function bloquear_mutacao();

create trigger trg_registos_imutavel
  before update or delete on registos_serie
  for each row execute function bloquear_mutacao();

create trigger trg_medicoes_imutavel
  before update or delete on medicoes_corporais
  for each row execute function bloquear_mutacao();

alter table pessoas enable row level security;
alter table perfis_pt enable row level security;
alter table relacoes_pt_cliente enable row level security;
alter table consentimentos enable row level security;
alter table avaliacoes enable row level security;
alter table objetivos_cliente enable row level security;
alter table planos enable row level security;
alter table sessoes_treino enable row level security;
alter table registos_serie enable row level security;
alter table medicoes_corporais enable row level security;
alter table comentarios_pt enable row level security;
alter table eventos enable row level security;

create policy sel_pessoa_propria on pessoas
  for select using (auth_user_id = auth.uid());

create or replace function meu_pessoa_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from pessoas where auth_user_id = auth.uid()
$$;

create policy sel_relacoes on relacoes_pt_cliente
  for select using (pt_id = meu_pessoa_id() or cliente_id = meu_pessoa_id());

create policy sel_avaliacoes on avaliacoes
  for select using (
    cliente_id = meu_pessoa_id()
    or exists (select 1 from relacoes_pt_cliente r
               where r.pt_id = meu_pessoa_id()
                 and r.cliente_id = avaliacoes.cliente_id
                 and r.estado = 'ativa')
  );

create policy sel_objetivos on objetivos_cliente
  for select using (
    cliente_id = meu_pessoa_id()
    or exists (select 1 from relacoes_pt_cliente r
               where r.pt_id = meu_pessoa_id()
                 and r.cliente_id = objetivos_cliente.cliente_id
                 and r.estado = 'ativa')
  );

create policy sel_planos on planos
  for select using (
    (cliente_id = meu_pessoa_id() and estado = 'publicado')
    or pt_id = meu_pessoa_id()
  );

create policy sel_sessoes on sessoes_treino
  for select using (
    cliente_id = meu_pessoa_id()
    or exists (select 1 from relacoes_pt_cliente r
               where r.pt_id = meu_pessoa_id()
                 and r.cliente_id = sessoes_treino.cliente_id
                 and r.estado = 'ativa')
  );

create policy sel_registos on registos_serie
  for select using (
    exists (select 1 from sessoes_treino s
            where s.id = registos_serie.sessao_id
              and (s.cliente_id = meu_pessoa_id()
                   or exists (select 1 from relacoes_pt_cliente r
                              where r.pt_id = meu_pessoa_id()
                                and r.cliente_id = s.cliente_id
                                and r.estado = 'ativa')))
  );

create or replace function tem_consentimento(p_pessoa uuid, p_tipo text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select concedido from consentimentos
     where pessoa_id = p_pessoa and tipo = p_tipo
     order by registado_em desc limit 1),
    false)
$$;

create policy sel_medicoes on medicoes_corporais
  for select using (
    cliente_id = meu_pessoa_id()
    or (
      exists (select 1 from relacoes_pt_cliente r
              where r.pt_id = meu_pessoa_id()
                and r.cliente_id = medicoes_corporais.cliente_id
                and r.estado = 'ativa')
      and tem_consentimento(medicoes_corporais.cliente_id, 'medicoes_corporais')
    )
  );

create policy sel_consentimentos on consentimentos
  for select using (pessoa_id = meu_pessoa_id());

create policy sel_comentarios on comentarios_pt
  for select using (
    pt_id = meu_pessoa_id()
    or exists (select 1 from sessoes_treino s
               where s.id = comentarios_pt.sessao_id
                 and s.cliente_id = meu_pessoa_id())
  );

create or replace function registar_evento(p_tipo text, p_ator uuid, p_sujeito uuid, p_dados jsonb)
returns void language sql security definer set search_path = public as $$
  insert into eventos (tipo, ator_id, sujeito_id, dados)
  values (p_tipo, p_ator, p_sujeito, coalesce(p_dados, '{}'::jsonb))
$$;

revoke execute on function registar_evento from public, anon, authenticated;

create or replace function bm_criar_pessoa(p_nome text, p_como_pt boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  select email into v_email from auth.users where id = auth.uid();
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

grant execute on function bm_criar_pessoa to authenticated;
revoke execute on function bm_criar_pessoa from public, anon;
