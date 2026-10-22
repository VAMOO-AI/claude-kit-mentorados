# Deploy bloqueado na Vercel pelo author do commit

Sintoma: o deploy aparece como **Blocked** no painel da Vercel, sem build, com uma
mensagem do tipo *"Git author … must have access to the team …"*.

Por quê: a Vercel só constrói commit cujo **author** ela reconhece como membro do
team dono do projeto (no plano Hobby, como o dono da conta). Ela reconhece pelo
e-mail gravado no commit, que vem do `user.email` do git: esse e-mail precisa estar
verificado na conta do GitHub (ou GitLab/Bitbucket) ligada a uma conta da Vercel que
está no team, ou cadastrado na própria conta da Vercel. Commit feito com outro e-mail
(o do trabalho, o padrão da máquina, um que ninguém do team usa) é bloqueado mesmo
com o código certo — o problema é só a identidade.

Trocar o author e o committer para uma identidade que é membro do team é o conserto,
e é permitido. Confira quem está no commit e troque de um destes dois jeitos:

```bash
git log -1 --format='%an <%ae>'   # author do último commit

# só neste repositório: sem --global, o author dos seus outros projetos não muda
git config user.name  "Nome"
git config user.email "email-membro-do-team@exemplo.com"

# ou só num commit, sem mexer na config
git -c user.name="Nome" -c user.email="email-membro-do-team@exemplo.com" commit -m "..."
```

O commit bloqueado continua com o author antigo; a Vercel constrói o próximo. Faça
o commit seguinte já com a identidade certa (sem mudança pendente,
`git commit --allow-empty -m "chore: redeploy"`), confira com o mesmo
`git log -1 --format='%an <%ae>'` que ele saiu com o e-mail do team e só então dê push.
