-- O token que o MCP recebe é um JWT `authenticated` comum com a claim client_id.
-- Sem esta trava, o cliente MCP lê e grava direto pela API REST do Supabase nas
-- tabelas abertas a authenticated/public — por fora das tools e do escopo por
-- papel. A sessão web não carrega client_id, então nada muda para o app.
--
-- RESTRICTIVE entra em AND com as policies existentes: só corta, nunca abre.
-- Lista de tabelas: saída da query de pg_policies em banco.md §3.
-- Rollback: DROP POLICY "sem token oauth" em cada tabela + storage.objects.

BEGIN;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    '<tabela_1>', '<tabela_2>'  -- todas as tabelas com policy para authenticated/public
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "sem token oauth" ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY "sem token oauth" ON public.%I AS RESTRICTIVE FOR ALL TO public '
      'USING ((auth.jwt() ->> ''client_id'') IS NULL) '
      'WITH CHECK ((auth.jwt() ->> ''client_id'') IS NULL)', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS "sem token oauth" ON storage.objects;
CREATE POLICY "sem token oauth" ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
  USING ((auth.jwt() ->> 'client_id') IS NULL)
  WITH CHECK ((auth.jwt() ->> 'client_id') IS NULL);

COMMIT;
