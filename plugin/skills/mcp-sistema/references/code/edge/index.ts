// supabase/functions/sistema-mcp/index.ts
// @ts-nocheck — Deno edge function (Supabase).
/**
 * Liga o handler ao Supabase. Público em https://<dominio-do-app>/mcp (rewrites no
 * vercel.json).
 *
 * verify_jwt = false (config.toml): o Bearer é um token opaco nosso, não JWT.
 * Sem isso o gateway devolve 401 antes de a função rodar — e todo deploy sem o
 * config.toml volta o flag para true.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createMcpHandler, OTP_MAX_TENTATIVAS } from './handler.ts';
// As tools de leitura que o projeto já tem (ex.: as do assistente interno). A tool
// chama a MESMA lib que a tela usa — senão o número do agente diverge do app.
import { TOOLS, executarTool } from './tools.ts';

const FUNCAO = 'sistema-mcp';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
// Domínio do app (https://app.exemplo.com.br), nunca o host do supabase.co.
const PUBLIC_BASE = Deno.env.get('MCP_PUBLIC_BASE') ?? '';
if (!PUBLIC_BASE) throw new Error('MCP_PUBLIC_BASE ausente: issuer e resource sairiam vazios');

const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

function falhou(op: string, error) {
    if (error) throw new Error(`${op}: ${error.message}`);
}

const store = {
    async registrarCliente(c) {
        const { error } = await supabase.from('mcp_clients').insert(c);
        falhou('registrarCliente', error);
    },
    async cliente(id) {
        const { data, error } = await supabase.from('mcp_clients').select('client_id, client_name, redirect_uris').eq('client_id', id).maybeSingle();
        falhou('cliente', error);
        return data;
    },
    async criarPedido(p) {
        const { data, error } = await supabase.from('mcp_auth_requests').insert(p).select('id').single();
        falhou('criarPedido', error);
        return data.id;
    },
    async pedido(id) {
        const { data, error } = await supabase.from('mcp_auth_requests').select('*').eq('id', id).maybeSingle();
        falhou('pedido', error);
        return data;
    },
    async codigosEnviadosDesde(desde) {
        const { count, error } = await supabase
            .from('mcp_auth_requests')
            .select('id', { count: 'exact', head: true })
            .gt('otp_sent_at', desde.toISOString());
        falhou('codigosEnviadosDesde', error);
        return count ?? 0;
    },
    async gravarOtp(id, hash, enviado, expira) {
        const { error } = await supabase
            .from('mcp_auth_requests')
            .update({ otp_hash: hash, otp_sent_at: enviado.toISOString(), otp_expires_at: expira.toISOString(), otp_attempts: 0 })
            .eq('id', id)
            .is('approved_at', null);
        falhou('gravarOtp', error);
    },
    async consumirOtp(id, codigo) {
        const { data, error } = await supabase.rpc('mcp_consume_otp', { p_request_id: id, p_code: codigo, p_max_attempts: OTP_MAX_TENTATIVAS });
        falhou('consumirOtp', error);
        return data;
    },
    async gravarCodigo(id, hash, expira) {
        const { error } = await supabase.from('mcp_auth_requests').update({ code_hash: hash, code_expires_at: expira.toISOString() }).eq('id', id);
        falhou('gravarCodigo', error);
    },
    async resgatarCodigo(hash) {
        // Um UPDATE só: dois /token simultâneos com o mesmo code não passam os dois.
        const { data, error } = await supabase
            .from('mcp_auth_requests')
            .update({ code_used_at: new Date().toISOString() })
            .eq('code_hash', hash)
            .is('code_used_at', null)
            .gt('code_expires_at', new Date().toISOString())
            .select('client_id, redirect_uri, code_challenge')
            .maybeSingle();
        falhou('resgatarCodigo', error);
        return data;
    },
    async gravarToken(t) {
        const { error } = await supabase.from('mcp_tokens').insert(t);
        falhou('gravarToken', error);
    },
    async tokenPorAccess(hash) {
        const { data, error } = await supabase
            .from('mcp_tokens')
            .select('client_id')
            .eq('access_hash', hash)
            .is('revoked_at', null)
            .gt('access_expires_at', new Date().toISOString())
            .maybeSingle();
        falhou('tokenPorAccess', error);
        return data;
    },
    async rotacionarRefresh(hash) {
        const { data, error } = await supabase
            .from('mcp_tokens')
            .update({ revoked_at: new Date().toISOString() })
            .eq('refresh_hash', hash)
            .is('revoked_at', null)
            .gt('refresh_expires_at', new Date().toISOString())
            .select('client_id')
            .maybeSingle();
        falhou('rotacionarRefresh', error);
        return data;
    },
};

async function habilitado(): Promise<boolean> {
    // Fail closed: erro de leitura ou linha ausente = desligado.
    const { data } = await supabase.from('mcp_config').select('enabled').eq('id', true).maybeSingle();
    return data?.enabled === true;
}

/**
 * Entrega o código num canal que SÓ o dono lê (WhatsApp, e-mail). É a assimetria
 * que segura o login: quem dispara o pedido no navegador não vê o código.
 * Use o envio que o projeto já tem (uma edge function de WhatsApp, o provedor de
 * e-mail) e devolva true só quando ele aceitou a mensagem.
 */
async function enviarCodigo(texto: string): Promise<boolean> {
    throw new Error(`implemente o envio do código ao dono (${texto.length} chars)`);
}

const handle = createMcpHandler({
    publicBase: PUBLIC_BASE,
    funcao: FUNCAO,
    urlFuncao: `${SUPABASE_URL}/functions/v1/${FUNCAO}`,
    nome: 'Meu Sistema',
    quem: 'o dono do sistema',
    instrucoes: 'Leitura do sistema: <domínios que as tools cobrem>. Só leitura.',
    now: () => new Date(),
    habilitado,
    enviarCodigo,
    ferramentas: TOOLS.map((t) => ({ name: t.name, description: t.description, inputSchema: t.input_schema })),
    executarFerramenta: (nome, args) => executarTool(nome, args, { supabase }),
    store,
});

Deno.serve(handle);
