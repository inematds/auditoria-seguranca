# CHANGELOG

## 1.1.2 — 23/10/2026

Correções de uma validação externa: o `audita.sh` 1.1.1 podia terminar limpo sem ter concluído a auditoria.

### audita.sh
- Teste incompleto nunca passa por limpo: SSH com código fora de 0/1/2/3 (124 tempo, 127 sem bash, 255 sem conexão), container sem shell, sem ferramenta, com tempo esgotado ou com saída cortada (marcador `__FIM_SONDA__`), `php -v` que falha, busca no disco cortada (`find` 124) e `docker ps` sem permissão viram `SEM TESTE` (saída 2).
- Fim dos falsos "protegido": o curl só conta recusa com código 60/51 (o 77 de lista local que não carregou é `SEM TESTE`); o wget do busybox não usa mais um site de controle — a recusa ambígua só vale como protegida se a lista do sistema (a que o `ssl_client` usa) foi lida e não tem a raiz daquela cadeia.
- PHP em versão de teste (RC, beta, dev) vira `VERIFIQUE`; linha `info` quando `session.upload_progress.enabled` está ligado (CVE-2026-115560).
- Execução segura: binário achado no disco só roda se o arquivo, cada link e cada pasta do caminho são do root ou do dono e ninguém mais grava neles (grupo pessoal do dono aceito; sticky aceito em pasta). Com root, o binário de um usuário roda como esse usuário (`runuser`), nunca como root. O que não passa vira `SEM TESTE` com o motivo.
- Bloco `escopo desta rodada` no fim (`--rapido`, `--sem-docker`, `--raiz`, `--php-ok`, Go sem `--go`, usuário); saída 0 diz que não certifica a máquina inteira.
- `--raiz DIR` limita a busca no disco. Tag fixada: a correção sugerida agora compara o digest antes de subir a versão.
- `testes/roda.sh`: 46 casos isolados (stubs de curl, wget, php, ssh, docker, find, id e runuser; node falso que deixa marca quando roda), com controles que devem passar.

### Guia e README (PT/EN/ES)
- "só leitura" → "não altera nada; é levantamento, não certificado". Saída 0 vale dentro do escopo e não libera deploy sozinha (CI/CD corrigido).
- Docker: tag fixada não é imutável; o que não muda é o digest.
- PHP: `memory_limit=-1` reduz, não fecha o caminho; aviso de 23/10 (CVE-2026-115560): manter `session.upload_progress.enabled=0` mesmo depois de atualizar, com o alcance real (só apps que trocam o `serialize_handler` em execução).
- Tabela: uv 0.13.5, Python 3.15.1 · 3.14.9 · 3.13.17, FreeBSD `ca_root_nss 1.131.1` e base 15.1-p6 · 14.5-p3 · 14.4-p12 (SA-26:73).

## 1.1.1 — 23/10/2026

- Versão do guia visível na capa (PT/EN/ES) e no topo dos README: "Guia v1.1.1 · atualizado em 23/10/2026".
- Versão num lugar só: arquivo `VERSION`; `python3 ferramentas/versao.py X.Y.Z [dd/mm/aaaa]` atualiza o `audita.sh`, a capa e o rodapé do guia e os README (sem argumento, só confere).
- Banners (`banner*.jpg`, PT/EN/ES, inclusive os "grade"): o "4" (a chave que era o número 4) em vermelho, para contrastar; o resto da arte igual.

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
- PHP de pacote da distribuição (dpkg/apk/rpm) vira `VERIFIQUE`, mesmo sem sufixo no `php -v` (backport não muda o número).
- Saída `3`: nada conecta, mas falta REINICIE/VERIFIQUE. Processos Java iniciados antes da mudança no `cacerts` entram em REINICIE.
- Tag `X.Y-alpine` conta como flutuante; só `X.Y.Z` exato (ou data) é fixada. Aviso para rodar correções de outros usuários como o dono.
- PHP de pacote Debian/Ubuntu: procura o CVE no changelog local do pacote (backport confirmado = protegido); `--php-ok` para quem já conferiu à mão.
- `--chave` para usar uma chave SSH específica; `--versao`.
- wget do busybox: recusa ambígua ("ssl_client"/"reset by peer") é confirmada contra um site bom.
- Testes em Node/Python saem com códigos próprios: um travamento vira `SEM TESTE`, nunca "protegido".
- Comparação de versão em sh puro (há containers sem `awk` nem `sort -V`).

### Guia (PT/EN/ES)
- Chamada "antes e depois de atualizar" no topo e no fim de Como atualizar (e nos README): backup, saúde antes, testar e validar depois.
- Aviso: banco com tag `latest` pode subir de versão principal; volta depois de migração = restaurar o backup.
- n8n: trocar a tag fixada antes do pull. Camada por cima com `USER root`, mesma versão principal do Node, sem `|| true` no pip.
- Novos passos: Java (cacerts, com `keytool -delete`), Deno e Bun, reinício com "quem reiniciar" e aviso para não reiniciar no meio de job.
- Docker reescrito: os 3 grupos, a camada por cima da imagem antiga (`:pre-emudhra`), Supabase local (backup, CLI nova, testar de novo, esperar o fornecedor), armadilhas (uv.lock, proxy nginx 502, compose 1.29, busybox wget).
- Go: no Linux segue a lista do sistema (teste com lista antiga).
- Python: venv do uv sem pip, `uv run`, conda.
- PHP em containers.
- Caso real: a máquina de desenvolvimento, em quatro blocos de lições.

## 1.0.0 — 23/10/2026

- Guia PT/EN/ES (o que houve, auditar, atualizar, caso real, PHP2Shell, rotina) e `audita.sh` com teste de conexão real (curl, wget, Node, Python/venvs, containers), `--ssh`, `--hosts`, `--rapido`, `--sem-docker`.
