<!-- secscan: lido na Fase 2.5, ao avaliar C4 (upload) -->

## C4 — Upload: tipo, tamanho e quem serve o arquivo

> Ponto de partida: skill `offensive-file-upload` de `SnailSploit/Claude-Red` (MIT). Comandos e
> critérios reescritos para Supabase Storage e Next.

O limite de entrada da Fase 2.5 cobra "tamanho e tipo de upload"; esta página diz onde olhar. A
chave do objeto montada com input é a C1.4, e bucket público com dado de usuário é a Fase 2.

```bash
grep -rnE "storage\.from\([^)]*\)\.(upload|uploadToSignedUrl|createSignedUploadUrl)|formData\(\)|multipart|busboy|formidable|multer" \
  src app supabase/functions 2>/dev/null
grep -nE 'allowed_mime_types|file_size_limit' supabase/config.toml supabase/migrations/*.sql 2>/dev/null
```

```sql
-- O banco vivo vence a migration (mesma regra da Fase 2)
select id, public, file_size_limit, allowed_mime_types from storage.buckets order by id;
```

O que é achado:

- **Bucket que recebe upload de usuário sem `allowed_mime_types` ou sem `file_size_limit`**, no
  banco vivo ou, sem acesso a ele, no `config.toml` e nas migrations. Sem os dois, vale qualquer
  tipo até o teto global do projeto. `MEDIUM`.
- **Tipo decidido pelo cliente.** `file.type`, o `contentType` repassado do browser e a extensão
  do nome são o que o cliente declarou. Validação que só olha isso não é validação: o servidor
  confere os bytes iniciais do arquivo, ou o bucket recusa pelo `allowed_mime_types`. Upload
  direto do browser para o Storage só tem o limite do bucket e as policies de `storage.objects`;
  checagem no componente React é UX.
- **SVG ou HTML aceitos.** SVG executa script quando aberto como documento. O impacto depende de
  **quem serve o arquivo**, e esse é o discriminante:
  - pelo origin do app (route handler que lê do Storage e devolve o corpo, `rewrites` do
    `next.config` apontando para o Storage): XSS armazenado com a sessão do usuário. `HIGH`;
  - por um subdomínio do mesmo site (domínio próprio apontado para o Supabase): `MEDIUM`, e
    `HIGH` se o cookie de sessão sai com `Domain=` do site inteiro;
  - direto de `*.supabase.co`: o script roda num origin sem a sessão do app; sobra hospedar
    conteúdo e phishing num domínio confiável. `LOW`.

  Não presuma que o Storage neutraliza SVG: a doc não garante o `Content-Type` com que ele serve
  cada tipo. Ache no código como o arquivo chega ao usuário e diga isso no finding.
- **Nome do arquivo devolvido ao usuário** (`Content-Disposition`, nome exibido) montado com o
  nome original sem sanitizar.
- **Arquivo processado no servidor** (imagem redimensionada, PDF lido, planilha importada, áudio
  convertido): exige limite de tamanho **antes** de processar e timeout. A versão do parser é da
  Fase 4.
- **Upload sem dono**: rota, ou policy de `insert` em `storage.objects`, aceitando `anon` sem
  motivo de produto. A policy em si é da Fase 2; aqui o achado é o boundary aberto. `HIGH` se o
  bucket é público, porque vira hospedagem grátis de qualquer arquivo.
