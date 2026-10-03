// supabase/functions/sistema-mcp/handler.ts
// @ts-nocheck — Deno edge function (Supabase).
/**
 * Servidor OAuth 2.1 mínimo + MCP Streamable HTTP sem sessão, numa edge function.
 *
 * Fica atrás de rewrites do domínio do app (vercel.json): o issuer e o `resource`
 * saem de PUBLIC_BASE, nunca de req.url — atrás do proxy o host que a função vê é
 * o do supabase.co, e o cliente recusa metadado de outro host.
 *
 * Um dono, só leitura. Login = código de 6 dígitos num canal que só o dono lê.
 * As dependências (banco, envio do código, tools) chegam injetadas: index.ts liga
 * o Supabase; o teste liga um store em memória e exercita o fluxo inteiro com Request.
 */

export const PROTOCOLOS = ['2025-11-25', '2025-06-18', '2025-03-26'];
export const ESCOPO = 'mcp:read';

export const AUTH_REQUEST_TTL_MIN = 10;
export const OTP_TTL_MIN = 5;
export const OTP_MAX_TENTATIVAS = 3;
export const OTP_JANELA_MIN = 15;
export const OTP_MAX_POR_JANELA = 3;
export const CODE_TTL_MIN = 5;
export const ACCESS_TTL_S = 3600;
export const REFRESH_TTL_DIAS = 30;
export const TOOL_DEADLINE_MS = 25_000;

/**
 * Callbacks aceitos no registro (DCR). É isto que corta phishing por DCR: um
 * cliente que registre redirect para um host qualquer não recebe código.
 * Loopback (Claude Code e afins) vale em qualquer porta — o código só cai na
 * máquina de quem abriu o navegador.
 */
export const REDIRECTS_PERMITIDOS = [
    'https://claude.ai/api/mcp/auth_callback',
    'https://claude.com/api/mcp/auth_callback',
    'https://chatgpt.com/connector_platform_oauth_redirect',
];
// ChatGPT sem RFC 9207 usa uma URI por conexão. Anunciamos 9207 (URI estável acima),
// mas aceitamos o formato por conexão para não depender da escolha do cliente.
const CHATGPT_POR_CONEXAO = /^https:\/\/chatgpt\.com\/connector\/oauth\/[A-Za-z0-9_-]{1,128}$/;

export function redirectPermitido(uri: string): boolean {
    if (typeof uri !== 'string' || uri.length > 500) return false;
    if (REDIRECTS_PERMITIDOS.includes(uri) || CHATGPT_POR_CONEXAO.test(uri)) return true;
    let u: URL;
    try {
        u = new URL(uri);
    } catch {
        return false;
    }
    if (u.protocol !== 'http:') return false;
    if (!['localhost', '127.0.0.1', '[::1]'].includes(u.hostname)) return false;
    return u.username === '' && u.password === '' && u.hash === '';
}

/** O nome do cliente vem do registro (qualquer um registra): sai limpo pra mensagem e pra tela. */
export function nomeLimpo(nome: unknown): string {
    const s = String(nome ?? '').replace(/[\r\n\t*_~`<>]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60);
    return s || 'cliente sem nome';
}

export function hostDe(uri: string): string {
    try {
        const u = new URL(uri);
        return u.protocol === 'http:' ? `${u.hostname}:${u.port || '80'} (seu computador)` : u.hostname;
    } catch {
        return '?';
    }
}

// ---------- cripto ----------

export async function sha256Hex(s: string): Promise<string> {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
    return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function b64url(bytes: Uint8Array): string {
    let s = '';
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function tokenAleatorio(): string {
    return b64url(crypto.getRandomValues(new Uint8Array(32)));
}

export function codigoSeisDigitos(): string {
    // Rejeição para não enviesar: 4294967296 % 10^6 != 0.
    const lim = Math.floor(0x100000000 / 1_000_000) * 1_000_000;
    const buf = new Uint32Array(1);
    do crypto.getRandomValues(buf);
    while (buf[0] >= lim);
    return String(buf[0] % 1_000_000).padStart(6, '0');
}

export async function pkceS256(verifier: string): Promise<string> {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
    return b64url(new Uint8Array(buf));
}

/** O SQL calcula sha256(codigo || ':' || id) — este é o mesmo cálculo, do lado do TS. */
export function otpHash(codigo: string, requestId: string): Promise<string> {
    return sha256Hex(`${codigo}:${requestId}`);
}

// ---------- HTTP ----------

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
    });
}

function oauthErro(error: string, description: string, status = 400): Response {
    return json({ error, error_description: description }, status);
}

function redirect(location: string): Response {
    return new Response(null, { status: 302, headers: { Location: location, 'Cache-Control': 'no-store' } });
}

function comParams(uri: string, params: Record<string, string | undefined | null>): string {
    const u = new URL(uri);
    for (const [k, v] of Object.entries(params)) if (v != null && v !== '') u.searchParams.set(k, v);
    return u.toString();
}

/** Path depois do nome da função: /functions/v1/<funcao>/mcp e /<funcao>/mcp viram /mcp. */
export function rota(pathname: string, funcao: string): string {
    const nome = funcao.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const m = pathname.match(new RegExp(`/${nome}(/.*)?$`));
    const r = m ? (m[1] ?? '/') : pathname;
    return r.length > 1 ? r.replace(/\/+$/, '') : r;
}

async function lerCorpo(req: Request): Promise<Record<string, unknown>> {
    const tipo = req.headers.get('content-type') ?? '';
    if (tipo.includes('application/x-www-form-urlencoded')) {
        return Object.fromEntries(new URLSearchParams(await req.text()));
    }
    try {
        const b = await req.json();
        return b && typeof b === 'object' && !Array.isArray(b) ? b : {};
    } catch {
        return {};
    }
}

// ---------- handler ----------

export interface Deps {
    /** Domínio do app, onde o cliente conecta: https://app.exemplo.com.br */
    publicBase: string;
    /** Nome da edge function, para tirar o prefixo do path. */
    funcao: string;
    /** https://<ref>.supabase.co/functions/v1/<funcao> */
    urlFuncao: string;
    /** Nome que aparece no cliente, na tela de login e na mensagem do código. */
    nome: string;
    /** Frase do whoami: com que conta o MCP está ligado. Ex.: 'o dono do sistema'. */
    quem: string;
    /** `instructions` do initialize: 1 frase do que o servidor expõe. */
    instrucoes: string;
    now: () => Date;
    habilitado: () => Promise<boolean>;
    /** Entrega o código num canal que só o dono lê (WhatsApp, e-mail). true = entregou. */
    enviarCodigo: (texto: string) => Promise<boolean>;
    ferramentas: { name: string; description: string; inputSchema: Record<string, unknown> }[];
    executarFerramenta: (nome: string, args: Record<string, unknown>) => Promise<string>;
    store: {
        registrarCliente(c: { client_id: string; client_name: string; redirect_uris: string[] }): Promise<void>;
        cliente(id: string): Promise<{ client_id: string; client_name: string; redirect_uris: string[] } | null>;
        criarPedido(p: Record<string, unknown>): Promise<string>;
        pedido(id: string): Promise<Record<string, any> | null>;
        codigosEnviadosDesde(desde: Date): Promise<number>;
        gravarOtp(id: string, hash: string, enviadoEm: Date, expiraEm: Date): Promise<void>;
        consumirOtp(id: string, codigo: string): Promise<'ok' | 'invalido' | 'sem_pendente'>;
        gravarCodigo(id: string, hash: string, expiraEm: Date): Promise<void>;
        /** Atômico: marca usado e devolve o pedido só se ainda não usado e não expirado. */
        resgatarCodigo(hash: string): Promise<Record<string, any> | null>;
        gravarToken(t: Record<string, unknown>): Promise<void>;
        tokenPorAccess(hash: string): Promise<{ client_id: string } | null>;
        /** Atômico: revoga o par e devolve o client_id só se o refresh ainda vale. */
        rotacionarRefresh(hash: string): Promise<{ client_id: string } | null>;
    };
    log?: (linha: string) => void;
}

const minutos = (d: Date, m: number) => new Date(d.getTime() + m * 60_000);

/**
 * Metadados OAuth. O Vercel não reescreve /.well-known, então o que o cliente lê
 * de fato são cópias estáticas em public/.well-known/ — o teste garante que as
 * cópias batem com isto.
 */
export function metadadosRecurso(publicBase: string, nome: string) {
    const base = publicBase.replace(/\/+$/, '');
    return {
        resource: `${base}/mcp`,
        authorization_servers: [base],
        scopes_supported: [ESCOPO],
        bearer_methods_supported: ['header'],
        resource_name: nome,
    };
}

/**
 * O authorize é a única URL que o NAVEGADOR abre. Ela fica no host da função, não
 * no domínio do app: o service worker do PWA já instalado manda navegação
 * desconhecida para o index.html do SPA. Ela só responde 302 (sem HTML, que o
 * supabase.co serviria como texto) para /mcp-autorizar.html, que o SW deixa passar.
 */
export function metadadosServidor(publicBase: string, urlFuncao: string) {
    const base = publicBase.replace(/\/+$/, '');
    return {
        issuer: base,
        authorization_endpoint: `${urlFuncao.replace(/\/+$/, '')}/oauth/authorize`,
        token_endpoint: `${base}/oauth/token`,
        registration_endpoint: `${base}/oauth/register`,
        response_types_supported: ['code'],
        grant_types_supported: ['authorization_code', 'refresh_token'],
        code_challenge_methods_supported: ['S256'],
        token_endpoint_auth_methods_supported: ['none'],
        scopes_supported: [ESCOPO],
        // RFC 9207: devolvemos `iss` em toda resposta do authorize (o ChatGPT usa
        // então o callback estável).
        authorization_response_iss_parameter_supported: true,
    };
}

export function createMcpHandler(deps: Deps) {
    const base = deps.publicBase.replace(/\/+$/, '');
    const resource = `${base}/mcp`;
    const prmUrl = `${base}/.well-known/oauth-protected-resource/mcp`;
    const log = deps.log ?? ((l: string) => console.log(l));

    const prm = () => json(metadadosRecurso(base, deps.nome));
    const asMetadata = () => json(metadadosServidor(base, deps.urlFuncao));

    async function register(req: Request): Promise<Response> {
        const b = await lerCorpo(req);
        const uris = Array.isArray(b.redirect_uris) ? b.redirect_uris : [];
        if (!uris.length || uris.length > 5) return oauthErro('invalid_redirect_uri', 'redirect_uris obrigatório (1 a 5).');
        const negado = uris.find((u) => !redirectPermitido(u));
        if (negado) {
            // Primeira falha provável com um cliente novo: a linha diz qual callback falta na lista.
            log(`[mcp] registro_recusado redirect=${String(negado).slice(0, 200)}`);
            return oauthErro('invalid_redirect_uri', `redirect_uri não permitido: ${String(negado).slice(0, 120)}`);
        }
        // Só emitimos cliente público: o RFC 7591 deixa o servidor trocar o método pedido
        // e devolver o que vale, em vez de recusar o registro.
        const client = { client_id: `mcp_${tokenAleatorio()}`, client_name: nomeLimpo(b.client_name), redirect_uris: uris };
        await deps.store.registrarCliente(client);
        return json({
            ...client,
            client_id_issued_at: Math.floor(deps.now().getTime() / 1000),
            grant_types: ['authorization_code', 'refresh_token'],
            response_types: ['code'],
            token_endpoint_auth_method: 'none',
        }, 201);
    }

    async function authorize(url: URL): Promise<Response> {
        const q = url.searchParams;
        const client = await deps.store.cliente(q.get('client_id') ?? '');
        const redirectUri = q.get('redirect_uri') ?? '';
        // Sem cliente ou redirect válidos não se redireciona (RFC 6749 §4.1.2.1): erro na tela.
        if (!client) return oauthErro('invalid_client', 'Cliente desconhecido. Registre de novo.');
        if (!client.redirect_uris.includes(redirectUri)) return oauthErro('invalid_request', 'redirect_uri não registrado para este cliente.');
        const state = q.get('state');
        const falha = (error: string, desc: string) => redirect(comParams(redirectUri, { error, error_description: desc, state, iss: base }));
        if (q.get('response_type') !== 'code') return falha('unsupported_response_type', 'Só response_type=code.');
        const challenge = q.get('code_challenge') ?? '';
        if (q.get('code_challenge_method') !== 'S256' || !/^[A-Za-z0-9_-]{43}$/.test(challenge)) {
            return falha('invalid_request', 'PKCE S256 obrigatório.');
        }
        const res = q.get('resource');
        if (res && res.replace(/\/+$/, '') !== resource) return falha('invalid_target', `resource deve ser ${resource}.`);
        if (!(await deps.habilitado())) return falha('access_denied', 'O MCP está desligado.');
        const id = await deps.store.criarPedido({
            client_id: client.client_id,
            redirect_uri: redirectUri,
            state,
            scope: q.get('scope') || ESCOPO,
            code_challenge: challenge,
            expires_at: minutos(deps.now(), AUTH_REQUEST_TTL_MIN).toISOString(),
        });
        // Fragmento, não query: o id não vai para log de servidor nem Referer.
        return redirect(`${base}/mcp-autorizar.html#req=${id}`);
    }

    async function pedidoVivo(id: unknown) {
        if (typeof id !== 'string' || !/^[0-9a-f-]{36}$/i.test(id)) return null;
        const p = await deps.store.pedido(id);
        if (!p || p.approved_at || new Date(p.expires_at) <= deps.now()) return null;
        const client = await deps.store.cliente(p.client_id);
        return client ? { p, client } : null;
    }

    async function verPedido(url: URL): Promise<Response> {
        const vivo = await pedidoVivo(url.searchParams.get('id'));
        if (!vivo) return json({ error: 'pedido_expirado' }, 404);
        return json({ nome: deps.nome, cliente: vivo.client.client_name, destino: hostDe(vivo.p.redirect_uri), expira_em: vivo.p.expires_at });
    }

    async function enviarCodigo(req: Request): Promise<Response> {
        const { id } = await lerCorpo(req);
        const vivo = await pedidoVivo(id);
        if (!vivo) return json({ error: 'pedido_expirado' }, 404);
        if (!(await deps.habilitado())) return json({ error: 'desligado' }, 403);
        const agora = deps.now();
        if ((await deps.store.codigosEnviadosDesde(minutos(agora, -OTP_JANELA_MIN))) >= OTP_MAX_POR_JANELA) {
            return json({ error: 'muitos_codigos', mensagem: `Já saíram ${OTP_MAX_POR_JANELA} códigos nos últimos ${OTP_JANELA_MIN} min. Espere um pouco.` }, 429);
        }
        const codigo = codigoSeisDigitos();
        await deps.store.gravarOtp(vivo.p.id, await otpHash(codigo, vivo.p.id), agora, minutos(agora, OTP_TTL_MIN));
        const texto = [
            `Código para conectar ${vivo.client.client_name} ao ${deps.nome}: ${codigo}`,
            `Depois do login, volta para: ${hostDe(vivo.p.redirect_uri)}`,
            `Vale ${OTP_TTL_MIN} min. Se não foi você que pediu, ignore — sem o código ninguém entra.`,
        ].join('\n');
        if (!(await deps.enviarCodigo(texto))) return json({ error: 'envio_falhou' }, 502);
        log(`[mcp] codigo_enviado client=${vivo.client.client_id}`);
        return json({ ok: true });
    }

    async function verificar(req: Request): Promise<Response> {
        const { id, codigo } = await lerCorpo(req);
        const vivo = await pedidoVivo(id);
        if (!vivo) return json({ error: 'pedido_expirado' }, 404);
        if (typeof codigo !== 'string' || !/^\d{6}$/.test(codigo)) return json({ error: 'codigo_invalido' }, 400);
        const r = await deps.store.consumirOtp(vivo.p.id, codigo);
        if (r === 'sem_pendente') return json({ error: 'codigo_expirado', mensagem: 'Código expirado ou tentativas esgotadas. Peça outro.' }, 400);
        if (r !== 'ok') return json({ error: 'codigo_invalido', mensagem: 'Código errado.' }, 400);
        const code = tokenAleatorio();
        await deps.store.gravarCodigo(vivo.p.id, await sha256Hex(code), minutos(deps.now(), CODE_TTL_MIN));
        log(`[mcp] autorizado client=${vivo.client.client_id}`);
        return json({ redirect: comParams(vivo.p.redirect_uri, { code, state: vivo.p.state, iss: base }) });
    }

    async function negar(req: Request): Promise<Response> {
        const { id } = await lerCorpo(req);
        const vivo = await pedidoVivo(id);
        if (!vivo) return json({ error: 'pedido_expirado' }, 404);
        return json({ redirect: comParams(vivo.p.redirect_uri, { error: 'access_denied', state: vivo.p.state, iss: base }) });
    }

    async function emitirTokens(clientId: string): Promise<Response> {
        const access = tokenAleatorio();
        const refresh = tokenAleatorio();
        const agora = deps.now();
        await deps.store.gravarToken({
            client_id: clientId,
            access_hash: await sha256Hex(access),
            access_expires_at: new Date(agora.getTime() + ACCESS_TTL_S * 1000).toISOString(),
            refresh_hash: await sha256Hex(refresh),
            refresh_expires_at: minutos(agora, REFRESH_TTL_DIAS * 24 * 60).toISOString(),
        });
        return json({ access_token: access, token_type: 'Bearer', expires_in: ACCESS_TTL_S, refresh_token: refresh, scope: ESCOPO });
    }

    async function token(req: Request): Promise<Response> {
        const b = await lerCorpo(req);
        if (b.resource && String(b.resource).replace(/\/+$/, '') !== resource) {
            return oauthErro('invalid_target', `resource deve ser ${resource}.`);
        }
        if (b.grant_type === 'authorization_code') {
            const p = await deps.store.resgatarCodigo(await sha256Hex(String(b.code ?? '')));
            if (!p) return oauthErro('invalid_grant', 'Código inválido, expirado ou já usado.');
            if (b.client_id && b.client_id !== p.client_id) return oauthErro('invalid_grant', 'client_id não bate.');
            if (b.redirect_uri !== p.redirect_uri) return oauthErro('invalid_grant', 'redirect_uri não bate.');
            if (typeof b.code_verifier !== 'string' || (await pkceS256(b.code_verifier)) !== p.code_challenge) {
                return oauthErro('invalid_grant', 'code_verifier não bate (PKCE).');
            }
            return emitirTokens(p.client_id);
        }
        if (b.grant_type === 'refresh_token') {
            const t = await deps.store.rotacionarRefresh(await sha256Hex(String(b.refresh_token ?? '')));
            if (!t) return oauthErro('invalid_grant', 'Refresh token inválido, expirado ou já usado.');
            if (b.client_id && b.client_id !== t.client_id) return oauthErro('invalid_grant', 'client_id não bate.');
            return emitirTokens(t.client_id);
        }
        return oauthErro('unsupported_grant_type', 'Só authorization_code e refresh_token.');
    }

    function naoAutorizado(): Response {
        return json({ error: 'invalid_token', error_description: `Faça login no ${deps.nome}.` }, 401, {
            'WWW-Authenticate': `Bearer resource_metadata="${prmUrl}", scope="${ESCOPO}"`,
        });
    }

    const rpcOk = (id: unknown, result: unknown) => json({ jsonrpc: '2.0', id, result });
    const rpcErro = (id: unknown, code: number, message: string) => json({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });

    async function chamarFerramenta(id: unknown, params: any, clientId: string): Promise<Response> {
        const nome = params?.name;
        const args = params?.arguments && typeof params.arguments === 'object' ? params.arguments : {};
        // allowlist: só o que está no tools/list vira chamada.
        if (nome !== 'whoami' && !deps.ferramentas.some((f) => f.name === nome)) {
            return rpcErro(id, -32602, `Ferramenta desconhecida: ${String(nome)}`);
        }
        const t0 = Date.now();
        let status = 'ok';
        let texto: string;
        let isError = false;
        try {
            if (nome === 'whoami') {
                const c = await deps.store.cliente(clientId);
                texto = `Conectado ao ${deps.nome} como ${deps.quem}. Cliente: ${c?.client_name ?? clientId}. Acesso só de leitura.`;
            } else {
                let timer;
                const prazo = new Promise((_, rej) => { timer = setTimeout(() => rej(new Error('__timeout__')), TOOL_DEADLINE_MS); });
                try {
                    texto = await Promise.race([deps.executarFerramenta(nome, args), prazo]);
                } finally {
                    clearTimeout(timer);
                }
            }
        } catch (e) {
            const timeout = e instanceof Error && e.message === '__timeout__';
            status = timeout ? 'timeout' : 'erro';
            isError = true;
            texto = timeout ? 'A consulta demorou demais. Tente de novo ou peça um recorte menor.' : 'Falha ao consultar. Tente de novo.';
            if (!timeout) console.error('[mcp] erro', nome, e);
        }
        log(`[mcp] tool=${nome} ms=${Date.now() - t0} ${status}`);
        return rpcOk(id, { content: [{ type: 'text', text: texto || '(sem resultado)' }], isError });
    }

    async function mcp(req: Request): Promise<Response> {
        // Versão que não falamos (ex.: 2026-07-28, sem initialize): 400 sem corpo, como
        // manda o spec 2025-11-25. Um erro "moderno" (-32022) faria o cliente achar que
        // somos modernos e não cair no initialize legado.
        const versao = req.headers.get('mcp-protocol-version');
        if (versao && !PROTOCOLOS.includes(versao)) return new Response(null, { status: 400 });
        const bearer = (req.headers.get('authorization') ?? '').match(/^Bearer\s+(\S+)$/i)?.[1];
        if (!bearer) return naoAutorizado();
        const tok = await deps.store.tokenPorAccess(await sha256Hex(bearer));
        if (!tok) return naoAutorizado();
        let corpo;
        try {
            corpo = await req.json();
        } catch {
            return rpcErro(null, -32700, 'JSON inválido');
        }
        if (!corpo || typeof corpo !== 'object' || Array.isArray(corpo) || corpo.jsonrpc !== '2.0' || typeof corpo.method !== 'string') {
            return rpcErro(corpo?.id, -32600, 'Requisição JSON-RPC inválida');
        }
        const { id, method, params } = corpo;
        // Notificação (sem id): 202 sem corpo.
        if (id === undefined || id === null) return new Response(null, { status: 202 });
        // Kill switch a cada chamada: desligar corta na próxima tool, sem esperar o token expirar.
        if (!(await deps.habilitado())) return rpcErro(id, -32001, 'O MCP está desligado.');
        if (method === 'initialize') {
            const pedida = params?.protocolVersion;
            return rpcOk(id, {
                protocolVersion: PROTOCOLOS.includes(pedida) ? pedida : PROTOCOLOS[0],
                capabilities: { tools: {} },
                serverInfo: { name: deps.funcao, title: deps.nome, version: '1.0.0' },
                instructions: deps.instrucoes,
            });
        }
        if (method === 'ping') return rpcOk(id, {});
        if (method === 'tools/list') {
            const tools = [
                { name: 'whoami', description: 'Teste de conexão: diz com que conta e cliente o MCP está ligado.', inputSchema: { type: 'object', properties: {} } },
                ...deps.ferramentas,
            ].map((t) => ({ ...t, annotations: { readOnlyHint: true, openWorldHint: false } }));
            return rpcOk(id, { tools });
        }
        if (method === 'tools/call') return chamarFerramenta(id, params, tok.client_id);
        // Inclui subscriptions/listen: recusar na hora evita o stream que nunca fecha.
        return rpcErro(id, -32601, `Método não suportado: ${method}`);
    }

    return async function handle(req: Request): Promise<Response> {
        const url = new URL(req.url);
        const r = rota(url.pathname, deps.funcao);
        const m = req.method;
        try {
            if (m === 'GET' && (r === '/.well-known/oauth-protected-resource' || r === '/.well-known/oauth-protected-resource/mcp')) return prm();
            if (m === 'GET' && (r === '/.well-known/oauth-authorization-server' || r === '/.well-known/oauth-authorization-server/mcp')) return asMetadata();
            if (r === '/mcp') {
                if (m === 'POST') return await mcp(req);
                return new Response(null, { status: 405, headers: { Allow: 'POST' } });
            }
            if (m === 'POST' && r === '/oauth/register') return await register(req);
            if (m === 'GET' && r === '/oauth/authorize') return await authorize(url);
            if (m === 'POST' && r === '/oauth/token') return await token(req);
            if (m === 'GET' && r === '/oauth/pedido') return await verPedido(url);
            if (m === 'POST' && r === '/oauth/enviar-codigo') return await enviarCodigo(req);
            if (m === 'POST' && r === '/oauth/verificar') return await verificar(req);
            if (m === 'POST' && r === '/oauth/negar') return await negar(req);
            return json({ error: 'not_found' }, 404);
        } catch (e) {
            console.error('[mcp] falha', m, r, e);
            return json({ error: 'server_error' }, 500);
        }
    };
}
