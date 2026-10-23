#!/usr/bin/env bash
# Testes isolados do audita.sh: nenhum acesso à rede, nenhum container de verdade, nada fora de uma pasta temporária.
# Cada caso troca curl, wget, php, ssh, docker, find e id por versões falsas (stubs) e confere o código de saída e
# as linhas do relatório. Há casos que DEVEM dar protegido/saída 0 (controles), para a correção não virar alarme
# para tudo.
#   bash testes/roda.sh            # todos
#   bash testes/roda.sh wget       # só os casos com "wget" no nome
# Precisa de: bash, gcc (compila o node falso que deixa uma marca quando é executado).
set -uo pipefail
umask 022   # pastas e stubs sem gravação para o grupo: o audita.sh recusa executar o que outros podem trocar
AQUI=$(cd "$(dirname "$0")" && pwd); AUD="$AQUI/../audita.sh"; FILTRO=${1:-}
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
B="$T/bin"; mkdir -p "$B" "$T/home" "$T/vazio"
for c in bash sh cat sed grep awk mktemp rm mkdir date hostname readlink dirname basename cut head tail tr xargs \
         sort wc stat getent printf sleep timeout chmod chown chgrp touch ls gzip env true false mountpoint find; do
  p=$(command -v "$c") && ln -s "$p" "$B/$c"; done
REAL_ID=$(command -v id); REAL_FIND=$(command -v find)

st(){ rm -f "$B/$1"; cat > "$B/$1"; chmod 755 "$B/$1"; }   # rm antes: nunca grava através de um link
st curl <<'S'
#!/bin/sh
case "${STUB_CURL:-60}" in
  0) exit 0;;
  60) echo "curl: (60) SSL certificate problem: unable to get local issuer certificate" >&2; exit 60;;
  77) echo "curl: (77) error setting certificate file: /nao/existe/certificate.pem" >&2; exit 77;;
  6) echo "curl: (6) Could not resolve host: x" >&2; exit 6;;
esac
S
st wget <<'S'
#!/bin/sh
case "${STUB_WGET:-gnu5}" in
  ok) exit 0;;
  gnu5) echo "ERROR: cannot verify certificate, issued by 'emSign'" >&2; exit 5;;
  bb) echo "ssl_client: SSL_connect" >&2; echo "wget: error getting response: Connection reset by peer" >&2; exit 1;;
  reset) echo "wget: error getting response: Connection reset by peer" >&2; exit 1;;
esac
S
st php <<'S'
#!/bin/sh
[ "${STUB_PHP:-}" = falha ] && exit 255
case "$1" in -v) echo "PHP ${STUB_PHP:-8.3.36} (cli) (built: Oct 21 2026)";; -r) echo 0;; esac
S
st ssh <<'S'
#!/bin/sh
cat >/dev/null; exit "${STUB_SSH:-0}"
S
st id <<S
#!/bin/sh
if [ "\${STUB_ROOT:-0}" = 1 ]; then case "\$1" in -u) echo 0; exit 0;; -un) echo root; exit 0;; esac; fi
exec $REAL_ID "\$@"
S
st runuser <<'S'
#!/bin/sh
echo "$*" >> "$STUB_LOG"; while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done; shift; exec "$@"
S
st docker <<'S'
#!/bin/sh
case "$1" in
  ps) [ "${STUB_DOCKER:-}" = semperm ] && { echo "permission denied while trying to connect to the Docker daemon" >&2; exit 1; }
      case "$*" in *format*) echo c1;; esac; exit 0;;
  exec) case "${STUB_DOCKER:-}" in
      semshell) cat >/dev/null; echo 'OCI runtime exec failed: exec: "sh": executable file not found in $PATH: unknown'; exit 126;;
      timeout) cat >/dev/null; echo "protegido  curl                               G3   "; exit 124;;
      parcial) cat >/dev/null; printf 'info       ca-certificates x\nprotegido  curl                               G3   \n'; exit 137;;
      semferr) PATH="$STUB_VAZIO" exec /bin/sh -s;;
      *) exec /bin/sh -s;;
    esac;;
  *) echo "img:1.0"; exit 0;;
esac
S
# find que estoura o tempo (só no caso da busca)
mkdir -p "$T/findlento"; cat > "$T/findlento/find" <<'S'
#!/bin/sh
echo /x/pyvenv.cfg; exit 124
S
chmod +x "$T/findlento/find"

# node falso (ELF de verdade): grava $MARCA quando roda; -v responde a versão; teste de conexão sai com 11 (recusou)
cat > "$T/fake.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int c,char**v){const char*m=getenv("MARCA");if(m){FILE*f=fopen(m,"a");if(f){fputs(v[0],f);fputs("\n",f);fclose(f);}}
if(c>1&&!strcmp(v[1],"-v")){puts("v22.23.4");return 0;}return 11;}
C
gcc -O0 -o "$T/fakenode" "$T/fake.c" || { echo "gcc falhou: não dá para testar a execução segura"; exit 1; }

# listas do sistema falsas: uma limpa, uma com a linha da raiz G3
L_G3=$(sed -n "s/^L_G3='\(.*\)'$/\1/p" "$AUD")
printf -- '-----BEGIN CERTIFICATE-----\nABCD\n-----END CERTIFICATE-----\n' > "$T/lista-limpa.crt"
printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "$L_G3" > "$T/lista-com-g3.crt"
L_AAA=$(sed -n "s/^L_AAA='\(.*\)'$/\1/p" "$AUD")
printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "$L_AAA" > "$T/lista-com-aaa.crt"

OK=0; FALHA=0
# caso <nome> <saída esperada> <padrão que DEVE aparecer|-> <padrão que NÃO pode aparecer|-> -- <env...> -- <args...>
caso(){ nome=$1; esp=$2; tem=$3; nao=$4; shift 4
  [ -n "$FILTRO" ] && case "$nome" in *"$FILTRO"*) ;; *) return;; esac
  envs=(); [ "$1" = -- ] && shift; while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done; [ $# -gt 0 ] && shift
  out=$(cd "$T" && env -i HOME="$T/home" PATH="$B" STUB_LOG="$T/runuser.log" STUB_VAZIO="$T/vazio" \
        AUDITA_LISTAS="$T/lista-limpa.crt" AUDITA_JVM="$T/vazio" ${envs[@]+"${envs[@]}"} /bin/bash "$AUD" "$@" 2>&1); rc=$?
  erro=
  [ "$rc" = "$esp" ] || erro="saída $rc (esperado $esp)"
  [ "$tem" = - ] || echo "$out" | grep -qE -- "$tem" || erro="$erro; faltou /$tem/"
  [ "$nao" = - ] || ! echo "$out" | grep -qE -- "$nao" || erro="$erro; apareceu /$nao/"
  if [ -z "$erro" ]; then OK=$((OK+1)); echo "ok     $nome"
  else FALHA=$((FALHA+1)); echo "FALHOU $nome: $erro"; echo "$out" | sed 's/^/       | /' | tail -25; fi; }
R=(--rapido --sem-docker)

# --- controles: o que está certo continua certo
caso "controle curl recusou (60) = protegido, saída 0" 0 '^protegido  curl' '^SEM TESTE' -- STUB_CURL=60 -- "${R[@]}"
caso "controle curl conectou = EXPOSTO, saída 1"        1 '^EXPOSTO  +curl' - -- STUB_CURL=0 -- "${R[@]}"
caso "controle wget GNU recusou (5) = protegido"        0 '^protegido  wget' '^SEM TESTE' -- STUB_WGET=gnu5 -- "${R[@]}"
caso "controle wget busybox + lista limpa = protegido"  0 'confirmada pela lista' '^SEM TESTE' -- STUB_WGET=bb -- "${R[@]}"
caso "controle PHP 8.3.36 = protegido"                  0 'PHP2Shell: versão corrigida' '^SEM TESTE' -- STUB_PHP=8.3.36 -- "${R[@]}"
caso "controle PHP 8.3.6 sem pacote = EXPOSTO"          1 '^EXPOSTO.*8\.3\.6' - -- STUB_PHP=8.3.6 -- "${R[@]}"
caso "controle ssh remoto saída 0 = 0"                  0 - 'SEM TESTE  ssh' -- STUB_SSH=0 -- --ssh x@y
caso "controle ssh remoto EXPOSTO (1) = 1"              1 - 'SEM TESTE  ssh' -- STUB_SSH=1 -- --ssh x@y
caso "controle container completo = protegido, saída 0" 0 '\[c1\]' '^SEM TESTE' -- STUB_DOCKER=ok -- --rapido
caso "controle escopo mostra --rapido e --sem-docker"   0 '--rapido: sem busca.*' - -- -- "${R[@]}"
caso "controle saída 0 diz que não certifica a máquina" 0 'não certifica que a máquina inteira' - -- -- "${R[@]}"

# --- falsos "protegido" (relatados na validação)
caso "wget reset sem SSL_connect = SEM TESTE, saída 2"  2 '^SEM TESTE  wget' '^protegido  wget' -- STUB_WGET=reset -- "${R[@]}"
caso "wget busybox + lista com a raiz G3 = SEM TESTE no G3" 2 '^SEM TESTE  wget +G3.*não prova' '^protegido  wget +G3' -- STUB_WGET=bb AUDITA_LISTAS="$T/lista-com-g3.crt" -- "${R[@]}"
caso "wget busybox + lista só com G3 = AAA protegido"   2 '^protegido  wget +AAA.*sem a raiz AAA' - -- STUB_WGET=bb AUDITA_LISTAS="$T/lista-com-g3.crt" -- "${R[@]}"
caso "wget busybox + lista com a raiz AAA = SEM TESTE no AAA" 2 '^SEM TESTE  wget +AAA' '^protegido  wget +AAA' -- STUB_WGET=bb AUDITA_LISTAS="$T/lista-com-aaa.crt" -- "${R[@]}"
caso "wget busybox sem lista legível = SEM TESTE"       2 '^SEM TESTE  wget' '^protegido  wget' -- STUB_WGET=bb AUDITA_LISTAS="$T/nao-existe.crt" -- "${R[@]}"
caso "curl 77 (lista local não carregou) = SEM TESTE"   2 '^SEM TESTE  curl' '^protegido  curl' -- STUB_CURL=77 -- "${R[@]}"
caso "curl 6 (DNS) = SEM TESTE"                         2 '^SEM TESTE  curl' - -- STUB_CURL=6 -- "${R[@]}"
caso "PHP 8.6.0RC1 = VERIFIQUE, saída 3"                3 '^VERIFIQUE.*versão de teste' '^protegido.*8\.6\.0' -- STUB_PHP=8.6.0RC1 -- "${R[@]}"
caso "php -v falha = SEM TESTE (PHP não some)"          2 '^SEM TESTE  php.*não respondeu' - -- STUB_PHP=falha -- "${R[@]}"

# --- teste que não terminou não pode sair 0
caso "ssh 124 = SEM TESTE, saída 2"                     2 'SEM TESTE  ssh.*código 124' - -- STUB_SSH=124 -- --ssh x@y
caso "ssh 127 = SEM TESTE, saída 2"                     2 'SEM TESTE  ssh.*código 127' - -- STUB_SSH=127 -- --ssh x@y
caso "ssh 255 = SEM TESTE, saída 2"                     2 'SEM TESTE  ssh.*não conectou' - -- STUB_SSH=255 -- --ssh x@y
caso "ssh 124 em 1 de 2 destinos = saída 2"             2 'código 124' - -- STUB_SSH=124 -- --ssh a@b --ssh c@d
caso "docker sem permissão = SEM TESTE"                 2 '^SEM TESTE  docker.*docker ps falhou' - -- STUB_DOCKER=semperm -- --rapido
caso "container sem shell = SEM TESTE"                  2 'SEM TESTE  container c1.*sem shell' - -- STUB_DOCKER=semshell -- --rapido
caso "container timeout = SEM TESTE"                    2 'SEM TESTE  container c1.*120 s' - -- STUB_DOCKER=timeout -- --rapido
caso "container saída parcial = SEM TESTE"              2 'SEM TESTE  container c1.*saída cortada' - -- STUB_DOCKER=parcial -- --rapido
caso "container sem ferramentas = SEM TESTE"            2 'SEM TESTE  container c1.*nenhuma ferramenta' - -- STUB_DOCKER=semferr -- --rapido

# --- busca no disco e execução segura
mkdir -p "$T/raiz/segura/bin" "$T/raiz/aberta/bin" "$T/raiz/vazia"
cp "$T/fakenode" "$T/raiz/segura/bin/node"; cp "$T/fakenode" "$T/raiz/aberta/bin/node"
chmod 755 "$T/raiz" "$T/raiz/segura" "$T/raiz/segura/bin"; chmod 777 "$T/raiz/aberta"   # aberta: qualquer um grava, sem sticky
caso "busca: node em pasta própria segura é testado"     0 '^protegido  node v22\.23\.4.*segura' '^SEM TESTE' -- MARCA="$T/m1" -- --sem-docker --raiz "$T/raiz/segura"
[ -s "$T/m1" ] && { OK=$((OK+1)); echo "ok     busca: o node seguro rodou de fato"; } || { FALHA=$((FALHA+1)); echo "FALHOU busca: o node seguro não rodou"; }
caso "busca: node em pasta gravável por outros NÃO roda" 2 'SEM TESTE  node.*não executado' '^protegido  node' -- MARCA="$T/m2" -- --sem-docker --raiz "$T/raiz/aberta"
[ -e "$T/m2" ] && { FALHA=$((FALHA+1)); echo "FALHOU busca: o node da pasta aberta RODOU"; } || { OK=$((OK+1)); echo "ok     busca: o node da pasta aberta não rodou"; }
# root simulado: binário de usuário roda via runuser (como o dono), nunca direto
: > "$T/runuser.log"
caso "root: node de usuário roda como o dono (runuser)"  0 '^protegido  node' '^SEM TESTE' -- STUB_ROOT=1 MARCA="$T/m3" -- --sem-docker --raiz "$T/raiz/segura"
grep -q -- "-u $(id -un) --" "$T/runuser.log" && { OK=$((OK+1)); echo "ok     root: passou pelo runuser -u $(id -un)"; } || { FALHA=$((FALHA+1)); echo "FALHOU root: não usou runuser"; }
caso "root: node em pasta aberta NÃO roda"               2 'SEM TESTE  node.*não executado' - -- STUB_ROOT=1 MARCA="$T/m4" -- --sem-docker --raiz "$T/raiz/aberta"
[ -e "$T/m4" ] && { FALHA=$((FALHA+1)); echo "FALHOU root: o node da pasta aberta RODOU"; } || { OK=$((OK+1)); echo "ok     root: o node da pasta aberta não rodou"; }
# venv numa pasta segura cujo bin/python é link para um binário em pasta aberta: segue o link e recusa
mkdir -p "$T/raiz/link/venv/bin"; chmod 755 "$T/raiz/link" "$T/raiz/link/venv" "$T/raiz/link/venv/bin"
touch "$T/raiz/link/venv/pyvenv.cfg"; cp "$T/fakenode" "$T/raiz/aberta/bin/python"; ln -s "$T/raiz/aberta/bin/python" "$T/raiz/link/venv/bin/python"
caso "venv com link → alvo em pasta aberta NÃO roda"     2 '^SEM TESTE  venv.*não executado' - -- MARCA="$T/m5" -- --sem-docker --raiz "$T/raiz/link"
[ -e "$T/m5" ] && { FALHA=$((FALHA+1)); echo "FALHOU link: o alvo inseguro RODOU"; } || { OK=$((OK+1)); echo "ok     link: o alvo inseguro não rodou"; }
# controle: o mesmo venv com o link apontando para binário em pasta segura roda
mkdir -p "$T/raiz/link2/venv/bin"; chmod 755 "$T/raiz/link2" "$T/raiz/link2/venv" "$T/raiz/link2/venv/bin"
touch "$T/raiz/link2/venv/pyvenv.cfg"; cp "$T/fakenode" "$T/raiz/segura/bin/python"; ln -s "$T/raiz/segura/bin/python" "$T/raiz/link2/venv/bin/python"
caso "controle venv com link → alvo seguro é testado"    0 '^protegido  venv' '^SEM TESTE' -- MARCA="$T/m6" -- --sem-docker --raiz "$T/raiz/link2"
# pasta gravável pelo grupo: aceita se o grupo é o pessoal do dono (umask 002 do Ubuntu); recusa se tem outros membros
mkdir -p "$T/raiz/gp/bin"; cp "$T/fakenode" "$T/raiz/gp/bin/node"; chmod 755 "$T/raiz/gp"; chmod 775 "$T/raiz/gp/bin"
if [ "$(getent group "$(id -g)" | cut -d: -f4)" = "" ] || [ "$(getent group "$(id -g)" | cut -d: -f4)" = "$(id -un)" ]; then
  caso "controle pasta 775 do grupo pessoal é testada"   0 '^protegido  node' '^SEM TESTE' -- -- --sem-docker --raiz "$T/raiz/gp"
else echo "pulado pasta 775 do grupo pessoal: o grupo principal de $(id -un) tem outros membros"; fi
GC=$(for g in $(id -G); do l=$(getent group "$g"); case "${l##*:}" in *,*) echo "$g"; break;; esac; done)
if [ -n "$GC" ]; then
  mkdir -p "$T/raiz/gc/bin"; cp "$T/fakenode" "$T/raiz/gc/bin/node"; chmod 755 "$T/raiz/gc"; chgrp "$GC" "$T/raiz/gc/bin"; chmod 775 "$T/raiz/gc/bin"
  caso "pasta 775 de grupo com outros membros NÃO roda"  2 '^SEM TESTE  node.*não executado' - -- MARCA="$T/m7" -- --sem-docker --raiz "$T/raiz/gc"
  [ -e "$T/m7" ] && { FALHA=$((FALHA+1)); echo "FALHOU grupo: o node da pasta do grupo compartilhado RODOU"; } || { OK=$((OK+1)); echo "ok     grupo: o node da pasta do grupo compartilhado não rodou"; }
else echo "pulado grupo compartilhado: $(id -un) não está em grupo com outros membros"; fi
caso "busca cortada (timeout do find) = SEM TESTE"       2 'SEM TESTE  busca no disco.*124' - -- PATH="$T/findlento:$B" -- --sem-docker
caso "escopo mostra --raiz"                              0 'busca no disco só em' - -- -- --sem-docker --raiz "$T/raiz/vazia"
caso "php-ok aparece no escopo"                          0 '--php-ok: 1 VERIFIQUE' - -- STUB_PHP=8.6.0RC1 -- "${R[@]}" --php-ok

echo "-- $OK ok · $FALHA falha(s)"
[ $FALHA = 0 ]
