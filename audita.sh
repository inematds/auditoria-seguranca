#!/usr/bin/env bash
# audita.sh — auditoria SÓ LEITURA da confiança em certificados (caso eMudhra, out/2026).
#
# Não lista certificados: testa a CONEXÃO REAL contra dois sites de teste assinados pelas chaves
# comprometidas. Se a ferramenta conecta, ela ainda confia na cadeia ruim.
#   EXPOSTO   = conectou (a ferramenta aceitou o certificado ruim)
#   protegido = recusou por erro de certificado
#   SEM TESTE = não deu para testar (rede, DNS, timeout, ferramenta quebrada) — NÃO conta como protegido
#
# O que testa: curl, wget, cada Node encontrado, o Python do sistema e o Python de cada venv
# (com o certifi do venv), e dentro de cada container Docker em execução (node, python3, curl, wget).
# Também mostra versões: ca-certificates, Node, Go, certifi desatualizado (< 2026.10.19).
#
# Uso:
#   ./audita.sh                         # esta máquina
#   ./audita.sh --ssh root@servidor     # outra máquina por SSH (repita --ssh para várias)
#   ./audita.sh --hosts servidores.txt  # um destino SSH por linha (linhas com # são ignoradas)
#   ./audita.sh --rapido                # pula a busca no disco (venvs, Node embutido, certifi)
#   ./audita.sh --sem-docker            # não entra nos containers
#
# Nada é instalado, alterado ou gravado. Saída: 0 = nenhum EXPOSTO; 1 = há EXPOSTO; 2 = há SEM TESTE.
set -uo pipefail

CERTIFI_MIN=2026.10.19
RAPIDO=0; DOCKER=1; ALVOS=()
while [ $# -gt 0 ]; do case "$1" in
  --ssh) ALVOS+=("$2"); shift 2;;
  --hosts) while IFS= read -r l; do l="${l%%#*}"; l="$(echo "$l" | xargs)"; [ -n "$l" ] && ALVOS+=("$l"); done < "$2"; shift 2;;
  --rapido) RAPIDO=1; shift;;
  --sem-docker) DOCKER=0; shift;;
  --local) shift;;
  -h|--help) sed -n 2,22p "$0"; exit 0;;
  *) echo "argumento desconhecido: $1" >&2; exit 64;;
esac; done

# ---------------------------------------------------------------------------------------------
# Remoto: manda este mesmo arquivo pelo SSH e roda lá (só leitura). Um destino de cada vez.
if [ ${#ALVOS[@]} -gt 0 ]; then
  pior=0
  for a in "${ALVOS[@]}"; do
    echo "################ $a"
    flags=(); [ $RAPIDO = 1 ] && flags+=(--rapido); [ $DOCKER = 0 ] && flags+=(--sem-docker)
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$a" "bash -s -- --local ${flags[*]}" < "$0"; rc=$?
    [ $rc = 255 ] && { echo "SEM TESTE  ssh  não conectou em $a"; rc=2; }
    [ $rc = 1 ] && pior=1; [ $rc = 2 ] && [ $pior = 0 ] && pior=2
    echo
  done
  exit $pior
fi

# ---------------------------------------------------------------------------------------------
# SONDA: sh POSIX (roda no host e dentro de containers Alpine/Debian sem bash).
# Cada teste devolve 0 = conectou (EXPOSTO), 1 = erro de certificado (protegido), 2 = sem teste.
SONDA=$(cat <<'SH'
U_G3=https://dv-g3b-emudhra.we-have-a-problem.com/
U_AAA=https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
JS='var u=process.argv[process.argv.length-1];var q=require("https").get(u,{timeout:10000},function(r){r.resume();process.exit(0)});q.on("timeout",function(){process.exit(2)});q.on("error",function(e){var c=String(e.code||"");process.exit(/CERT|UNABLE_TO|SELF_SIGNED|DEPTH_ZERO|ERR_TLS/.test(c)?1:2)})'
PY='
import ssl, sys
u, modo = sys.argv[1], sys.argv[2]
try:
    import urllib.request as R, urllib.error as E
except ImportError:
    sys.exit(2)
if modo == "certifi":
    try:
        import certifi
    except ImportError:
        sys.exit(3)
    ctx = ssl.create_default_context(cafile=certifi.where())
else:
    ctx = ssl.create_default_context()
try:
    R.urlopen(u, timeout=10, context=ctx)
    sys.exit(0)
except E.HTTPError:
    sys.exit(0)
except Exception as e:
    if "CERTIFICATE_VERIFY_FAILED" in str(e) or "certificate verify failed" in str(e):
        sys.exit(1)
    sys.exit(2)
'
st(){ case "$1" in 0) echo "EXPOSTO  ";; 1) echo "protegido";; *) echo "SEM TESTE";; esac; }
linha(){ printf '%s  %-34s %-4s %s\n' "$(st "$1")" "$2" "$3" "$4"; }
t_curl(){ e=$(curl -sS -o /dev/null -m 10 "$1" 2>&1); r=$?
  if [ $r = 0 ]; then return 0; elif [ $r = 60 ] || echo "$e" | grep -qi certif; then return 1; else return 2; fi; }
t_wget(){ e=$(wget -O /dev/null -T 10 "$1" 2>&1); r=$?   # sem -q: a mensagem de certificado vem no stderr
  if [ $r = 0 ] || [ $r = 8 ]; then return 0; elif [ $r = 5 ] || echo "$e" | grep -qi certif; then return 1; else return 2; fi; }
t_node(){ "$1" -e "$JS" "$2" >/dev/null 2>&1; }
t_py(){ "$1" -c "$PY" "$2" "$3" >/dev/null 2>&1; }
# testa as duas cadeias com um comando; $1 = rótulo, resto = função + args (a URL vai no fim)
duas(){ rot=$1; shift
  for par in "G3 $U_G3" "AAA $U_AAA"; do tag=${par%% *}; u=${par#* }
    "$@" "$u"; r=$?            # guarda o código ANTES de qualquer echo
    linha "$r" "$rot" "$tag" ""
  done; }
py_duas(){ rot=$1; py=$2; modo=$3
  for par in "G3 $U_G3" "AAA $U_AAA"; do tag=${par%% *}; u=${par#* }
    t_py "$py" "$u" "$modo"; r=$?
    [ $r = 3 ] && return 0     # sem certifi neste Python: nada a testar nesse modo
    linha "$r" "$rot" "$tag" ""
  done; }
basico(){ # ferramentas no PATH (usado dentro de containers)
  command -v curl >/dev/null 2>&1 && duas "curl" t_curl
  command -v wget >/dev/null 2>&1 && duas "wget" t_wget
  if command -v node >/dev/null 2>&1; then duas "node $(node -v 2>/dev/null)" t_node node; fi
  if command -v python3 >/dev/null 2>&1; then
    py_duas "python3 (ssl do sistema)" python3 sistema
    py_duas "python3 (certifi)" python3 certifi
  fi
  true; }
SH
)
eval "$SONDA"
N_EXP=0; N_SEM=0
conta(){ case "$1" in 0) N_EXP=$((N_EXP+1));; 1) ;; *) N_SEM=$((N_SEM+1));; esac; }
# no host, cada linha também entra no resumo (dentro dos containers a contagem é feita pelo texto)
linha(){ conta "$1"; printf '%s  %-34s %-4s %s\n' "$(st "$1")" "$2" "$3" "$4"; }

ver_ge(){ [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }   # $1 >= $2
node_fix(){ v=${1#v}; case "${v%%.*}" in
  22) ver_ge "$v" 22.23.4 && echo "ok (>= 22.23.4)" || echo "ATUALIZE para 22.23.4+";;
  24) ver_ge "$v" 24.22.1 && echo "ok (>= 24.22.1)" || echo "ATUALIZE para 24.22.1+";;
  26) ver_ge "$v" 26.12.1 && echo "ok (>= 26.12.1)" || echo "ATUALIZE para 26.12.1+";;
  *) echo "linha SEM correção — troque para Node 22, 24 ou 26";; esac; }

echo "== $(hostname) · $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-?}") · $(date '+%d/%m/%Y %H:%M')"

echo "-- versões"
if command -v dpkg-query >/dev/null 2>&1; then echo "ca-certificates $(dpkg-query -W -f='${Version}' ca-certificates 2>/dev/null)"
elif command -v apk >/dev/null 2>&1; then echo "ca-certificates $(apk info -v ca-certificates 2>/dev/null | head -1)"
elif command -v rpm >/dev/null 2>&1; then echo "ca-certificates $(rpm -q ca-certificates 2>/dev/null)"; fi
if ls /etc/ssl/certs 2>/dev/null | grep -qi 'emSign_ECC_Root_CA_-_G3'; then echo "raiz emSign ECC G3 ainda presente em /etc/ssl/certs (normal: a correção bloqueia os intermediários, o teste de conexão é o que vale)"; fi
command -v go >/dev/null 2>&1 && { gv=$(go version | awk '{print $3}'); echo "go $gv — corrigido: 1.27.3 / 1.26.10; binários Go antigos precisam ser RECOMPILADOS"; }
systemctl is-enabled unattended-upgrades >/dev/null 2>&1 && echo "unattended-upgrades: ligado"

echo "-- conexão real (G3 = cadeia emSign ECC Root CA - G3 · AAA = cadeia cruzada AAA Certificate Services)"
command -v curl >/dev/null 2>&1 && duas "curl" t_curl
command -v wget >/dev/null 2>&1 && duas "wget" t_wget

# Node: o do PATH + os achados no disco (nvm, /opt, Node embutido de agentes e apps)
NODES=(); command -v node >/dev/null 2>&1 && NODES+=("$(readlink -f "$(command -v node)")")
PYS=(); CERTIFIS=()
if [ $RAPIDO = 0 ]; then
  echo "   (procurando venvs, Node e certifi no disco — até 3 min; use --rapido para pular)"
  while IFS= read -r f; do
    case "$f" in
      */pyvenv.cfg) d=${f%/pyvenv.cfg}; [ -x "$d/bin/python" ] && PYS+=("$d/bin/python");;
      */certifi-*.dist-info) CERTIFIS+=("$f");;
      */node) head -c4 "$f" 2>/dev/null | grep -q ELF && NODES+=("$(readlink -f "$f")");;
    esac
  done < <(timeout 180 find / -xdev \( -path /proc -o -path /sys -o -path '*/Trash/*' -o -path '*/.cache/uv' -o -path '*/.local/share/Trash' -o -path /var/lib/docker \) -prune -o \
            \( -name pyvenv.cfg -o -name 'certifi-*.dist-info' -o \( -type f -name node -perm -u+x \) \) -print 2>/dev/null)
fi
mapfile -t NODES < <(printf '%s\n' "${NODES[@]}" | awk 'NF && !s[$0]++')
for n in "${NODES[@]}"; do
  v=$("$n" -v 2>/dev/null) || continue
  duas "node $v $(echo "$n" | sed "s|^$HOME|~|")" t_node "$n"
  echo "          versão: $(node_fix "$v")"
done
if command -v python3 >/dev/null 2>&1; then
  py_duas "python3 do sistema (ssl)" python3 sistema
  py_duas "python3 do sistema (certifi)" python3 certifi
fi
for p in "${PYS[@]}"; do
  py_duas "venv $(echo "${p%/bin/python}" | sed "s|^$HOME|~|")" "$p" certifi
done

if [ ${#CERTIFIS[@]} -gt 0 ]; then
  echo "-- certifi abaixo de $CERTIFI_MIN (atualize: python -m pip install -U certifi)"
  velhos=0
  for c in "${CERTIFIS[@]}"; do v=$(basename "$c" | sed 's/^certifi-//;s/\.dist-info$//')
    ver_ge "$v" "$CERTIFI_MIN" && continue
    case "$c" in /usr/lib/python3/dist-packages/*)   # pacote da distribuição (Debian/Ubuntu): aponta para a lista do sistema
      echo "   $v  /usr/lib/python3/dist-packages  (pacote do sistema: usa o ca-certificates — vale o teste de conexão acima)"; continue;; esac
    echo "   $v  $(echo "${c%/certifi-*}" | sed "s|^$HOME|~|")"; velhos=$((velhos+1))
  done
  [ $velhos = 0 ] && echo "   nenhum venv desatualizado"
fi

if [ $DOCKER = 1 ] && command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
  echo "-- containers Docker em execução (teste de dentro de cada um)"
  for c in $(docker ps --format '{{.Names}}'); do
    img=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null)
    echo "   [$c] $img"
    out=$(printf '%s\nbasico\n' "$SONDA" | timeout 120 docker exec -i "$c" sh -s 2>&1); r=$?
    if echo "$out" | grep -q 'executable file not found'; then echo "   (sem shell no container — imagem mínima; teste a imagem de outra forma)"
    elif [ -n "$out" ]; then echo "$out" | sed 's/^/   /'
      N_EXP=$((N_EXP + $(echo "$out" | grep -c '^EXPOSTO'))); N_SEM=$((N_SEM + $(echo "$out" | grep -c '^SEM TESTE')))
    elif [ $r = 126 ] || [ $r = 127 ]; then echo "   (sem shell no container — imagem mínima; teste a imagem de outra forma)"
    else echo "   (nenhuma ferramenta de rede no container: curl/wget/node/python3 ausentes)"; fi
  done
fi

echo "-- resumo $(hostname): $N_EXP EXPOSTO · $N_SEM SEM TESTE"
[ $N_EXP -gt 0 ] && { echo "   Há ferramenta que ainda confia nas chaves comprometidas: veja o guia (Como atualizar) e rode de novo."; exit 1; }
[ $N_SEM -gt 0 ] && { echo "   Alguns testes não rodaram (rede/DNS/timeout). Repita antes de concluir."; exit 2; }
exit 0
