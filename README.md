# 🛡️ auditoria-seguranca

[![GRAVE: atualize seus sistemas](guia/assets/banner.jpg)](https://inematds.github.io/auditoria-seguranca/guia/)

**🇧🇷 [Português](README.md) · 🇺🇸 [English](README.en.md) · 🇪🇸 [Español](README.es.md)**

## O que é

Este é um guia de segurança para quem tem servidor, site, automação ou agente de IA rodando. Em outubro de 2026 vieram duas notícias graves juntas: vazaram as chaves secretas de 8 certificados da certificadora eMudhra (uma delas era literalmente o número 4), e uma falha no PHP, chamada PHP2Shell, deixa invadir sites sem senha. O guia mostra como testar se cada ferramenta ainda está exposta, com um script que só lê e não muda nada, e como atualizar cada camada. Precisa só de um terminal na máquina que você quer conferir.

## 📖 Guia de uso

Guia completo (o que houve, como auditar, como atualizar, caso real, PHP2Shell, rotina): **https://inematds.github.io/auditoria-seguranca/guia/**

## Teste em 10 segundos

```bash
curl https://dv-g3b-emudhra.we-have-a-problem.com/
curl https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
# "SSL certificate problem" = protegido · mostrou a página = EXPOSTO
```

O navegador já está protegido. curl antigo, Python (certifi), Node, Deno, Bun, Java, Go, Docker, n8n e agentes de IA têm lista própria de certificados (ou seguem a do sistema/container) e precisam de correção própria.

## O script `audita.sh` (só leitura) — versão 1.1.0

Testa a **conexão real** (não só lista certificados) com curl, wget, cada Node, Deno e Bun do disco (inclusive os embutidos), o Python do sistema, cada venv e ambiente conda com o certifi dele e cada container Docker em execução. Confere também a lista do Java (`cacerts`, pelo `keytool`), a versão do PHP no servidor e nos containers (PHP2Shell) e os processos que precisam ser reiniciados. No fim, agrupa o que achou por tipo com a correção sugerida.

Estados: `EXPOSTO` (conectou), `protegido` (erro de certificado), `SEM TESTE` (rede/DNS/timeout — não conta como protegido), `VERIFIQUE` (PHP de distribuição abaixo da versão corrigida: confira o backport) e `REINICIE` (processo rodando com o programa ou a lista antiga).

```bash
curl -fsSLO https://raw.githubusercontent.com/inematds/auditoria-seguranca/main/audita.sh
less audita.sh                              # leia antes de rodar
chmod +x audita.sh
./audita.sh                                 # esta máquina (até 3 min)
./audita.sh --rapido                        # sem busca no disco
./audita.sh --comandos                      # lista os comandos de correção (não executa)
./audita.sh --go                            # teste real do Go (compila em pasta temporária, ~100 MB, apagada no fim)
./audita.sh --ssh root@servidor1 --ssh deploy@servidor2
./audita.sh --chave ~/.ssh/minha_chave --ssh root@servidor1
./audita.sh --hosts servidores.txt          # um destino SSH por linha
```

Saída: `0` nada exposto · `1` há EXPOSTO · `2` há teste que não rodou. O script nunca instala, altera ou corrige nada; só grava em pasta temporária apagada no fim.

## Versões corrigidas (eMudhra)

| Camada | Versão |
|---|---|
| Ubuntu | `20260816ubuntu0.<versão do Ubuntu>` (ex.: `20260816ubuntu0.24.04.1`) |
| Debian | `20250419~deb12u2` (12) · `20250419+deb13u1` (13) |
| Alpine | `20261020-r0` |
| Python | `certifi 2026.10.19` · `pip 26.2.2` · `uv 0.13.4` |
| Node | `22.23.4` · `24.22.1` · `26.12.1` (Node 20 sem correção) |
| Go | `1.27.3` · `1.26.10` + recompilar (no Linux segue a lista do sistema) |
| Java | `sudo update-ca-certificates -f` (refaz o `cacerts`) ou JDK novo |
| Deno · Bun | recusaram no nosso teste: `2.9.8` · `1.4.4` |
| Firefox / NSS | `158.0.1` · `3.131.1` |
| Electron | `44.9.1` · `43.8.1` · `42.11.16` |
| Rust | `rustls-webpki 0.103.16` · `webpki-roots 1.0.10` |

## PHP2Shell

`CVE-2026-109618` e `CVE-2026-109619`, execução remota sem login. Corrigido em **PHP 8.5.12 · 8.4.27 · 8.3.36 · 8.2.35**. Verificador: [openai/php2shell-checker](https://github.com/openai/php2shell-checker). Detalhes, mitigações temporárias e sinais de invasão no guia.

## O processo, do início ao fim

| # | Passo | Comando | Quem |
|---|---|---|---|
| 1 | Teste rápido com curl nas duas cadeias | `curl https://dv-g3b-emudhra.we-have-a-problem.com/` | 🧠 você |
| 2 | Auditoria completa da máquina, com a lista de correções | `./audita.sh --comandos` | ⚙️ script |
| 3 | Auditoria dos servidores | `./audita.sh --hosts servidores.txt` | ⚙️ script |
| 4 | Atualizar o sistema (e o `cacerts` do Java) | `sudo apt install --only-upgrade ca-certificates` · `sudo update-ca-certificates -f` | 🧠 você |
| 5 | Atualizar o certifi de cada venv / conda | `<venv>/bin/python -m pip install -U certifi` · `uv pip install --python <venv>/bin/python -U certifi` | 🧠 você |
| 6 | Trocar o Node (20 → 22/24), atualizar Deno e Bun | `nvm install 22` · `sudo apt install --only-upgrade nodejs` · `deno upgrade` · `bun upgrade` | 🧠 você |
| 7 | Containers por grupo: A puxar e recriar · B camada por cima · C subir a versão / Supabase | `docker compose up -d --pull always <svc>` · `FROM <img>:pre-emudhra` · `supabase stop && supabase start` | 🧠 você |
| 8 | Achar e reiniciar serviços (fora de job/upload/live) | seção `processos a reiniciar` do script · `systemctl restart …` · `pm2 restart all` | 🧠 você |
| 9 | Auditar de novo até zerar | `./audita.sh` → `0 EXPOSTO · 0 SEM TESTE` | ⚙️ script |
| 10 | PHP: testar, atualizar, reiniciar workers (servidor e containers) | `node phpcheck.js https://seusite` · `apt install --only-upgrade 'php*'` | 🧠 você |
| 11 | Rotina mensal | checklist da seção Rotina do guia | 🧠 você |

O histórico de versões está no [CHANGELOG.md](CHANGELOG.md).

## Fontes

- https://emudhra.we-have-a-problem.com/
- https://bugzilla.mozilla.org/show_bug.cgi?id=2083449
- https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/
- https://socradar.io/blog/emudhra-ca-key-compromise-weak-keys-risks-and-fixes/
- https://www.php.net/archive/2026.php#2026-10-21-5
- https://github.com/openai/php2shell-checker

## Licença

MIT. Aberto e gratuito — [INEMA.CLUB](https://inema.club).
