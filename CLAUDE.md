# CLAUDE.md — auditoria-seguranca

Kit/guia de segurança do INEMA (23/10/2026): como atualizar cada camada, como auditar com `audita.sh` (teste de conexão real, não altera nada; é levantamento, não certificado), caso real (eMudhra) e PHP2Shell.

- Repo: `inematds/auditoria-seguranca` (público). Commits com autor `inematds <inematds@gmail.com>`.
- Guia: `guia/index.html` (PT, fonte) + `guia/en/` + `guia/es/`; GitHub Pages por Actions (`.github/workflows/pages.yml`). Push de mudança no workflow: por SSH (`git push git@github.com:inematds/auditoria-seguranca.git main`).
- Versão: arquivo `VERSION` é a fonte; `python3 ferramentas/versao.py X.Y.Z` atualiza audita.sh, capa/rodapé do guia (`data-v`) e README. CHANGELOG.md à mão.
- `audita.sh` **não altera nada**: nunca instalar, alterar ou gravar nada nas máquinas auditadas (mas executa as ferramentas que testa). Estados EXPOSTO / protegido / SEM TESTE / VERIFIQUE / REINICIE.
- **Teste que não terminou ou não prova nada = SEM TESTE e saída ≠ 0** (1.1.2): SSH ≠ 0/1/2/3, container sem shell/sem ferramenta/timeout/sem `__FIM_SONDA__`, `php -v` vazio, find cortado, docker sem permissão. "protegido" só por código/mensagem de verificação (curl 60/51, wget 5) ou, no busybox, pela lista do sistema sem a raiz daquela cadeia — nunca por dedução (site de controle abriu, palavra "certif" na mensagem). Saída 0 vale só dentro do escopo impresso.
- **Executar binário achado no disco só se `ok_exec` aprovar** (arquivo, cada link e cada pasta do root/dono, sem gravação de outros; grupo pessoal aceito); com root, binário de usuário roda via `runuser` como o dono. Guardar `$?` numa variável ANTES de qualquer `echo`; variáveis das funções do host com `local` (os laços usam `p`, `n`, `d`).
- Mudou o `audita.sh` → `bash testes/roda.sh` (stubs, sem rede) tem de dar 0 falhas, e rodar de verdade `--rapido` comparando os EXPOSTO com a versão anterior.
- Nada de IP, hostname ou nome de cliente no repo (caso real anonimizado). Lista de servidores (`servidores.txt`) fica fora do git.
- Fatos só de fontes oficiais (php.net, Mozilla, Google, emudhra.we-have-a-problem.com, SOCRadar). Não citar vídeos de terceiros.
- Mudou o PT → retraduzir EN/ES com `inema-traduz` e conferir.

## O processo, do início ao fim

Ver a seção de mesmo nome no [README.md](README.md).

## Self-learning

When I correct you, or you catch yourself making a mistake: before continuing, add the lesson as a one-line rule at the TOP of the Lessons section below, so it never happens again.

## Lessons

- Não editar o `audita.sh` enquanto ele roda (o bash lê o arquivo aos poucos): testar sempre numa cópia. (23/10/2026)
- No Linux o Go segue a lista do sistema: Go 1.26.3 conectou com lista antiga (`SSL_CERT_FILE`) e recusou com a nova. (23/10/2026)
- Deno/Bun saem com código 1 tanto em erro de certificado quanto de DNS: o teste sai com 10/11/12 próprios. (23/10/2026)

- `grep` do nome da raiz em `/etc/ssl/certs/ca-certificates.crt` nunca casa (PEM sem cabeçalho de texto); só o `cacert.pem` do certifi tem `# Subject:`. Teste conexão real. (23/10/2026)
- `echo "$(teste) $(r $?)"` pega o `$?` errado: guardar o código numa variável logo depois do teste. (23/10/2026)
- Testar as DUAS cadeias (G3 e AAA): várias ferramentas recusam uma e aceitam a outra. (23/10/2026)
- `certifi` em `/usr/lib/python3/dist-packages` (pacote Debian/Ubuntu) aponta para a lista do sistema: versão antiga ali não é exposição. (23/10/2026)
- Node: `--use-openssl-ca` bloqueou as duas cadeias com o sistema atualizado; `--use-system-ca` não (soma as listas). (23/10/2026)
