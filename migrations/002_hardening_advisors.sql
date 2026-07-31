-- BEAST MODE — Migração 002: Hardening pós-advisors (aplicada 2026-07-22, versão 20260722142149)

create or replace function bloquear_mutacao() returns trigger
language plpgsql set search_path = public as $$
begin
  raise exception 'Tabela % é append-only: % proibido', tg_table_name, tg_op;
end $$;

revoke execute on function meu_pessoa_id() from public, anon;
revoke execute on function tem_consentimento(uuid, text) from public, anon;

create policy sel_perfis_pt on perfis_pt
  for select using (
    pessoa_id = meu_pessoa_id()
    or exists (select 1 from relacoes_pt_cliente r
               where r.pt_id = perfis_pt.pessoa_id
                 and r.cliente_id = meu_pessoa_id()
                 and r.estado = 'ativa')
  );

comment on table eventos is 'Livro imutável. Sem policies de leitura por design: acesso apenas via service role (admin).';
