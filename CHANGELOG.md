# CHANGELOG

## 1.1.0 — 23/10/2026

Lições da correção de uma máquina de desenvolvimento (134 EXPOSTO → quase zero).

### audita.sh
- Testa Deno e Bun (conexão real, no PATH, em `~/.deno`/`~/.bun`, no disco e nos containers).
- Java: confere o `cacerts` de cada JDK com o `keytool` (apelido e impressão digital das duas raízes). É conferência de lista, não de conexão, e a linha diz isso.
- `--go`: teste real do Go (compila um programa numa pasta temporária, apagada no fim).
- PHP2Shell: `php -v` no servidor e em cada container, comparado com 8.5.12 · 8.4.27 · 8.3.36 · 8.2.35 (`VERIFIQUE` para pacote de distribuição, que pode ter backport).
- Ambientes conda passam a ser testados; venv sem pip ganha a correção pelo `uv`; aviso de `uv.lock` (o `uv run` desfaz o certifi novo).
- Seção "processos a reiniciar": Node/Deno/Bun/Java/PHP cujo binário foi trocado depois que o processo começou, processos que usam ferramenta ainda EXPOSTA e processos de venv iniciados antes do certifi novo, com a unidade systemd.
- Containers testados em paralelo (6 por vez) e classificados pelo `docker inspect`: tag flutuante, imagem nova já no disco (só recriar), imagem construída localmente (camada por cima), versão fixada e Supabase local.
- Resumo agrupado por tipo com a correção sugerida; `--comandos` lista os comandos (nunca executa).
- Cada REINICIE diz o que reiniciar: unidade do sistema, unidade `--user` ou processo avulso (nunca o `user@NNNN.service`); os reinícios entram no resumo e no `--comandos`.
- Java: a correção sugerida é `keytool -delete` das duas raízes (com backup); `update-ca-certificates -f` sozinho regrava o arquivo mas não as tira.
- `--chave` para usar uma chave SSH específica; `--versao`.
- wget do busybox: recusa ambígua ("ssl_client"/"reset by peer") é confirmada contra um site bom.
- Testes em Node/Python saem com códigos próprios: um travamento vira `SEM TESTE`, nunca "protegido".
- Comparação de versão em sh puro (há containers sem `awk` nem `sort -V`).

### Guia (PT/EN/ES)
- Novos passos: Java (cacerts, com `keytool -delete`), Deno e Bun, reinício com "quem reiniciar" e aviso para não reiniciar no meio de job.
- Docker reescrito: os 3 grupos, a camada por cima da imagem antiga (`:pre-emudhra`), Supabase local (backup, CLI nova, testar de novo, esperar o fornecedor), armadilhas (uv.lock, proxy nginx 502, compose 1.29, busybox wget).
- Go: no Linux segue a lista do sistema (teste com lista antiga).
- Python: venv do uv sem pip, `uv run`, conda.
- PHP em containers.
- Caso real: a máquina de desenvolvimento, em quatro blocos de lições.

## 1.0.0 — 23/10/2026

- Guia PT/EN/ES (o que houve, auditar, atualizar, caso real, PHP2Shell, rotina) e `audita.sh` com teste de conexão real (curl, wget, Node, Python/venvs, containers), `--ssh`, `--hosts`, `--rapido`, `--sem-docker`.
