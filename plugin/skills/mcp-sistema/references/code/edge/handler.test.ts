// supabase/functions/sistema-mcp/handler.test.ts
// @ts-nocheck
// deno test --allow-read supabase/functions/sistema-mcp/
import { assert, assertEquals, assertStringIncludes } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { createMcpHandler, metadadosRecurso, metadadosServidor, OTP_MAX_POR_JANELA, otpHash, pkceS256, redirectPermitido, rota } from './handler.ts';

const BASE = 'https://app.exemplo.com.br';
const FUNCAO = 'sistema-mcp';
const FN = `https://ref.supabase.co/functions/v1/${FUNCAO}`;
// URL da função em produção: é a que vai no authorization_endpoint dos arquivos estáticos.
const FN_PROD = `https://<ref>.supabase.co/functions/v1/${FUNCAO}`;
const NOME = 'Meu Sistema';
const CLAUDE_CB = 'https://claude.ai/api/mcp/auth_callback';

/** Store em memória com a mesma semântica do SQL (uso único, tentativas, expiração). */
function montar({ habilitado = true, ferramenta = async (n) => `resultado de ${n}` } = {}) {
    let agora = new Date('2026-10-03T12:00:00Z');
    const clientes = new Map();
    const pedidos = new Map();
    const tokens = [];
    const enviados = [];
    const estado = { habilitado };
    const store = {
        async registrarCliente(c) { clientes.set(c.client_id, c); },
        async cliente(id) { return clientes.get(id) ?? null; },
        async criarPedido(p) {
            const id = crypto.randomUUID();
            pedidos.set(id, { id, ...p, otp_attempts: 0 });
            return id;
        },
        async pedido(id) { return pedidos.get(id) ?? null; },
        async codigosEnviadosDesde(desde) {
            return [...pedidos.values()].filter((p) => p.otp_sent_at && new Date(p.otp_sent_at) > desde).length;
        },
        async gravarOtp(id, hash, enviado, expira) {
            Object.assign(pedidos.get(id), { otp_hash: hash, otp_sent_at: enviado.toISOString(), otp_expires_at: expira.toISOString(), otp_attempts: 0 });
        },
        async consumirOtp(id, codigo) {
            const p = pedidos.get(id);
            const vivo = p && !p.approved_at && p.otp_hash && new Date(p.otp_expires_at) > agora && p.otp_attempts < 3;
            if (!vivo) return 'sem_pendente';
            if (p.otp_hash === (await otpHash(codigo, id))) {
                p.approved_at = agora.toISOString();
                return 'ok';
            }
            p.otp_attempts += 1;
            return 'invalido';
        },
        async gravarCodigo(id, hash, expira) { Object.assign(pedidos.get(id), { code_hash: hash, code_expires_at: expira.toISOString() }); },
        async resgatarCodigo(hash) {
            const p = [...pedidos.values()].find((x) => x.code_hash === hash && !x.code_used_at && new Date(x.code_expires_at) > agora);
            if (!p) return null;
            p.code_used_at = agora.toISOString();
            return p;
        },
        async gravarToken(t) { tokens.push({ ...t }); },
        async tokenPorAccess(hash) {
            const t = tokens.find((x) => x.access_hash === hash && !x.revoked_at && new Date(x.access_expires_at) > agora);
            return t ? { client_id: t.client_id } : null;
        },
        async rotacionarRefresh(hash) {
            const t = tokens.find((x) => x.refresh_hash === hash && !x.revoked_at && new Date(x.refresh_expires_at) > agora);
            if (!t) return null;
            t.revoked_at = agora.toISOString();
            return { client_id: t.client_id };
        },
    };
    const handle = createMcpHandler({
        publicBase: BASE,
        funcao: FUNCAO,
        urlFuncao: FN,
        nome: NOME,
        quem: 'o dono do sistema',
        instrucoes: 'Leitura do sistema. Só leitura.',
        now: () => agora,
        habilitado: async () => estado.habilitado,
        enviarCodigo: async (texto) => { enviados.push(texto); return true; },
        ferramentas: [{ name: 'tarefas_listar', description: 'tarefas', inputSchema: { type: 'object', properties: {} } }],
        executarFerramenta: ferramenta,
        store,
        log: () => {},
    });
    return { handle, enviados, estado, pedidos, avancar: (min) => { agora = new Date(agora.getTime() + min * 60_000); } };
}

const post = (path, body, headers = {}) => new Request(`${FN}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
});
const get = (path) => new Request(`${FN}${path}`);
const rpc = (token, method, params, id = 1) => post('/mcp', { jsonrpc: '2.0', id, method, params }, { authorization: `Bearer ${token}` });

async function registrar(h, redirect = CLAUDE_CB, nome = 'Claude') {
    const r = await h.handle(post('/oauth/register', { redirect_uris: [redirect], client_name: nome, token_endpoint_auth_method: 'none' }));
    assertEquals(r.status, 201);
    return (await r.json()).client_id;
}

async function pedir(h, clientId, verifier = 'v'.repeat(50), extra = {}) {
    const q = new URLSearchParams({
        response_type: 'code', client_id: clientId, redirect_uri: CLAUDE_CB, state: 'st4te',
        code_challenge: await pkceS256(verifier), code_challenge_method: 'S256', resource: `${BASE}/mcp`, ...extra,
    });
    return h.handle(get(`/oauth/authorize?${q}`));
}

const reqId = (r) => r.headers.get('location').split('#req=')[1];
const codigoEnviado = (h) => h.enviados.at(-1).match(/: (\d{6})\n/)[1];

/** Login inteiro até o access token. */
async function login(h, verifier = 'v'.repeat(50)) {
    const clientId = await registrar(h);
    const id = reqId(await pedir(h, clientId, verifier));
    await h.handle(post('/oauth/enviar-codigo', { id }));
    const v = await (await h.handle(post('/oauth/verificar', { id, codigo: codigoEnviado(h) }))).json();
    const code = new URL(v.redirect).searchParams.get('code');
    const t = await h.handle(post('/oauth/token', { grant_type: 'authorization_code', code, redirect_uri: CLAUDE_CB, client_id: clientId, code_verifier: verifier }));
    return { clientId, code, ...(await t.json()) };
}

Deno.test('rota tira o prefixo da função nos dois formatos de URL', () => {
    assertEquals(rota(`/functions/v1/${FUNCAO}/mcp`, FUNCAO), '/mcp');
    assertEquals(rota(`/${FUNCAO}/oauth/token`, FUNCAO), '/oauth/token');
    assertEquals(rota(`/${FUNCAO}`, FUNCAO), '/');
});

Deno.test('metadados anunciam o domínio público, não o host do supabase', async () => {
    const h = montar();
    for (const p of ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp']) {
        const prm = await (await h.handle(get(p))).json();
        assertEquals(prm.resource, `${BASE}/mcp`);
        assertEquals(prm.authorization_servers, [BASE]);
    }
    const as = await (await h.handle(get('/.well-known/oauth-authorization-server'))).json();
    assertEquals(as.issuer, BASE);
    assertEquals(as.registration_endpoint, `${BASE}/oauth/register`);
    // Navegação do navegador: fora do domínio do app, longe do service worker.
    assertEquals(as.authorization_endpoint, `${FN}/oauth/authorize`);
    assertEquals(as.code_challenge_methods_supported, ['S256']);
});

Deno.test('MCP sem token responde 401 apontando os metadados do recurso', async () => {
    const h = montar();
    const r = await h.handle(post('/mcp', { jsonrpc: '2.0', id: 1, method: 'initialize' }));
    assertEquals(r.status, 401);
    assertStringIncludes(r.headers.get('www-authenticate'), `resource_metadata="${BASE}/.well-known/oauth-protected-resource/mcp"`);
    const r2 = await h.handle(rpc('token-inventado', 'tools/list'));
    assertEquals(r2.status, 401);
});

Deno.test('GET no /mcp é 405: nada de stream aberto', async () => {
    const r = await montar().handle(get('/mcp'));
    assertEquals(r.status, 405);
});

Deno.test('registro recusa callback fora da lista e aceita Claude, ChatGPT e loopback', async () => {
    assert(redirectPermitido(CLAUDE_CB));
    assert(redirectPermitido('https://chatgpt.com/connector_platform_oauth_redirect'));
    assert(redirectPermitido('https://chatgpt.com/connector/oauth/abc_123'));
    assert(!redirectPermitido('https://chatgpt.com/connector/oauth/abc/../../evil'));
    assert(redirectPermitido('http://127.0.0.1:41235/callback'));
    assert(redirectPermitido('http://localhost:53682/callback'));
    assert(redirectPermitido('http://127.0.0.1:9999/cb'));
    assert(!redirectPermitido('https://evil.com/cb'));
    assert(!redirectPermitido('https://claude.ai.evil.com/api/mcp/auth_callback'));
    assert(!redirectPermitido('https://localhost/cb'));
    assert(!redirectPermitido('http://localhost.evil.com/cb'));
    const r = await montar().handle(post('/oauth/register', { redirect_uris: ['https://evil.com/cb'] }));
    assertEquals(r.status, 400);
    assertEquals((await r.json()).error, 'invalid_redirect_uri');
});

Deno.test('fluxo completo: código ao dono → token → initialize, tools/list e whoami', async () => {
    const h = montar();
    const clientId = await registrar(h, CLAUDE_CB, 'Claude *bold*\nfalso');
    const a = await pedir(h, clientId);
    assertEquals(a.status, 302);
    // startsWith, não RegExp montada com BASE: o ponto do domínio casaria qualquer caractere.
    assert(a.headers.get('location').startsWith(`${BASE}/mcp-autorizar.html#req=`));
    const id = reqId(a);

    const info = await (await h.handle(get(`/oauth/pedido?id=${id}`))).json();
    assertEquals(info.destino, 'claude.ai');
    assertEquals(info.nome, NOME);

    assertEquals((await h.handle(post('/oauth/enviar-codigo', { id }))).status, 200);
    const msg = h.enviados.at(-1);
    assertStringIncludes(msg, 'claude.ai');
    assert(!msg.includes('\nfalso'), 'nome do cliente não injeta linha na mensagem');

    const errado = await h.handle(post('/oauth/verificar', { id, codigo: '000000' === codigoEnviado(h) ? '111111' : '000000' }));
    assertEquals(errado.status, 400);

    const v = await (await h.handle(post('/oauth/verificar', { id, codigo: codigoEnviado(h) }))).json();
    const volta = new URL(v.redirect);
    assertEquals(volta.origin + volta.pathname, CLAUDE_CB);
    assertEquals(volta.searchParams.get('state'), 'st4te');
    assertEquals(volta.searchParams.get('iss'), BASE);
    const code = volta.searchParams.get('code');

    const ruim = await h.handle(post('/oauth/token', { grant_type: 'authorization_code', code, redirect_uri: CLAUDE_CB, client_id: clientId, code_verifier: 'x'.repeat(50) }));
    assertEquals((await ruim.json()).error, 'invalid_grant');

    // O resgate do code é atômico e vem antes da conferência do PKCE: um verifier errado
    // queima o code, e o cliente precisa logar de novo.
    const de_novo = await h.handle(post('/oauth/token', { grant_type: 'authorization_code', code, redirect_uri: CLAUDE_CB, client_id: clientId, code_verifier: 'v'.repeat(50) }));
    assertEquals((await de_novo.json()).error, 'invalid_grant');

    const s = await login(h);
    assertEquals(s.token_type, 'Bearer');
    const init = await (await h.handle(rpc(s.access_token, 'initialize', { protocolVersion: '2025-06-18' }))).json();
    assertEquals(init.result.protocolVersion, '2025-06-18');
    const lista = await (await h.handle(rpc(s.access_token, 'tools/list'))).json();
    assertEquals(lista.result.tools.map((t) => t.name), ['whoami', 'tarefas_listar']);
    assert(lista.result.tools.every((t) => t.annotations.readOnlyHint === true));
    const quem = await (await h.handle(rpc(s.access_token, 'tools/call', { name: 'whoami', arguments: {} }))).json();
    assertStringIncludes(quem.result.content[0].text, 'só de leitura');
    const t = await (await h.handle(rpc(s.access_token, 'tools/call', { name: 'tarefas_listar', arguments: {} }))).json();
    assertEquals(t.result.content[0].text, 'resultado de tarefas_listar');
});

Deno.test('initialize com versão desconhecida no corpo recebe a mais nova que o servidor fala', async () => {
    const h = montar();
    const s = await login(h);
    const init = await (await h.handle(rpc(s.access_token, 'initialize', { protocolVersion: '2099-01-01' }))).json();
    assertEquals(init.result.protocolVersion, '2025-11-25');
});

Deno.test('authorization code é de uso único', async () => {
    const h = montar();
    const s = await login(h);
    const r = await h.handle(post('/oauth/token', { grant_type: 'authorization_code', code: s.code, redirect_uri: CLAUDE_CB, client_id: s.clientId, code_verifier: 'v'.repeat(50) }));
    assertEquals((await r.json()).error, 'invalid_grant');
});

Deno.test('refresh rotaciona e o par antigo morre inteiro', async () => {
    const h = montar();
    const s = await login(h);
    const r1 = await (await h.handle(post('/oauth/token', { grant_type: 'refresh_token', refresh_token: s.refresh_token, client_id: s.clientId }))).json();
    assert(r1.access_token && r1.access_token !== s.access_token);
    const r2 = await (await h.handle(post('/oauth/token', { grant_type: 'refresh_token', refresh_token: s.refresh_token }))).json();
    assertEquals(r2.error, 'invalid_grant');
    assertEquals((await h.handle(rpc(s.access_token, 'tools/list'))).status, 401);
    assertEquals((await h.handle(rpc(r1.access_token, 'tools/list'))).status, 200);
});

Deno.test('token aceita corpo form-urlencoded (padrão OAuth)', async () => {
    const h = montar();
    const s = await login(h);
    const r = await h.handle(new Request(`${FN}/oauth/token`, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: s.refresh_token }).toString(),
    }));
    assertEquals(r.status, 200);
});

Deno.test('access token expira em 1h', async () => {
    const h = montar();
    const s = await login(h);
    h.avancar(61);
    assertEquals((await h.handle(rpc(s.access_token, 'tools/list'))).status, 401);
});

Deno.test('três códigos errados queimam o pedido', async () => {
    const h = montar();
    const clientId = await registrar(h);
    const id = reqId(await pedir(h, clientId));
    await h.handle(post('/oauth/enviar-codigo', { id }));
    const certo = codigoEnviado(h);
    const errado = certo === '123456' ? '654321' : '123456';
    for (let i = 0; i < 3; i++) await h.handle(post('/oauth/verificar', { id, codigo: errado }));
    const r = await (await h.handle(post('/oauth/verificar', { id, codigo: certo }))).json();
    assertEquals(r.error, 'codigo_expirado');
});

Deno.test('código expira em 5 min', async () => {
    const h = montar();
    const clientId = await registrar(h);
    const id = reqId(await pedir(h, clientId));
    await h.handle(post('/oauth/enviar-codigo', { id }));
    h.avancar(6);
    const r = await (await h.handle(post('/oauth/verificar', { id, codigo: codigoEnviado(h) }))).json();
    assertEquals(r.error, 'codigo_expirado');
});

Deno.test('freio de spam: no máximo 3 códigos por 15 min', async () => {
    const h = montar();
    const clientId = await registrar(h);
    for (let i = 0; i < OTP_MAX_POR_JANELA; i++) {
        const id = reqId(await pedir(h, clientId));
        assertEquals((await h.handle(post('/oauth/enviar-codigo', { id }))).status, 200);
    }
    const id = reqId(await pedir(h, clientId));
    assertEquals((await h.handle(post('/oauth/enviar-codigo', { id }))).status, 429);
    assertEquals(h.enviados.length, OTP_MAX_POR_JANELA);
});

Deno.test('authorize recusa sem PKCE S256 e não redireciona para callback não registrado', async () => {
    const h = montar();
    const clientId = await registrar(h);
    const plain = await pedir(h, clientId, 'v'.repeat(50), { code_challenge_method: 'plain' });
    assertEquals(new URL(plain.headers.get('location')).searchParams.get('error'), 'invalid_request');
    const outro = await pedir(h, clientId, 'v'.repeat(50), { redirect_uri: 'http://localhost:1/cb' });
    assertEquals(outro.status, 400);
    assertEquals(outro.headers.get('location'), null);
    const res = await pedir(h, clientId, 'v'.repeat(50), { resource: 'https://outro.com/mcp' });
    assertEquals(new URL(res.headers.get('location')).searchParams.get('error'), 'invalid_target');
});

Deno.test('kill switch: desligado não faz login nem responde tool', async () => {
    const h = montar();
    const s = await login(h);
    h.estado.habilitado = false;
    const clientId = await registrar(h);
    const a = await pedir(h, clientId);
    assertEquals(new URL(a.headers.get('location')).searchParams.get('error'), 'access_denied');
    const r = await (await h.handle(rpc(s.access_token, 'tools/call', { name: 'whoami' }))).json();
    assertEquals(r.error.code, -32001);
});

Deno.test('ferramenta fora da lista e subscriptions/listen são recusadas na hora', async () => {
    const h = montar();
    const s = await login(h);
    assertEquals((await (await h.handle(rpc(s.access_token, 'tools/call', { name: 'enviar_mensagem' }))).json()).error.code, -32602);
    assertEquals((await (await h.handle(rpc(s.access_token, 'subscriptions/listen', {}))).json()).error.code, -32601);
    assertEquals((await h.handle(post('/mcp', { jsonrpc: '2.0', method: 'notifications/initialized' }, { authorization: `Bearer ${s.access_token}` }))).status, 202);
});

Deno.test('erro da ferramenta não vaza stack', async () => {
    const h = montar({ ferramenta: async () => { throw new Error('relation "segredo" does not exist'); } });
    const s = await login(h);
    const r = await (await h.handle(rpc(s.access_token, 'tools/call', { name: 'tarefas_listar' }))).json();
    assertEquals(r.result.isError, true);
    assert(!r.result.content[0].text.includes('segredo'));
});

Deno.test('pedido aprovado não pode ser reaproveitado', async () => {
    const h = montar();
    const clientId = await registrar(h);
    const id = reqId(await pedir(h, clientId));
    await h.handle(post('/oauth/enviar-codigo', { id }));
    await h.handle(post('/oauth/verificar', { id, codigo: codigoEnviado(h) }));
    assertEquals((await h.handle(post('/oauth/enviar-codigo', { id }))).status, 404);
    assertEquals((await h.handle(get(`/oauth/pedido?id=${id}`))).status, 404);
});

Deno.test('metadados estáticos do Vercel batem com o handler (o Vercel não reescreve /.well-known)', async () => {
    const pub = new URL('../../../public/.well-known/', import.meta.url);
    const as = JSON.parse(await Deno.readTextFile(new URL('oauth-authorization-server', pub)));
    const prm = JSON.parse(await Deno.readTextFile(new URL('oauth-protected-resource/mcp', pub)));
    assertEquals(as, metadadosServidor(BASE, FN_PROD));
    assertEquals(prm, metadadosRecurso(BASE, NOME));
    assertEquals(as.authorization_response_iss_parameter_supported, true);
});

Deno.test('cliente 2026-07-28 sem initialize recebe 400 vazio e cai no handshake legado', async () => {
    const h = montar();
    const r = await h.handle(new Request(`${FN}/mcp`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'mcp-protocol-version': '2026-07-28' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'server/discover' }),
    }));
    assertEquals(r.status, 400);
    assertEquals(await r.text(), '');
    const s = await login(h);
    const ok = await h.handle(new Request(`${FN}/mcp`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'mcp-protocol-version': '2025-06-18', authorization: `Bearer ${s.access_token}` },
        body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
    }));
    assertEquals(ok.status, 200);
});

Deno.test('authorize devolve iss (RFC 9207) também no erro', async () => {
    const h = montar();
    const clientId = await registrar(h);
    const r = await pedir(h, clientId, 'v'.repeat(50), { code_challenge_method: 'plain' });
    assertEquals(new URL(r.headers.get('location')).searchParams.get('iss'), BASE);
});

Deno.test('token recusa resource de outro servidor (RFC 8707)', async () => {
    const h = montar();
    const s = await login(h);
    const r = await (await h.handle(post('/oauth/token', { grant_type: 'refresh_token', refresh_token: s.refresh_token, resource: 'https://outro.com/mcp' }))).json();
    assertEquals(r.error, 'invalid_target');
    const ok = await h.handle(post('/oauth/token', { grant_type: 'refresh_token', refresh_token: s.refresh_token, resource: `${BASE}/mcp` }));
    assertEquals(ok.status, 200);
});

Deno.test('registro pedindo client_secret_basic vira cliente público em vez de falhar', async () => {
    const r = await montar().handle(post('/oauth/register', { redirect_uris: [CLAUDE_CB], token_endpoint_auth_method: 'client_secret_basic' }));
    assertEquals(r.status, 201);
    assertEquals((await r.json()).token_endpoint_auth_method, 'none');
});
