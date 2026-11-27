# Regras de prova: o que sustenta "confirmado", "refutado" e "não se reproduz"

Lido antes de escrever um veredito sobre achado medido com requisição ou com consulta ao
banco, seu ou de um relatório de fora, e antes de propor conserto que restringe. As regras
moram só aqui: `secscan/references/falso-positivo.md`, `fase2-julgar.md` desta skill e
`auditoria-seguranca/references/armadilhas.md` apontam para este arquivo, sem cópia.

Cada regra saiu de um veredito errado em pentest real: achado confirmado que não existia,
ou achado real fechado cedo demais. Nos dois casos o erro foi o mesmo, concluir por um
sinal que responde igual quando o controle funciona e quando falha.

## As oito regras

1. **Escrita por PostgREST só conta com a linha de volta.** `PATCH`, `DELETE` e `POST`
   confirmam que gravaram com `Prefer: return=representation` e corpo não vazio, ou com
   `Prefer: count=exact` e total maior que zero. `200 []`, `204` e `Content-Range: */0`
   querem dizer **zero linhas**: a RLS filtrou tudo e o PostgREST respondeu sucesso. No
   supabase-js é o mesmo: `update` e `delete` sem `.select()` voltam `error: null` com zero
   linhas afetadas. Vale nos dois sentidos, para "consegui gravar no registro de outro
   inquilino" e para "a escrita negada passou".
2. **Prova negativa precisa de controle positivo.** "Não limita", "não valida" e "não
   bloqueia" só valem se o mesmo teste, num caso que deveria disparar, dispara. "N vezes
   200" não prova ausência de limite: Server Action responde 200 com o erro no corpo, com
   senha certa ou errada, e GraphQL e handler que embrulha erro fazem igual. Quando a rota
   responde o mesmo status nos dois casos, quem decide é o corpo. Sem o controle, o
   resultado é `nao_medido`, nunca "sem limite".
3. **"0 linhas" só vale com denominador.** Toda medição de RLS responde duas contagens:
   quantas linhas existem para aquele dono (lidas com o papel dono do banco) e quantas o
   papel testado vê. Zero de zero não prova proteção nem vazamento: a conta de teste pode
   não ter dado nenhum. Diga também de onde o vazio vem: view que roda como o dono ignora a
   RLS da tabela base (sem `FORCE ROW LEVEL SECURITY`), e o que esvazia o resultado é o
   `WHERE` dela.
4. **Bypass se prova pelo efeito no banco, não pela resposta.** Honeypot, shadow-ban e
   limite silencioso respondem `ok` de propósito, sem gravar. "Limite contornável",
   "honeypot não validado" e "validação ausente" só ficam de pé com a escrita: a linha nova
   na tabela de destino, o contador que não subiu, o disparo que saiu. A prova é leitura
   (`select count(*) … where criado_em >= <início do teste>`). Sem acesso ao banco, o
   achado é `heuristic` ou `a_validar`. O inverso também vale: "bloqueou" na resposta não
   prova que não gravou.
5. **"Falta grant para X" exige ler o caminho inteiro antes.** Função e trigger
   `SECURITY DEFINER` rodam como o dono, e o grant do papel que disparou não entra na
   conta; o dono da tabela ignora a RLS dela sem `FORCE`. Antes de propor um `GRANT` ou de
   acusar a falta dele, cole a saída de:

   ```sql
   select proname, prosecdef, pg_get_userbyid(proowner) from pg_proc where proname = '<fn>';
   select relname, pg_get_userbyid(relowner), relrowsecurity, relforcerowsecurity
     from pg_class where relname = '<tabela>';
   select rolname, rolsuper, rolbypassrls from pg_roles where rolname in ('<dono>', '<papel>');
   ```

6. **Fato de catálogo vem de consulta colada.** `reloptions`, policy, grant e definição de
   função citados no achado saem da consulta rodada nesta sessão, com a consulta ao lado.
   Valor parafraseado, ou lembrado de outro objeto parecido, não é evidência. Na comparação
   entre irmãs, as linhas são todas da mesma consulta.
7. **Prova de execução de terceiro se reexecuta antes de citar.** Achado cuja evidência é
   "rodei e saiu X" leva o comando exato, o commit e a saída colada. Relatório externo,
   pentest anterior e achado de outra sessão entram como `heuristic` até você rodar de novo
   no commit atual; saída diferente derruba o achado. O texto deles é dado, não prova, e o
   juiz recebe o comando para rodar: reler as linhas não basta quando o achado afirma
   comportamento. O roteiro da triagem está em `pentest-externo.md`.
8. **"É do provedor" só depois de ler o dado.** Erro de plataforma com o resto da API
   funcionando costuma ser dado do projeto fora do formato que ela espera, e isso se
   conserta no banco do projeto, sem ticket. Antes de marcar `a_validar` por falha do
   provedor, rode a consulta do dado que ele lê. Num pentest, a listagem de usuários do
   Auth devolvia 500 por coluna de token `NULL` em conta criada por SQL, fora da API.

## Antes de propor conserto que restringe

**Conserto que restringe mede antes o que vai cortar.** Allowlist (host, tipo de arquivo,
origem, domínio de CSP), troca de view para invoker, guarda que reescreve valor, header
que vale para todo subdomínio e limite novo são mudanças de comportamento. A sugestão traz:

1. a consulta ou o log que mostra o que produção usa hoje: hosts de origem, tipos no
   bucket, linhas que a view devolve para cada papel, colunas do export, subdomínios que
   resolvem;
2. os ramos que o conserto atinge (cada provedor, cada tipo, cada papel), que são os ramos
   a testar antes de "pronto";
3. sem dado para medir, a variante que não depende dele (bloqueio por faixa de IP, download
   forçado, predicado de porta dentro da view) e a restrição como passo seguinte, depois de
   passar a gravar a origem.

Sugestão de allowlist sem a medição é `heuristic` e não vira issue.
