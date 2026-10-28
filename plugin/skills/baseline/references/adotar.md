# baseline — Adotar num repo pela primeira vez

Lido quando o repo ainda não tem `.context/docs/baseline.md` e vai passar pela primeira auditoria.
Os passos citam o Modo AUDITAR e o Modo CONSTRUIR do SKILL.md.

Uma sessão por repo. O primeiro custa mais porque você calibra o julgamento; os
seguintes são rápidos porque o método já está no lugar.

**1–3. Meça** com o bloco do Modo AUDITAR, da raiz do repo.

**4. Escreva o contrato** em `.context/docs/baseline.md`, de
`references/contrato-template.md`. É aqui que está o trabalho de verdade — os
scripts só medem. Preencha nesta ordem:

1. **Superfícies e ambientes.** Se não há staging, escreva isso: muda como tudo
   no repo é feito, e quem chega depois precisa saber.
2. **Estado por pilar**, com a prova ao lado. O que não mediu fica `nao_medido`.
3. **Inventário de segredos** — a coluna que decide prioridade é *raio de dano*.
4. **Gates de UI e contrapartidas.** Para cada gate, meça se o banco também nega
   (ver `03-auth.md`); marque `real` ou `cosmético`. Cosmético não é acusação, é
   informação — o risco é não saber qual dos seus gates é.
5. **Exceções aceitas**, com motivo, dono e data de revisão (o passo 5 do Modo CONSTRUIR).
6. **Backlog por custo × risco**, não por pilar.

**5. Julgue o report contra o contrato** (fase 2) e **6. reconfira** rodando os
comandos de reconferência dos itens que fechou.

### O que esperar do primeiro run

- **Falso positivo é normal e é informação.** Detector que acusa depois do bug
  corrigido treina a ignorar o gate — corrija o detector, não o sintoma. Se for
  específico do projeto, registre em `.context/docs/security/vereditos.md`.
- **Achado que some quando você corrige** é o único que prova que o gate funciona.
  Por isso a fase 4 existe.
- **O que o script mede vence o que o repo sugere.** Grep em migration responde
  "o que foi escrito"; o banco responde "o que está valendo". Já divergiu por
  mais do dobro num projeto real.

### Ordem sugerida de adoção

Por exposição, não por afinidade: cliente em produção primeiro, protótipo por
último. Um repo por sessão — o contrato do primeiro serve de modelo para os
outros, e emendar dois na mesma sessão só encarece o contexto.
