# CLAUDE.md — auditoria-seguranca

Kit/guia de segurança do INEMA (23/10/2026): como atualizar cada camada, como auditar com `audita.sh` (teste de conexão real, só leitura), caso real (eMudhra) e PHP2Shell.

- Repo: `inematds/auditoria-seguranca` (público). Commits com autor `inematds <inematds@gmail.com>`.
- Guia: `guia/index.html` (PT, fonte) + `guia/en/` + `guia/es/`; GitHub Pages por Actions (`.github/workflows/pages.yml`). Push de mudança no workflow: por SSH (`git push git@github.com:inematds/auditoria-seguranca.git main`).
- `audita.sh` é **só leitura**: nunca instalar, alterar ou gravar nada nas máquinas auditadas. Três estados (EXPOSTO / protegido / SEM TESTE); erro de rede nunca conta como protegido. Guardar `$?` numa variável ANTES de qualquer `echo`.
- Nada de IP, hostname ou nome de cliente no repo (caso real anonimizado). Lista de servidores (`servidores.txt`) fica fora do git.
- Fatos só de fontes oficiais (php.net, Mozilla, Google, emudhra.we-have-a-problem.com, SOCRadar). Não citar vídeos de terceiros.
- Mudou o PT → retraduzir EN/ES com `inema-traduz` e conferir.

## O processo, do início ao fim

Ver a seção de mesmo nome no [README.md](README.md).

## Self-learning

When I correct you, or you catch yourself making a mistake: before continuing, add the lesson as a one-line rule at the TOP of the Lessons section below, so it never happens again.

## Lessons

- `grep` do nome da raiz em `/etc/ssl/certs/ca-certificates.crt` nunca casa (PEM sem cabeçalho de texto); só o `cacert.pem` do certifi tem `# Subject:`. Teste conexão real. (23/10/2026)
- `echo "$(teste) $(r $?)"` pega o `$?` errado: guardar o código numa variável logo depois do teste. (23/10/2026)
- Testar as DUAS cadeias (G3 e AAA): várias ferramentas recusam uma e aceitam a outra. (23/10/2026)
- `certifi` em `/usr/lib/python3/dist-packages` (pacote Debian/Ubuntu) aponta para a lista do sistema: versão antiga ali não é exposição. (23/10/2026)
- Node: `--use-openssl-ca` bloqueou as duas cadeias com o sistema atualizado; `--use-system-ca` não (soma as listas). (23/10/2026)
