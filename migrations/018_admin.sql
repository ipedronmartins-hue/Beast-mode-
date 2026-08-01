-- BEAST MODE — Migração 018: papel admin com acesso de leitura total à plataforma. (aplicada 2026-08-02)
-- Escrita continua exclusivamente por RPC — admin não ganha UPDATE/INSERT/DELETE
-- direto em tabelas, só leitura alargada. Mantém a disciplina "escrita só por RPC".

create table admins (
  email text primary key,
  criado_em timestamptz not null default now()
);
alter table admins enable row level security;

insert into admins (email) values ('ipedronmartins@gmail.com');

create or replace function sou_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from admins a
    join auth.users u on u.email = a.email
    where u.id = auth.uid()
  )
$$;

revoke execute on function sou_admin() from anon, public;

create policy admin_sel_pessoas on pessoas for select using (sou_admin());
create policy admin_sel_perfis_pt on perfis_pt for select using (sou_admin());
create policy admin_sel_relacoes on relacoes_pt_cliente for select using (sou_admin());
create policy admin_sel_avaliacoes on avaliacoes for select using (sou_admin());
create policy admin_sel_objetivos on objetivos_cliente for select using (sou_admin());
create policy admin_sel_planos on planos for select using (sou_admin());
create policy admin_sel_sessoes on sessoes_treino for select using (sou_admin());
create policy admin_sel_registos on registos_serie for select using (sou_admin());
create policy admin_sel_medicoes on medicoes_corporais for select using (sou_admin());
create policy admin_sel_consentimentos on consentimentos for select using (sou_admin());
create policy admin_sel_comentarios on comentarios_pt for select using (sou_admin());
create policy admin_sel_eventos on eventos for select using (sou_admin());

create or replace function bm_admin_resumo()
returns table(pts bigint, atletas bigint, planos_publicados bigint, sessoes_concluidas bigint)
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from perfis_pt),
    (select count(distinct cliente_id) from relacoes_pt_cliente where estado = 'ativa'),
    (select count(*) from planos where estado = 'publicado'),
    (select count(*) from sessoes_treino where concluida_em is not null)
  where sou_admin()
$$;

create or replace function bm_admin_pts()
returns table(pessoa_id uuid, nome text, email text, num_atletas bigint, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.nome, p.email,
    (select count(*) from relacoes_pt_cliente r where r.pt_id = p.id and r.estado = 'ativa'),
    p.criado_em
  from pessoas p
  join perfis_pt pt on pt.pessoa_id = p.id
  where sou_admin()
  order by p.criado_em desc
$$;

create or replace function bm_admin_eventos(p_limite int default 30)
returns table(id bigint, tipo text, ator_nome text, sujeito_nome text, ocorrido_em timestamptz, dados jsonb)
language sql stable security definer set search_path = public as $$
  select e.id, e.tipo, pa.nome, ps.nome, e.ocorrido_em, e.dados
  from eventos e
  left join pessoas pa on pa.id = e.ator_id
  left join pessoas ps on ps.id = e.sujeito_id
  where sou_admin()
  order by e.ocorrido_em desc
  limit p_limite
$$;

grant execute on function bm_admin_resumo() to authenticated;
grant execute on function bm_admin_pts() to authenticated;
grant execute on function bm_admin_eventos(int) to authenticated;
revoke execute on function bm_admin_resumo() from anon, public;
revoke execute on function bm_admin_pts() from anon, public;
revoke execute on function bm_admin_eventos(int) from anon, public;
