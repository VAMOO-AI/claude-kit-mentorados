-- supabase/migrations/<timestamp>_mcp_oauth.sql
-- MCP do sistema: servidor OAuth próprio numa edge function, para um dono.
--
-- O token é opaco, guardado só como hash, e não abre nada além da edge function.
-- O token do Supabase OAuth Server é um JWT `authenticated` que também vale no
-- PostgREST: exigiria uma policy RESTRICTIVE em cada tabela aberta a `authenticated`.
--
-- Login = código de 6 dígitos num canal que só o dono lê: quem dispara o pedido no
-- navegador não lê o código. Todas as tabelas: RLS ligada, sem policy, só service_role.

CREATE TABLE IF NOT EXISTS public.mcp_clients (
  client_id text PRIMARY KEY,
  client_name text NOT NULL,
  redirect_uris text[] NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.mcp_auth_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id text NOT NULL REFERENCES public.mcp_clients (client_id) ON DELETE CASCADE,
  redirect_uri text NOT NULL,
  state text,
  scope text,
  code_challenge text NOT NULL,
  expires_at timestamptz NOT NULL,
  -- sha256(codigo || ':' || id): ler a tabela não entrega o código.
  otp_hash text,
  otp_sent_at timestamptz,
  otp_expires_at timestamptz,
  otp_attempts integer NOT NULL DEFAULT 0,
  approved_at timestamptz,
  -- Authorization code (RFC 6749 §4.1.2): uso único, consumido no /token.
  code_hash text UNIQUE,
  code_expires_at timestamptz,
  code_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Freio de spam: quantos códigos saíram na janela.
CREATE INDEX IF NOT EXISTS mcp_auth_requests_otp_sent_idx
  ON public.mcp_auth_requests (otp_sent_at DESC)
  WHERE otp_sent_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.mcp_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id text NOT NULL REFERENCES public.mcp_clients (client_id) ON DELETE CASCADE,
  access_hash text NOT NULL UNIQUE,
  access_expires_at timestamptz NOT NULL,
  refresh_hash text NOT NULL UNIQUE,
  refresh_expires_at timestamptz NOT NULL,
  -- Revogar = setar. O refresh rotaciona: cada uso revoga o par anterior.
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Kill switch, lido a cada request. Nasce desligado: ligar é um UPDATE, não um deploy.
-- Se o projeto já tem tabela de configuração, use uma chave nela e ajuste o habilitado() do index.ts.
CREATE TABLE IF NOT EXISTS public.mcp_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.mcp_config (id, enabled) VALUES (true, false) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.mcp_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mcp_auth_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mcp_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mcp_config ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.mcp_clients FROM anon, authenticated;
REVOKE ALL ON public.mcp_auth_requests FROM anon, authenticated;
REVOKE ALL ON public.mcp_tokens FROM anon, authenticated;
REVOKE ALL ON public.mcp_config FROM anon, authenticated;

COMMENT ON TABLE public.mcp_clients IS 'Clientes MCP registrados por DCR (RFC 7591). Só service_role.';
COMMENT ON TABLE public.mcp_auth_requests IS 'Pedidos de autorização OAuth do MCP: código ao dono + authorization code. Só service_role.';
COMMENT ON TABLE public.mcp_tokens IS 'Tokens opacos (hash) do MCP. Revogar = UPDATE revoked_at. Só service_role.';
COMMENT ON TABLE public.mcp_config IS 'enabled = true liga o MCP (login e chamadas). Qualquer outro estado desliga na hora.';

/**
 * Troca o código pela aprovação do pedido, numa transação.
 *
 * O UPDATE ... WHERE approved_at IS NULL garante uso único sob concorrência, e cada
 * erro gasta uma tentativa — no limite o pedido morre (10^6 códigos não cabem em 3 chutes).
 */
CREATE OR REPLACE FUNCTION public.mcp_consume_otp(
  p_request_id uuid,
  p_code text,
  p_max_attempts integer DEFAULT 3
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  UPDATE public.mcp_auth_requests
  SET approved_at = now()
  WHERE id = p_request_id
    AND approved_at IS NULL
    AND otp_hash IS NOT NULL
    AND otp_expires_at > now()
    AND otp_attempts < p_max_attempts
    AND otp_hash = encode(sha256((p_code || ':' || id::text)::bytea), 'hex')
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    RETURN 'ok';
  END IF;

  UPDATE public.mcp_auth_requests
  SET otp_attempts = otp_attempts + 1
  WHERE id = p_request_id
    AND approved_at IS NULL
    AND otp_hash IS NOT NULL
    AND otp_expires_at > now()
    AND otp_attempts < p_max_attempts
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN 'sem_pendente';
  END IF;
  RETURN 'invalido';
END;
$$;

REVOKE ALL ON FUNCTION public.mcp_consume_otp(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mcp_consume_otp(uuid, text, integer) FROM anon, authenticated;
