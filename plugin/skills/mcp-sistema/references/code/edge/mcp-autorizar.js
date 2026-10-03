/* global URLSearchParams, location, document, fetch */
// public/mcp-autorizar.js — tela de login do MCP. O id do pedido vem no fragmento
// (#req=…), que não vai para log de servidor nem Referer. Fala com /oauth/* do mesmo
// domínio (rewrite para a edge function) e termina com location.assign — form POST +
// 302 cross-origin esbarraria no `form-action 'self'` da CSP do app.
(function () {
  var id = new URLSearchParams(location.hash.slice(1)).get('req') || '';
  var $ = function (s) { return document.getElementById(s); };
  var msg = function (texto, tipo) { var m = $('msg'); m.textContent = texto || ''; m.className = 'msg' + (tipo ? ' ' + tipo : ''); };

  function api(caminho, corpo) {
    var init = corpo ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) } : {};
    return fetch('/oauth/' + caminho, init).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (b) { b._status = r.status; return b; });
    });
  }

  function expirado() {
    $('carregando').hidden = true;
    $('pedido').hidden = true;
    msg('Este pedido expirou ou já foi usado. Volte ao app e conecte de novo.', 'erro');
  }

  if (!/^[0-9a-f-]{36}$/i.test(id)) return expirado();

  api('pedido?id=' + encodeURIComponent(id)).then(function (b) {
    if (b._status !== 200) return expirado();
    if (b.nome) { $('titulo').textContent = 'Conectar ao ' + b.nome; document.title = $('titulo').textContent; }
    $('cliente').textContent = b.cliente;
    $('destino').textContent = b.destino;
    $('carregando').hidden = true;
    $('pedido').hidden = false;
  }, expirado);

  $('enviar').addEventListener('click', function () {
    $('enviar').disabled = true;
    msg('Enviando…');
    api('enviar-codigo', { id: id }).then(function (b) {
      if (b._status === 200) {
        $('passo-enviar').hidden = true;
        $('passo-codigo').hidden = false;
        $('codigo').focus();
        msg('Código enviado. Vale 5 minutos.', 'ok');
      } else if (b._status === 404) {
        expirado();
      } else {
        $('enviar').disabled = false;
        msg(b.mensagem || (b.error === 'desligado' ? 'O MCP está desligado.' : 'Não consegui enviar o código. Tente de novo.'), 'erro');
      }
    }, function () { $('enviar').disabled = false; msg('Falha de rede. Tente de novo.', 'erro'); });
  });

  $('passo-codigo').addEventListener('submit', function (e) {
    e.preventDefault();
    var codigo = $('codigo').value.replace(/\D/g, '');
    if (codigo.length !== 6) return msg('São 6 dígitos.', 'erro');
    $('confirmar').disabled = true;
    msg('Conferindo…');
    api('verificar', { id: id, codigo: codigo }).then(function (b) {
      if (b._status === 200 && b.redirect) {
        msg('Conectado. Voltando para o app…', 'ok');
        location.assign(b.redirect);
      } else if (b._status === 404) {
        expirado();
      } else {
        $('confirmar').disabled = false;
        $('codigo').value = '';
        msg(b.mensagem || 'Código errado.', 'erro');
        if (b.error === 'codigo_expirado') { $('passo-codigo').hidden = true; $('passo-enviar').hidden = false; $('enviar').disabled = false; }
      }
    }, function () { $('confirmar').disabled = false; msg('Falha de rede. Tente de novo.', 'erro'); });
  });

  $('negar').addEventListener('click', function () {
    api('negar', { id: id }).then(function (b) {
      if (b.redirect) location.assign(b.redirect); else expirado();
    }, expirado);
  });
})();
