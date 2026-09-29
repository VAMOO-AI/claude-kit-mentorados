-- Liberação do MCP por pessoa. Desligado por padrão: ninguém conecta agente até
-- o admin ligar a chave em Usuários & Acessos. Lido a cada chamada do MCP, então
-- desligar corta na hora.

ALTER TABLE app_users ADD COLUMN IF NOT EXISTS mcp_enabled BOOLEAN NOT NULL DEFAULT false;
