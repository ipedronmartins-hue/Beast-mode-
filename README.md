# Beast Mode — site estático (fase 0/1)

Páginas HTML leves, sem framework (guardrail: sem framework até ao primeiro cliente pagante).

- index.html — landing pública
- login.html — magic link (Supabase Auth)
- app.html — router pós-login: onboarding → área PT ou área Cliente
- config.js — URL + anon key do Supabase (preencher ANON KEY antes do deploy)
- migrations/ — cópia de todas as migrações aplicadas no Supabase (fonte de verdade no repo)

## Deploy
1. Criar repo GitHub `beast-mode`, colocar estes ficheiros na raiz.
2. Preencher `config.js` com a anon key (Supabase → Settings → API).
3. Importar o repo no Vercel (framework: Other, sem build). Auto-deploy da main fica ativo.
4. No Supabase → Auth → URL Configuration: adicionar o domínio Vercel aos Redirect URLs.

Projeto Supabase: beast-mode (ref awvycaaeojdcwlbuxzkw) — 100% independente da YTB.
