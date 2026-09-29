-- Log das escritas feitas pelo MCP. A linha nasce ANTES da gravação (status
-- 'iniciado'); sem ela a tool recusa a escrita. Só o service role lê/grava:
-- RLS ligada e nenhuma policy.

CREATE TABLE IF NOT EXISTS mcp_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  auth_user_id UUID NOT NULL,
  email TEXT NOT NULL,
  role TEXT NOT NULL,
  client_id TEXT,
  tool TEXT NOT NULL,
  args JSONB NOT NULL DEFAULT '{}',
  antes JSONB,
  depois JSONB,
  status TEXT NOT NULL DEFAULT 'iniciado' CHECK (status IN ('iniciado', 'aplicado', 'falhou')),
  erro TEXT
);

CREATE INDEX IF NOT EXISTS idx_mcp_audit_log_created ON mcp_audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mcp_audit_log_user ON mcp_audit_log (auth_user_id, created_at DESC);

ALTER TABLE mcp_audit_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON mcp_audit_log FROM anon, authenticated;
