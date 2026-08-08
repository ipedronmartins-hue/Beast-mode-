-- BEAST MODE — Migração 026: perfil de PT com dados reais (contacto, profissão, formação),
-- e contadores mensais no admin (pagantes do mês, total a pagar aos PTs). (aplicada 2026-08-02)

alter table perfis_pt add column telefone text;
alter table perfis_pt add column profissao text;
alter table perfis_pt add column anos_experiencia smallint check (anos_experiencia between 0 and 60);
alter table perfis_pt add column formacao_nome text;
alter table perfis_pt add column formacao_instituicao text;
alter table perfis_pt add column formacao_ano smallint check (formacao_ano between 1970 and 2100);
alter table perfis_pt add column perfil_completo boolean not null default false;

create or replace function bm_completar_perfil_pt(
  p_telefone text, p_profissao text, p_anos_experiencia smallint,
  p_formacao_nome text, p_formacao_instituicao text, p_formacao_ano smallint
) returns void language plpgsql security definer set search_path = public as $$
declare v_pt_id uuid;
begin
  v_pt_id := meu_pessoa_id();
  if v_pt_id is null or not exists (select 1 from perfis_pt where pessoa_id = v_pt_id) then
    raise exception 'Só treinadores podem completar este perfil';
  end if;

  update perfis_pt set
    telefone = nullif(trim(p_telefone), ''),
    profissao = nullif(trim(p_profissao), ''),
    anos_experiencia = p_anos_experiencia,
    formacao_nome = nullif(trim(p_formacao_nome), ''),
    formacao_instituicao = nullif(trim(p_formacao_instituicao), ''),
    formacao_ano = p_formacao_ano,
    perfil_completo = true
  where pessoa_id = v_pt_id;

  perform registar_evento('perfil_pt_completado', v_pt_id, v_pt_id, '{}'::jsonb);
end $$;

grant execute on function bm_completar_perfil_pt(text, text, smallint, text, text, smallint) to authenticated;
revoke execute on function bm_completar_perfil_pt(text, text, smallint, text, text, smallint) from anon, public;

drop function if exists bm_admin_pts();
create function bm_admin_pts()
returns table(
  pessoa_id uuid, nome text, email text, num_atletas bigint, estado text, criado_em timestamptz,
  telefone text, profissao text, anos_experiencia smallint,
  formacao_nome text, formacao_instituicao text, formacao_ano smallint, perfil_completo boolean
)
language sql stable security definer set search_path = public as $$
  select p.id, p.nome, p.email,
    (select count(*) from relacoes_pt_cliente r where r.pt_id = p.id and r.estado = 'ativa'),
    pt.estado::text, p.criado_em,
    pt.telefone, pt.profissao, pt.anos_experiencia,
    pt.formacao_nome, pt.formacao_instituicao, pt.formacao_ano, pt.perfil_completo
  from pessoas p
  join perfis_pt pt on pt.pessoa_id = p.id
  where sou_admin()
  order by
    case pt.estado when 'pendente' then 0 when 'ativo' then 1 when 'suspenso' then 2 else 3 end,
    p.criado_em desc
$$;
grant execute on function bm_admin_pts() to authenticated;
revoke execute on function bm_admin_pts() from anon, public;

drop function if exists bm_admin_resumo();
create function bm_admin_resumo()
returns table(
  pts bigint, atletas bigint, planos_publicados bigint, sessoes_concluidas bigint,
  pagantes_mes bigint, receita_mes numeric, a_pagar_pts numeric
)
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from perfis_pt),
    (select count(distinct cliente_id) from relacoes_pt_cliente where estado = 'ativa'),
    (select count(*) from planos where estado = 'publicado'),
    (select count(*) from sessoes_treino where concluida_em is not null),
    (select count(*) from comissoes_pt where criado_em >= date_trunc('month', now())),
    (select count(*) from comissoes_pt where criado_em >= date_trunc('month', now()))
      * (select valor from configuracoes where chave = 'preco_atleta_mensal'),
    (select coalesce(sum(valor), 0) from comissoes_pt where estado = 'pendente')
  where sou_admin()
$$;
grant execute on function bm_admin_resumo() to authenticated;
revoke execute on function bm_admin_resumo() from anon, public;
