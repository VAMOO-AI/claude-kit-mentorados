-- Tabela de papel (app_users) e tabela de negócio (<members>) sem escrita por sessão.
-- Antes: policy FOR ALL TO authenticated USING (true) → qualquer logado vira admin
-- ou se liga ao registro de outra pessoa pela API REST.
-- Pré-requisito: nenhuma rota do app escreve nessas tabelas com o client de sessão
-- (confira com grep; escrita de admin passa por rota com service role).
-- Guarde o nome e a definição das policies antigas aqui, como rollback.

BEGIN;

DROP POLICY IF EXISTS "<policy antiga de app_users>" ON public.app_users;

CREATE POLICY "app_users le a propria linha" ON public.app_users
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR lower(email) = lower(auth.jwt() ->> 'email')
  );

DROP POLICY IF EXISTS "<policy antiga de members>" ON public.<members>;

-- Mantém a leitura (seletores do app), tira a escrita.
CREATE POLICY "<members> leitura autenticada" ON public.<members>
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

COMMIT;

-- Prova: SET LOCAL ROLE authenticated + claims de um usuário comum, em ROLLBACK:
-- app_users devolve 1 linha (a própria); UPDATE afeta 0 nas duas tabelas.
