#!/usr/bin/env bash
# audita.sh 1.1.0 — auditoria SÓ LEITURA da confiança em certificados (caso eMudhra, out/2026) + versão do PHP (PHP2Shell).
#
# Não lista certificados: testa a CONEXÃO REAL contra dois sites de teste assinados pelas chaves
# comprometidas. Se a ferramenta conecta, ela ainda confia na cadeia ruim.
#   EXPOSTO   = conectou (a ferramenta aceitou o certificado ruim)
#   protegido = recusou por erro de certificado
#   SEM TESTE = não deu para testar (rede, DNS, timeout, ferramenta quebrada) — NÃO conta como protegido
#   VERIFIQUE = PHP abaixo da versão corrigida, mas com número de distribuição (pode ter backport)
#   REINICIE  = processo rodando com binário/lista antiga (atualizou, mas não reiniciou)
#
# O que testa (conexão real): curl, wget, cada Node, Deno e Bun achados, o Python do sistema e o de cada venv
# (com o certifi dele), e dentro de cada container Docker em execução (curl, wget, node, deno, bun, python3).
# Java: confere a LISTA (keystore cacerts) com keytool, sem conexão (Java 8 não roda teste sem compilar).
# PHP: compara `php -v` (host e containers) com as versões corrigidas do PHP2Shell.
# Mostra versões, certifi desatualizado (< 2026.10.19), processos a reiniciar e um resumo agrupado com a correção.
#
# Uso:
#   ./audita.sh                         # esta máquina
#   ./audita.sh --ssh root@servidor     # outra máquina por SSH (repita --ssh para várias)
#   ./audita.sh --hosts servidores.txt  # um destino SSH por linha (linhas com # são ignoradas)
#   ./audita.sh --chave ~/.ssh/id_vps --ssh root@servidor   # chave SSH específica (ssh -i)
#   ./audita.sh --rapido                # pula a busca no disco (venvs, Node/Deno/Bun embutidos, JDKs, certifi)
#   ./audita.sh --sem-docker            # não entra nos containers
#   ./audita.sh --comandos              # imprime os comandos de correção sugeridos (NÃO executa nada)
#   ./audita.sh --go                    # também testa o Go de verdade: compila um teste numa pasta temporária
#                                       # (grava ~100 MB em $TMPDIR e apaga no fim; por isso é opcional)
#   ./audita.sh --php-ok                # você já conferiu o backport do PHP no changelog: VERIFIQUE não segura a saída
#   ./audita.sh --versao
#
# Nada é instalado, alterado ou executado como correção. Arquivos só em pasta temporária apagada no fim.
# Saída: 0 = tudo zerado; 1 = há EXPOSTO; 2 = há SEM TESTE; 3 = só falta REINICIE/VERIFIQUE.
set -uo pipefail

VERSAO=1.1.0
CERTIFI_MIN=2026.10.19
RAPIDO=0; DOCKER=1; COMANDOS=0; GO=0; PHPOK=0; ALVOS=(); SSH_OPTS=()
while [ $# -gt 0 ]; do case "$1" in
  --ssh) ALVOS+=("$2"); shift 2;;
  --hosts) while IFS= read -r l; do l="${l%%#*}"; l="$(echo "$l" | xargs)"; [ -n "$l" ] && ALVOS+=("$l"); done < "$2"; shift 2;;
  --chave) SSH_OPTS+=(-i "$2"); shift 2;;
  --rapido) RAPIDO=1; shift;;
  --sem-docker) DOCKER=0; shift;;
  --comandos) COMANDOS=1; shift;;
  --go) GO=1; shift;;
  --php-ok) PHPOK=1; shift;;
  --local) shift;;
  --versao|--version) echo "audita.sh $VERSAO"; exit 0;;
  -h|--help) sed -n 2,32p "$0"; exit 0;;
  *) echo "argumento desconhecido: $1" >&2; exit 64;;
esac; done

# ---------------------------------------------------------------------------------------------
# Remoto: manda este mesmo arquivo pelo SSH e roda lá (só leitura). Um destino de cada vez.
if [ ${#ALVOS[@]} -gt 0 ]; then
  pior=0
  for a in "${ALVOS[@]}"; do
    echo "################ $a"
    flags=(); [ $RAPIDO = 1 ] && flags+=(--rapido); [ $DOCKER = 0 ] && flags+=(--sem-docker)
    [ $COMANDOS = 1 ] && flags+=(--comandos); [ $GO = 1 ] && flags+=(--go); [ $PHPOK = 1 ] && flags+=(--php-ok)
    ssh -o BatchMode=yes -o ConnectTimeout=10 ${SSH_OPTS[@]+"${SSH_OPTS[@]}"} "$a" "bash -s -- --local ${flags[*]-}" < "$0"; rc=$?
    [ $rc = 255 ] && { echo "SEM TESTE  ssh  não conectou em $a"; rc=2; }
    [ $rc = 1 ] && pior=1; [ $rc = 2 ] && [ $pior != 1 ] && pior=2; [ $rc = 3 ] && [ $pior = 0 ] && pior=3
    echo
  done
  exit $pior
fi

TMPD=$(mktemp -d 2>/dev/null || echo "/tmp/audita.$$"); mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT

# ---------------------------------------------------------------------------------------------
# SONDA: sh POSIX (roda no host e dentro de containers Alpine/Debian sem bash).
# Cada teste devolve 0 = conectou (EXPOSTO), 1 = erro de certificado (protegido), 2 = sem teste, 4 = verifique.
# Os testes em Node/Python/Deno/Bun saem com 10/11/12 de propósito: um travamento (código 1) vira SEM TESTE,
# nunca "protegido" por engano.
SONDA=$(cat <<'SH'
U_G3=https://dv-g3b-emudhra.we-have-a-problem.com/
U_AAA=https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
U_OK=https://www.google.com/
JS='var u=process.argv[process.argv.length-1];var q=require("https").get(u,{timeout:10000},function(r){r.resume();process.exit(10)});q.on("timeout",function(){process.exit(12)});q.on("error",function(e){var c=String(e.code||"");process.exit(/CERT|UNABLE_TO|SELF_SIGNED|DEPTH_ZERO|ERR_TLS/.test(c)?11:12)})'
JSF='const u=__U__;const ex=c=>(typeof Deno!=="undefined"?Deno.exit(c):process.exit(c));try{await fetch(u,{signal:AbortSignal.timeout(10000)});ex(10)}catch(e){const s=[e,e&&e.code,e&&e.cause,e&&e.cause&&e.cause.code].map(String).join(" ");ex(/cert|UNABLE_TO|SELF_SIGNED|issuer/i.test(s)?11:12)}'
PY='
import ssl, sys
u, modo = sys.argv[1], sys.argv[2]
try:
    import urllib.request as R, urllib.error as E
except ImportError:
    sys.exit(12)
if modo == "certifi":
    try:
        import certifi
    except ImportError:
        sys.exit(13)
    ctx = ssl.create_default_context(cafile=certifi.where())
else:
    ctx = ssl.create_default_context()
try:
    R.urlopen(u, timeout=10, context=ctx)
    sys.exit(10)
except E.HTTPError:
    sys.exit(10)
except Exception as e:
    if "CERTIFICATE_VERIFY_FAILED" in str(e) or "certificate verify failed" in str(e):
        sys.exit(11)
    sys.exit(12)
'
# impressões digitais (SHA-1 e SHA-256) das duas raízes, além dos apelidos usados por Debian e pelos JDKs
RX_G3='emsign[^,]*ecc[^,]*g3|30:43:FA:4F:F2:57:DC:A0:C3:80|86:A1:EC:BA:08:9C:4A:8D:3B:BE'
RX_AAA='comodo[^,]*aaa|aaa[^,]*certificate[^,]*services|D1:EB:23:A4:6D:17:D6:8F:D9:25|D7:A7:A0:FB:5D:7E:27:31:D7:71'
st(){ case "$1" in 0) echo "EXPOSTO  ";; 1) echo "protegido";; 4) echo "VERIFIQUE";; *) echo "SEM TESTE";; esac; }
linha(){ printf '%s  %-34s %-4s %s\n' "$(st "$1")" "$2" "$3" "$4"; }
mapa(){ case "$1" in 10) return 0;; 11) return 1;; 13) return 3;; *) return 2;; esac; }
vge(){ a="$1."; b="$2."   # $1 >= $2 ? (sh puro: há containers sem awk)
  while [ -n "$a" ] || [ -n "$b" ]; do
    x=${a%%.*}; y=${b%%.*}; a=${a#*.}; b=${b#*.}
    x=${x%%[!0-9]*}; y=${y%%[!0-9]*}; x=${x:-0}; y=${y:-0}
    [ "$x" -gt "$y" ] && return 0; [ "$x" -lt "$y" ] && return 1
  done; return 0; }
t_curl(){ e=$(curl -sS -o /dev/null -m 10 "$1" 2>&1); r=$?
  if [ $r = 0 ]; then return 0; elif [ $r = 60 ] || echo "$e" | grep -qi certif; then return 1; else return 2; fi; }
CTRL_WGET=
t_wget(){ e=$(wget -O /dev/null -T 10 "$1" 2>&1); r=$?   # sem -q: a mensagem de certificado vem no stderr
  if [ $r = 0 ] || [ $r = 8 ]; then return 0; elif [ $r = 5 ] || echo "$e" | grep -qi certif; then return 1; fi
  # wget do busybox: a recusa aparece como "ssl_client: SSL_connect" ou "Connection reset" — ambíguo.
  # Confere com um site bom: se o site bom abre, a falha foi de certificado; se não abre, é rede.
  if echo "$e" | grep -qiE 'ssl_client|SSL_connect|reset by peer'; then
    [ -z "$CTRL_WGET" ] && { wget -O /dev/null -T 10 "$U_OK" >/dev/null 2>&1 && CTRL_WGET=ok || CTRL_WGET=falha; }
    [ "$CTRL_WGET" = ok ] && return 1
  fi
  return 2; }
t_node(){ "$1" -e "$JS" "$2" >/dev/null 2>&1; mapa $?; }
t_py(){ "$1" -c "$PY" "$2" "$3" >/dev/null 2>&1; mapa $?; }
t_deno(){ js=$(printf '%s' "$JSF" | sed "s|__U__|\"$2\"|"); dd=$(mktemp -d 2>/dev/null || echo /tmp/audita-deno.$$)
  NO_COLOR=1 DENO_NO_UPDATE_CHECK=1 DENO_NO_PROMPT=1 DENO_DIR="$dd" "$1" eval "$js" >/dev/null 2>&1; r=$?; rm -rf "$dd"; mapa $r; }
t_bun(){ js=$(printf '%s' "$JSF" | sed "s|__U__|\"$2\"|"); NO_COLOR=1 "$1" -e "$js" >/dev/null 2>&1; mapa $?; }
# testa as duas cadeias com um comando; $1 = rótulo, resto = função + args (a URL vai no fim)
# ULT = resultado das duas: 0 se alguma conectou, 2 se alguma não testou, 1 se as duas recusaram
duas(){ rot=$1; shift; ULT=1
  for par in "G3 $U_G3" "AAA $U_AAA"; do tag=${par%% *}; u=${par#* }
    "$@" "$u"; r=$?            # guarda o código ANTES de qualquer echo
    linha "$r" "$rot" "$tag" ""
    if [ $r = 0 ]; then ULT=0; elif [ $r != 1 ] && [ $ULT = 1 ]; then ULT=2; fi
  done; }
py_duas(){ rot=$1; py=$2; modo=$3; ULT=1
  for par in "G3 $U_G3" "AAA $U_AAA"; do tag=${par%% *}; u=${par#* }
    t_py "$py" "$u" "$modo"; r=$?
    [ $r = 3 ] && { ULT=3; return 0; }    # sem certifi neste Python: nada a testar nesse modo
    linha "$r" "$rot" "$tag" ""
    if [ $r = 0 ]; then ULT=0; elif [ $r != 1 ] && [ $ULT = 1 ]; then ULT=2; fi
  done; }
# Java: a lista (keystore) ainda tem as raízes? 0 = tem (EXPOSTO), 1 = não tem, 2 = não deu para ler
t_jks(){ out=$("$2" -list -keystore "$1" -storepass changeit </dev/null 2>&1); [ $? = 0 ] || return 2
  echo "$out" | grep -qiE "$3" && return 0; return 1; }
java_lista(){ ks=$1; kt=$2; rot=$3; ULT=1
  for tag in G3 AAA; do if [ $tag = G3 ]; then rx=$RX_G3; else rx=$RX_AAA; fi
    t_jks "$ks" "$kt" "$rx"; r=$?
    linha "$r" "$rot" "$tag" "(lista do keystore, não conexão)"
    if [ $r = 0 ]; then ULT=0; elif [ $r != 1 ] && [ $ULT = 1 ]; then ULT=2; fi
  done; }
# cacerts do Java do PATH / JAVA_HOME: imprime "cacerts keytool" por linha
java_achar(){
  for j in "$(command -v java 2>/dev/null)" "${JAVA_HOME:+$JAVA_HOME/bin/java}"; do
    [ -n "$j" ] && [ -x "$j" ] || continue
    h=$(dirname "$(dirname "$(readlink -f "$j" 2>/dev/null || echo "$j")")")
    for k in "$h/lib/security/cacerts" "$h/jre/lib/security/cacerts"; do
      [ -f "$k" ] || continue
      kt="$h/bin/keytool"; [ -x "$kt" ] || kt=$(command -v keytool 2>/dev/null)
      echo "$(readlink -f "$k" 2>/dev/null || echo "$k") ${kt:-keytool}"
    done
  done | sort -u -k1,1; }
# PHP2Shell: versão do php; corrigido em 8.5.12 · 8.4.27 · 8.3.36 · 8.2.35
# o php veio de pacote da distribuição (dpkg/apk/rpm)? Aí o número não muda com o backport: VERIFIQUE, não EXPOSTO
de_pacote(){ f=$(readlink -f "$1" 2>/dev/null || echo "$1")
  if command -v dpkg >/dev/null 2>&1 && dpkg -S "$f" >/dev/null 2>&1; then dpkg -S "$f" 2>/dev/null | head -1 | cut -d: -f1; return 0; fi
  if command -v apk >/dev/null 2>&1; then o=$(apk info --who-owns "$f" 2>/dev/null | sed -n 's/.* owned by //p'); [ -n "$o" ] && { echo "$o"; return 0; }; fi
  if command -v rpm >/dev/null 2>&1 && rpm -qf "$f" >/dev/null 2>&1; then rpm -qf "$f"; return 0; fi
  return 1; }
php_ver(){ bin=$1; rot=$2; l=$("$bin" -v 2>/dev/null | head -1); ULT=1
  v=$(echo "$l" | sed -n 's/^PHP \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p'); [ -n "$v" ] || return 0
  suf=$(echo "$l" | sed -n 's/^PHP [0-9.]*\([^ ]*\).*/\1/p')
  pk=$(de_pacote "$(command -v "$bin" 2>/dev/null || echo "$bin")") && [ -z "$suf" ] && suf=" (pacote $pk)"
  # Debian/Ubuntu: o changelog local do pacote cita o CVE quando o backport já foi aplicado
  if [ -n "$pk" ] && [ -f "/usr/share/doc/$pk/changelog.Debian.gz" ] && \
     gzip -dc "/usr/share/doc/$pk/changelog.Debian.gz" 2>/dev/null | grep -q 'CVE-2026-109618'; then
    linha 1 "$rot $v$suf" PHP "PHP2Shell: backport no changelog do pacote (CVE-2026-109618)"; return 0; fi
  case "$v" in 8.5.*) m=8.5.12;; 8.4.*) m=8.4.27;; 8.3.*) m=8.3.36;; 8.2.*) m=8.2.35;; *) m=;; esac
  if [ -n "$m" ] && vge "$v" "$m"; then linha 1 "$rot $v$suf" PHP "PHP2Shell: versão corrigida"
  elif [ -z "$m" ] && vge "$v" 8.6; then linha 1 "$rot $v$suf" PHP "PHP2Shell: versão posterior às corrigidas"
  elif [ -n "$suf" ]; then ULT=4; linha 4 "$rot $v$suf" PHP "abaixo de ${m:-8.2.35}: pacote da distribuição, confira o backport (CVE-2026-109618) no changelog"
  elif [ -z "$m" ]; then ULT=0; linha 0 "$rot $v" PHP "PHP2Shell: linha sem suporte — suba para 8.2+ corrigido"
  else ULT=0; linha 0 "$rot $v" PHP "PHP2Shell: atualize para $m+"; fi; }
cainfo(){ # versão da lista do sistema (só informação, para provar a correção)
  if command -v apk >/dev/null 2>&1; then v=$(apk list -I ca-certificates-bundle ca-certificates 2>/dev/null | cut -d' ' -f1 | tr '\n' ' '); echo "info       ${v:-ca-certificates ?}"
  elif command -v dpkg-query >/dev/null 2>&1; then echo "info       ca-certificates $(dpkg-query -W -f='${Version}' ca-certificates 2>/dev/null)"
  elif command -v rpm >/dev/null 2>&1; then echo "info       $(rpm -q ca-certificates 2>/dev/null)"; fi; }
basico(){ # ferramentas no PATH (usado dentro de containers)
  cainfo
  command -v curl >/dev/null 2>&1 && duas "curl" t_curl
  command -v wget >/dev/null 2>&1 && duas "wget" t_wget
  if command -v node >/dev/null 2>&1; then duas "node $(node -v 2>/dev/null)" t_node node; fi
  if command -v deno >/dev/null 2>&1; then duas "deno $(deno -v 2>/dev/null | awk '{print $2}')" t_deno deno; fi
  if command -v bun >/dev/null 2>&1; then duas "bun $(bun -v 2>/dev/null)" t_bun bun; fi
  if command -v python3 >/dev/null 2>&1; then
    py_duas "python3 (ssl do sistema)" python3 sistema
    py_duas "python3 (certifi)" python3 certifi
  fi
  java_achar | while read -r ks kt; do java_lista "$ks" "$kt" "java cacerts $ks"; done
  command -v php >/dev/null 2>&1 && php_ver php "php"
  true; }
SH
)
eval "$SONDA"
N_EXP=0; N_SEM=0; N_VER=0; N_REI=0
conta(){ case "$1" in 0) N_EXP=$((N_EXP+1));; 1) ;; 4) N_VER=$((N_VER+1));; *) N_SEM=$((N_SEM+1));; esac; }
# no host, cada linha também entra no resumo (dentro dos containers a contagem é feita pelo texto)
linha(){ conta "$1"; printf '%s  %-34s %-4s %s\n' "$(st "$1")" "$2" "$3" "$4"; }

# achados para o resumo agrupado: "tipo|alvo|comando sugerido"
ACH=()
achado(){ ACH+=("$1"$'\t'"$2"$'\t'"$3"); }   # separador: TAB (comandos podem ter "|")
curto(){ echo "$1" | sed "s|^$HOME|~|"; }
SO_ID=$(. /etc/os-release 2>/dev/null; echo "${ID:-?} ${ID_LIKE:-}")
fix_sistema(){ case "$SO_ID" in
  *alpine*) echo "apk upgrade --no-cache ca-certificates ca-certificates-bundle";;
  *debian*|*ubuntu*) echo "sudo apt update && sudo apt install --only-upgrade ca-certificates";;
  *rhel*|*fedora*|*centos*) echo "sudo dnf upgrade ca-certificates";;
  *) echo "atualize o pacote ca-certificates da distribuição";; esac; }
node_fix(){ v=${1#v}; case "${v%%.*}" in
  22) vge "$v" 22.23.4 && echo "ok (>= 22.23.4)" || echo "ATUALIZE para 22.23.4+";;
  24) vge "$v" 24.22.1 && echo "ok (>= 24.22.1)" || echo "ATUALIZE para 24.22.1+";;
  26) vge "$v" 26.12.1 && echo "ok (>= 26.12.1)" || echo "ATUALIZE para 26.12.1+";;
  *) echo "linha SEM correção — troque para Node 22, 24 ou 26";; esac; }
node_cmd(){ n=$1; v=${2#v}; maj=${v%%.*}
  if command -v dpkg >/dev/null 2>&1 && dpkg -S "$n" 2>/dev/null | grep -q '^nodejs'; then
    if [ "$maj" -le 20 ] 2>/dev/null; then echo "Node $maj do apt sem correção: troque o repositório NodeSource para setup_22.x e: sudo apt install -y nodejs"
    else echo "sudo apt update && sudo apt install --only-upgrade nodejs"; fi
  else case "$n" in
    */.nvm/*) [ "$maj" -le 20 ] 2>/dev/null && maj=22; echo "nvm install $maj && nvm alias default $maj   # e reinicie o que usa este Node";;
    *playwright*) echo "atualize o pacote playwright do projeto que trouxe $(curto "$n") (pip install -U playwright · npm i playwright@latest) ou NODE_OPTIONS=--use-openssl-ca";;
    *) echo "atualize a ferramenta que trouxe $(curto "$n"); paliativo: NODE_OPTIONS=--use-openssl-ca no serviço";;
  esac; fi; }
venv_cmd(){ d=$1; c=
  case "$d" in */pipx/venvs/*) c="pipx runpip $(basename "$d") install -U certifi";; esac
  [ -z "$c" ] && [ -d "$d/conda-meta" ] && c="conda update -p $(curto "$d") certifi   # ambiente conda (ou: $(curto "$d")/bin/python -m pip install -U certifi)"
  if [ -z "$c" ]; then
    if [ -x "$d/bin/pip" ]; then c="$d/bin/python -m pip install -U certifi"
    else c="uv pip install --python $d/bin/python -U certifi   # venv sem pip (criado pelo uv)"; fi
  fi
  [ -f "$(dirname "$d")/uv.lock" ] && c="$c   # tem uv.lock: 'uv run' desfaz; faça também: cd $(dirname "$d") && uv lock --upgrade-package certifi && uv sync"
  echo "$c"; }

echo "== $(hostname) · $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-?}") · $(date '+%d/%m/%Y %H:%M') · audita.sh $VERSAO"

echo "-- versões"
if command -v dpkg-query >/dev/null 2>&1; then echo "ca-certificates $(dpkg-query -W -f='${Version}' ca-certificates 2>/dev/null)"
elif command -v apk >/dev/null 2>&1; then echo "ca-certificates $(apk info -v ca-certificates 2>/dev/null | head -1)"
elif command -v rpm >/dev/null 2>&1; then echo "ca-certificates $(rpm -q ca-certificates 2>/dev/null)"; fi
if ls /etc/ssl/certs 2>/dev/null | grep -qi 'emSign_ECC_Root_CA_-_G3'; then echo "raiz emSign ECC G3 ainda em /etc/ssl/certs: a lista do sistema pode ser anterior à correção (o teste de conexão é o que vale)"; fi
command -v go >/dev/null 2>&1 && { gv=$(go version | awk '{print $3}'); echo "go $gv — corrigido: 1.27.3 / 1.26.10; no Linux o Go segue a lista do sistema (teste real: --go); binários Go antigos: RECOMPILE"; }
command -v java >/dev/null 2>&1 && echo "java $(java -version 2>&1 | head -1 | sed 's/.*version //;s/"//g')"
systemctl is-enabled unattended-upgrades >/dev/null 2>&1 && echo "unattended-upgrades: ligado"

echo "-- conexão real (G3 = cadeia emSign ECC Root CA - G3 · AAA = cadeia cruzada AAA Certificate Services)"
if command -v curl >/dev/null 2>&1; then duas "curl" t_curl; [ $ULT = 0 ] && achado sistema curl "$(fix_sistema)"; fi
if command -v wget >/dev/null 2>&1; then duas "wget" t_wget; [ $ULT = 0 ] && achado sistema wget "$(fix_sistema)"; fi

# Node/Deno/Bun: os do PATH + os achados no disco (nvm, /opt, Node embutido de agentes e apps)
NODES=(); DENOS=(); BUNS=(); PYS=(); CERTIFIS=(); JKS=()
command -v node >/dev/null 2>&1 && NODES+=("$(readlink -f "$(command -v node)")")
for x in "$(command -v deno 2>/dev/null)" "$HOME/.deno/bin/deno"; do [ -n "$x" ] && [ -x "$x" ] && DENOS+=("$(readlink -f "$x")"); done
for x in "$(command -v bun 2>/dev/null)" "$HOME/.bun/bin/bun"; do [ -n "$x" ] && [ -x "$x" ] && BUNS+=("$(readlink -f "$x")"); done
while read -r ks kt; do [ -n "$ks" ] && JKS+=("$ks|$kt"); done < <(java_achar)
for k in /usr/lib/jvm/*/lib/security/cacerts /usr/lib/jvm/*/jre/lib/security/cacerts; do
  [ -f "$k" ] || continue; h=${k%/lib/security/cacerts}; h=${h%/jre}
  kt="$h/bin/keytool"; [ -x "$kt" ] || kt="$h/jre/bin/keytool"; [ -x "$kt" ] || kt=$(command -v keytool 2>/dev/null || echo keytool)
  JKS+=("$(readlink -f "$k")|$kt")
done
if [ $RAPIDO = 0 ]; then
  echo "   (procurando venvs, Node/Deno/Bun, JDKs e certifi no disco — até 3 min; use --rapido para pular)"
  # / e, se estiverem em outra partição, /home /opt /srv /var/www /root (o -xdev não cruza partições)
  RAIZES=(/); for m in /home /opt /srv /var/www /root; do mountpoint -q "$m" 2>/dev/null && RAIZES+=("$m"); done
  while IFS= read -r f; do
    case "$f" in
      */pyvenv.cfg) d=${f%/pyvenv.cfg}; [ -x "$d/bin/python" ] && PYS+=("$d/bin/python");;
      */conda-meta) d=${f%/conda-meta}; [ -x "$d/bin/python" ] && PYS+=("$d/bin/python");;   # ambientes conda
      */certifi-*.dist-info) CERTIFIS+=("$f");;
      */security/cacerts) h=${f%/lib/security/cacerts}; h=${h%/jre}
        kt="$h/bin/keytool"; [ -x "$kt" ] || kt="$h/jre/bin/keytool"; [ -x "$kt" ] || kt=$(command -v keytool 2>/dev/null || echo keytool)
        JKS+=("$(readlink -f "$f")|$kt");;
      */node|*/deno|*/bun) head -c4 "$f" 2>/dev/null | grep -q ELF || continue
        case "$f" in */node) NODES+=("$(readlink -f "$f")");; */deno) DENOS+=("$(readlink -f "$f")");; */bun) BUNS+=("$(readlink -f "$f")");; esac;;
    esac
  done < <(timeout 180 find "${RAIZES[@]}" -xdev \( -path /proc -o -path /sys -o -path '*/Trash/*' -o -path '*/.cache/uv' -o -path '*/.local/share/Trash' -o -path /var/lib/docker -o -path '*conda*/pkgs' \) -prune -o \
            \( -name pyvenv.cfg -o \( -type d -name conda-meta \) -o -name 'certifi-*.dist-info' -o \( -type f -name cacerts -path '*/lib/security/*' \) -o \( -type f -perm -u+x \( -name node -o -name deno -o -name bun \) \) \) -print 2>/dev/null)
fi
uniq_arr(){ printf '%s\n' "$@" | awk 'NF && !s[$0]++'; }
mapfile -t NODES < <(uniq_arr ${NODES[@]+"${NODES[@]}"})
mapfile -t DENOS < <(uniq_arr ${DENOS[@]+"${DENOS[@]}"})
mapfile -t BUNS < <(uniq_arr ${BUNS[@]+"${BUNS[@]}"})
mapfile -t PYS < <(uniq_arr ${PYS[@]+"${PYS[@]}"})
mapfile -t CERTIFIS < <(uniq_arr ${CERTIFIS[@]+"${CERTIFIS[@]}"})
mapfile -t JKS < <(printf '%s\n' ${JKS[@]+"${JKS[@]}"} | awk -F'|' 'NF && !s[$1]++')
EXP_NODES=(); EXP_PYS=()
for n in ${NODES[@]+"${NODES[@]}"}; do
  v=$("$n" -v 2>/dev/null) || continue
  duas "node $v $(curto "$n")" t_node "$n"
  echo "          versão: $(node_fix "$v")"
  [ $ULT = 0 ] && { achado node "$(curto "$n") ($v)" "$(node_cmd "$n" "$v")"; EXP_NODES+=("$n"); }
done
for d in ${DENOS[@]+"${DENOS[@]}"}; do
  v=$("$d" -v 2>/dev/null | awk '{print $2}') || continue
  duas "deno $v $(curto "$d")" t_deno "$d"
  dcmd="$(curto "$d") upgrade"; [ -x "$(dirname "$d")/python" ] && dcmd="$(curto "$(dirname "$d")")/python -m pip install -U deno   # Deno instalado pelo pip neste venv"
  [ $ULT = 0 ] && { achado deno "$(curto "$d") ($v)" "$dcmd"; EXP_NODES+=("$d"); }
done
for b in ${BUNS[@]+"${BUNS[@]}"}; do
  v=$("$b" -v 2>/dev/null) || continue
  duas "bun $v $(curto "$b")" t_bun "$b"
  [ $ULT = 0 ] && { achado bun "$(curto "$b") ($v)" "$(curto "$b") upgrade"; EXP_NODES+=("$b"); }
done
if command -v python3 >/dev/null 2>&1; then
  py_duas "python3 do sistema (ssl)" python3 sistema
  [ $ULT = 0 ] && achado sistema "python3 (ssl)" "$(fix_sistema)"
  py_duas "python3 do sistema (certifi)" python3 certifi
  if [ $ULT = 0 ]; then w=$(python3 -c 'import certifi;print(certifi.where())' 2>/dev/null)
    case "$w" in
      "$HOME"/.local/*) achado python "python3 do sistema: certifi do usuário em $(curto "${w%/certifi/*}")" "python3 -m pip install --user --break-system-packages -U certifi";;
      /usr/lib/python3/dist-packages/*) achado sistema "python3 (certifi do pacote)" "$(fix_sistema)";;
      *) achado python "python3 do sistema: certifi em $w" "python3 -m pip install -U certifi";;
    esac
  fi
fi
for p in ${PYS[@]+"${PYS[@]}"}; do
  py_duas "$([ -d "${p%/bin/python}/conda-meta" ] && echo conda || echo venv) $(curto "${p%/bin/python}")" "$p" certifi
  [ $ULT = 0 ] && { achado venv "$(curto "${p%/bin/python}")" "$(venv_cmd "${p%/bin/python}")"; EXP_PYS+=("${p%/bin/python}"); }
done
if [ $GO = 1 ] && command -v go >/dev/null 2>&1; then
  cat > "$TMPD/t.go" <<'GO'
package main
import ("net/http";"os";"strings";"time")
func main(){c:=&http.Client{Timeout:10*time.Second};r,err:=c.Get(os.Args[1]);if err==nil{r.Body.Close();os.Exit(10)};s:=err.Error();if strings.Contains(s,"x509")||strings.Contains(s,"certificate"){os.Exit(11)};os.Exit(12)}
GO
  if (cd "$TMPD" && GOTOOLCHAIN=local GOCACHE="$TMPD/gocache" GOENV=off GOFLAGS= GO111MODULE=off timeout 300 go build -o "$TMPD/t" t.go) >/dev/null 2>&1; then
    t_go(){ "$TMPD/t" "$1" >/dev/null 2>&1; mapa $?; }
    duas "go $(go version | awk '{print $3}') (programa novo)" t_go
    [ $ULT = 0 ] && achado sistema "go (usa a lista do sistema)" "$(fix_sistema)"
  else linha 2 "go (não compilou o teste)" "" ""; fi
fi

# Java: a lista (keystore) — o teste de conexão exigiria compilar código Java
if [ ${#JKS[@]} -gt 0 ]; then
  echo "-- Java: lista de confiança (cacerts) — conferida pelo keytool, sem conexão"
  for j in "${JKS[@]}"; do ks=${j%%|*}; kt=${j#*|}
    java_lista "$ks" "$kt" "java $(curto "$ks")"
    if [ $ULT = 0 ]; then
      if [ "$ks" = /etc/ssl/certs/java/cacerts ]; then achado java "$ks" "[ \$(grep -cE '^!mozilla/(emSign_ECC_Root_CA_-_G3|Comodo_AAA_Services_root)' /etc/ca-certificates.conf) = 2 ] && sudo cp -a $ks $ks.bak && for a in debian:emsign_ecc_root_ca_-_g3.pem debian:comodo_aaa_services_root.pem; do sudo keytool -delete -alias \$a -keystore $ks -storepass changeit; done   # update-ca-certificates -f sozinho não tira as raízes; só remove se o sistema já desconfia das duas (!); backup em .bak"
      else achado java "$(curto "$ks")" "atualize o JDK dono deste cacerts (ele tem lista própria)"; fi
    fi
  done
fi

# PHP2Shell no host
for p in $(command -v php 2>/dev/null) /usr/sbin/php-fpm* /usr/bin/php[0-9]*; do
  [ -x "$p" ] && [ -f "$p" ] && echo "$(readlink -f "$p") $p"
done | awk '!s[$1]++{print $2}' > "$TMPD/php.lst"
if [ ! -s "$TMPD/php.lst" ]; then echo "-- PHP2Shell: php não encontrado neste servidor (containers: veja abaixo)"
else
  echo "-- PHP2Shell (corrigido: 8.5.12 · 8.4.27 · 8.3.36 · 8.2.35)"
  while read -r p; do php_ver "$p" "$(basename "$p")"
    [ $ULT = 0 ] && achado php "$p" "sudo apt update && sudo apt install --only-upgrade \$(dpkg -l 'php*' | awk '/^ii/{print \$2}')   # depois reinicie php-fpm/apache2"
    [ $ULT = 4 ] && achado php-verificar "$p" "apt changelog do pacote php: procure CVE-2026-109618"
  done < "$TMPD/php.lst"
fi

if [ ${#CERTIFIS[@]} -gt 0 ]; then
  echo "-- certifi abaixo de $CERTIFI_MIN (atualize: python -m pip install -U certifi)"
  velhos=0
  for c in "${CERTIFIS[@]}"; do v=$(basename "$c" | sed 's/^certifi-//;s/\.dist-info$//')
    vge "$v" "$CERTIFI_MIN" && continue
    case "$c" in /usr/lib/python3/dist-packages/*)   # pacote da distribuição (Debian/Ubuntu): aponta para a lista do sistema
      echo "   $v  /usr/lib/python3/dist-packages  (pacote do sistema: usa o ca-certificates — vale o teste de conexão acima)"; continue;; esac
    echo "   $v  $(curto "${c%/certifi-*}")"; velhos=$((velhos+1))
  done
  [ $velhos = 0 ] && echo "   nenhum venv desatualizado"
fi

# ---------------------------------------------------------------------------------------------
# Containers: testa de dentro de cada um (até 6 ao mesmo tempo) e classifica a correção pelo docker inspect.
cont_cmd(){ c=$1
  img=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null)
  run_id=$(docker inspect -f '{{.Image}}' "$c" 2>/dev/null)
  tag_id=$(docker image inspect -f '{{.Id}}' "$img" 2>/dev/null)
  dig=$(docker image inspect -f '{{len .RepoDigests}}' "$img" 2>/dev/null)
  proj=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$c" 2>/dev/null)
  svc=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$c" 2>/dev/null)
  wd=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$c" 2>/dev/null)
  supa=$(docker inspect -f '{{index .Config.Labels "com.supabase.cli.project"}}' "$c" 2>/dev/null)
  tag=${img##*:}; [ "$tag" = "$img" ] && tag=latest
  ondecompose=""; [ -n "$svc" ] && ondecompose="cd $(curto "${wd:-.}") && "
  if [ -n "$supa" ]; then
    echo "supabase	$supa	docker exec supabase_db_$supa pg_dumpall -U postgres > supabase-$supa.sql && npx -y supabase@latest stop && npx -y supabase@latest start   # na pasta do projeto $supa; sem --no-backup; nunca docker rm; depois rode o audita.sh: se seguir EXPOSTO, a imagem do fornecedor ainda não foi corrigida (não sobrescreva a tag com imagem local)"
  elif [ -n "$tag_id" ] && [ "$tag_id" != "$run_id" ]; then
    if [ -n "$svc" ]; then echo "recriar	$c ($img)	${ondecompose}docker compose up -d $svc   # a imagem nova já está no disco; o container roda a antiga"
    else echo "recriar	$c ($img)	recrie $c com a mesma imagem $img (salve antes: docker inspect $c > $c.inspect.json; confira portas, env e .Mounts)"; fi
  elif [ "${dig:-0}" = 0 ]; then
    echo "local	$c ($img)	imagem construída aqui: use a camada por cima da imagem antiga (guia, seção Containers): docker tag $img ${img%:*}:pre-emudhra; FROM ${img%:*}:pre-emudhra + ca-certificates/certifi/node novos"
  elif echo "$tag" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+|^[0-9]{4}\.[0-9]{2}\.[0-9]{2}'; then   # X.Y.Z exato ou data: fixada (X.Y-alpine recebe patch: flutuante)
    echo "fixada	$c ($img)	versão fixada: puxar a mesma tag não corrige; suba a versão (compose/config) para uma lançada depois de 21/10/2026"
  elif [ -n "$svc" ] && echo "$img" | grep -qiE '(^|/)(postgres|mysql|mariadb|mongo)(:|$)' && ! echo "$tag" | grep -qE '^[0-9]'; then
    echo "flutuante	$c ($img)	BANCO sem versão principal fixa: fixe a versão atual no compose (ex.: postgres:16-alpine) e faça o dump ANTES; depois ${ondecompose}docker compose up -d --pull always $svc"
  elif [ -n "$svc" ]; then
    echo "flutuante	$c ($img)	${ondecompose}docker compose up -d --pull always $svc   # se continuar EXPOSTO: o fornecedor ainda não atualizou; use a camada local"
  else
    echo "flutuante	$c ($img)	docker pull $img; salve docker inspect $c; recrie $c com as mesmas portas/env/volumes (sem volume: copie os dados antes)"
  fi; }

if [ $DOCKER = 1 ] && command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
  echo "-- containers Docker em execução (teste de dentro de cada um)"
  mapfile -t CONTS < <(docker ps --format '{{.Names}}')
  i=0
  for c in ${CONTS[@]+"${CONTS[@]}"}; do i=$((i+1))
    ( out=$(printf '%s\nbasico\n' "$SONDA" | timeout 120 docker exec -i "$c" sh -s 2>&1); echo $? > "$TMPD/c$i.rc"; printf '%s\n' "$out" > "$TMPD/c$i.out" ) &
    while [ "$(jobs -rp | wc -l)" -ge 6 ]; do sleep 0.3; done
  done
  wait
  i=0
  for c in ${CONTS[@]+"${CONTS[@]}"}; do i=$((i+1))
    img=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null)
    echo "   [$c] $img"
    out=$(cat "$TMPD/c$i.out" 2>/dev/null); r=$(cat "$TMPD/c$i.rc" 2>/dev/null || echo 1)
    if echo "$out" | grep -q 'executable file not found'; then echo "   (sem shell no container — imagem mínima; teste a imagem de outra forma)"
    elif [ -n "$out" ]; then echo "$out" | sed '/^$/d;s/^/   /'
      echo "$out" | grep -q '^VERIFIQUE.* PHP ' && achado php-verificar "container $c" "docker exec $c php -v; confira no changelog do pacote se tem a correção do CVE-2026-109618"
      e=$(echo "$out" | grep -c '^EXPOSTO'); N_EXP=$((N_EXP + e)); N_SEM=$((N_SEM + $(echo "$out" | grep -c '^SEM TESTE'))); N_VER=$((N_VER + $(echo "$out" | grep -c '^VERIFIQUE')))
      if [ "$e" -gt 0 ]; then
        if echo "$out" | grep '^EXPOSTO' | grep -q ' PHP '; then achado php "container $c" "atualize a imagem/tag do PHP (ou a do app) para PHP corrigido e recrie"; fi
        if echo "$out" | grep '^EXPOSTO' | grep -qv ' PHP '; then IFS=$'\t' read -r t a cmd < <(cont_cmd "$c"); achado "container-$t" "$a" "$cmd"; fi
      fi
    elif [ "$r" = 126 ] || [ "$r" = 127 ]; then echo "   (sem shell no container — imagem mínima; teste a imagem de outra forma)"
    else echo "   (nenhuma ferramenta de rede no container: curl/wget/node/python3 ausentes)"; fi
  done
fi

# ---------------------------------------------------------------------------------------------
# Quem reiniciar: processo já em execução não relê a lista. Só lista; não reinicia nada.
# unidade do processo: "sistema:<unit>", "usuario:<unit>" ou "processo" (sessão, tmux, terminal: reinicie só o processo,
# nunca o user@NNNN.service, que derruba a sessão inteira do usuário)
unidade(){ cg=$(tail -1 "/proc/$1/cgroup" 2>/dev/null); cg=${cg##*::}
  case "$cg" in
    /system.slice/*.service*) u=${cg#/system.slice/}; echo "sistema:${u%%/*}";;
    */user@*.service/*) u=${cg##*user@*.service/}; u=$(echo "$u" | tr '/' '\n' | grep '\.service$' | tail -1)
      if [ -n "$u" ]; then echo "usuario:$u"; else echo "processo"; fi;;
    *) echo "processo";; esac; }
REI=()
agora=$(date +%s)
while read -r pid et args; do
  [ -r "/proc/$pid/exe" ] || continue
  exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
  b=$(basename "${exe% (deleted)}")
  motivo=""
  case "$exe" in *" (deleted)") case "$b" in node*|deno|bun|java|php*) motivo="o binário foi atualizado depois que o processo começou";; esac;; esac
  if [ -z "$motivo" ] && [ "$b" = java ]; then
    for j in ${JKS[@]+"${JKS[@]}"}; do k=${j%%|*}
      [ $((agora - et)) -lt "$(stat -c %Y "$k" 2>/dev/null || echo 0)" ] && motivo="Java que começou antes da mudança no $(curto "$k")"; done
  fi
  if [ -z "$motivo" ]; then
    for n in ${EXP_NODES[@]+"${EXP_NODES[@]}"}; do [ "$exe" = "$n" ] && motivo="usa $(basename "$n") ainda EXPOSTO (corrija antes)"; done
    for v in ${PYS[@]+"${PYS[@]}"}; do d=${v%/bin/python}
      case "$args" in "$d"/bin/*) ;; *) continue;; esac
      cp=$(ls "$d"/lib/python3*/site-packages/certifi/cacert.pem 2>/dev/null | head -1); [ -n "$cp" ] || continue
      if [ $((agora - et)) -lt "$(stat -c %Y "$cp")" ]; then motivo="começou antes da atualização do certifi de $(curto "$d")"; fi
    done
  fi
  [ -n "$motivo" ] && REI+=("$pid|$(unidade "$pid")|$(echo "$args" | cut -c1-70)|$motivo")
done < <(ps -eo pid=,etimes=,args= 2>/dev/null)
if [ ${#REI[@]} -gt 0 ]; then
  echo "-- processos a reiniciar (não reinicie no meio de job, upload ou live; escolha a hora)"
  for r in "${REI[@]}"; do IFS='|' read -r pid un cmd mot <<< "$r"
    case "$un" in
      sistema:*) rot="${un#sistema:} (sistema)"; fx="sudo systemctl restart ${un#sistema:}";;
      usuario:*) rot="${un#usuario:} (--user)"; fx="systemctl --user restart ${un#usuario:}";;
      *) rot="processo avulso"; fx="reinicie o programa do pid $pid ($cmd) pelo jeito que você o iniciou (terminal, tmux, pm2) — não reinicie a sessão";;
    esac
    case "$cmd" in *"PM2 v"*|*"God Daemon"*) fx="pm2 update   # reinicia o daemon do pm2 e os apps dele";; esac
    printf 'REINICIE   pid %-8s %-34s %s\n           %s\n' "$pid" "$rot" "$cmd" "$mot"; N_REI=$((N_REI+1))
    achado reiniciar "$rot" "$fx"
  done
fi

# ---------------------------------------------------------------------------------------------
echo "-- resumo $(hostname): $N_EXP EXPOSTO · $N_SEM SEM TESTE · $N_VER VERIFIQUE · $N_REI REINICIE"
if [ ${#ACH[@]} -gt 0 ]; then
  echo "-- o que corrigir, por tipo (conta itens; o resumo acima conta linhas, 2 por item: G3 e AAA)"
  printf '%s\n' "${ACH[@]}" | awk -F'\t' '
    BEGIN{d["sistema"]="lista do sistema (ca-certificates)"; d["node"]="Node"; d["deno"]="Deno"; d["bun"]="Bun";
      d["python"]="Python do sistema (certifi do usuário)"; d["venv"]="venvs e ambientes conda (certifi)"; d["java"]="Java (cacerts)";
      d["php"]="PHP2Shell"; d["php-verificar"]="PHP com número de distribuição";
      d["container-flutuante"]="containers de tag flutuante (grupo A: puxar e recriar)";
      d["container-recriar"]="containers rodando imagem velha já substituída (só recriar)";
      d["container-local"]="containers de imagem construída aqui (grupo B: camada por cima)";
      d["container-fixada"]="containers de versão fixada (grupo C: subir a versão)";
      d["container-supabase"]="Supabase local (grupo C: CLI + stop/start, depois testar)";
      d["reiniciar"]="processos a reiniciar (fora de job, upload ou live)"}
    { n[$1]++; if(!($1 in ex)){ex[$1]=$2; fx[$1]=$3; ord[++k]=$1} }
    END{for(i=1;i<=k;i++){t=ord[i]; printf "   %3d  %s\n        ex.: %s\n        → %s\n", n[t], (t in d?d[t]:t), ex[t], fx[t]}}'
  if [ $COMANDOS = 1 ]; then
    echo "-- comandos sugeridos (NÃO executados; revise, faça backup e rode um por um)"
    printf '%s\n' "${ACH[@]}" | awk -F'\t' '!s[$3]++{print "# " $2; print $3}' | sed 's/^/   /'
  else echo "   (use --comandos para ver a lista de comandos de correção, sem executar)"; fi
fi
[ "$(id -u)" = 0 ] && [ ${#ACH[@]} -gt 0 ] && echo "   Rodando como root: corrija venvs, Deno e Bun de outros usuários COMO O DONO (sudo -u <usuário> …), senão os arquivos ficam com dono root."
[ $N_EXP -gt 0 ] && { echo "   Há ferramenta que ainda confia nas chaves comprometidas (ou PHP vulnerável): corrija, reinicie e rode de novo."; exit 1; }
[ $N_SEM -gt 0 ] && { echo "   Alguns testes não rodaram (rede/DNS/timeout). Repita antes de concluir."; exit 2; }
[ $PHPOK = 1 ] && N_VER=0
[ $((N_REI + N_VER)) -gt 0 ] && { echo "   Nada conecta, mas falta reiniciar processos e/ou conferir o PHP: só termina com tudo zerado."; exit 3; }
exit 0
