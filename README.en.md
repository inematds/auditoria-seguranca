# 🛡️ auditoria-seguranca

[![CRITICAL: update your systems](guia/assets/banner-en.jpg)](https://inematds.github.io/auditoria-seguranca/guia/en/)

**🇧🇷 [Português](README.md) · 🇺🇸 [English](README.en.md) · 🇪🇸 [Español](README.es.md)**

## What it is

This is a security guide for anyone running a server, website, automation, or AI agent. In October 2026, two serious pieces of news landed together: the private keys of 8 certificates from the certificate authority eMudhra leaked (one of them was literally number 4), and a flaw in PHP, called PHP2Shell, lets attackers break into sites without a password. The guide shows how to test whether each tool is still exposed, using a script that only reads and changes nothing, and how to update each layer. All you need is a terminal on the machine you want to check.

## 📖 User guide

Full guide (what happened, how to audit, how to update, a real case, PHP2Shell, routine): **https://inematds.github.io/auditoria-seguranca/guia/en/**

## 10-second test

```bash
curl https://dv-g3b-emudhra.we-have-a-problem.com/
curl https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
# "SSL certificate problem" = protegido · mostrou a página = EXPOSTO
```

Your browser is already protected. Older curl, Python (certifi), Node, Go, Docker, n8n, and AI agents each ship their own certificate list and need their own fix.

## The `audita.sh` script (read-only)

It tests the **real connection** (not just a list of certificates) with curl, wget, every Node on disk (including embedded Node), the system Python, each venv with its own certifi, and every running Docker container. Three states: `EXPOSTO` (exposed: the connection succeeded), `protegido` (protected: certificate error), and `SEM TESTE` (not tested: network/DNS/timeout — does not count as protected).

```bash
curl -fsSLO https://raw.githubusercontent.com/inematds/auditoria-seguranca/main/audita.sh
less audita.sh                              # read it before running
chmod +x audita.sh
./audita.sh                                 # this machine (up to 3 min)
./audita.sh --rapido                        # skips the disk search
./audita.sh --ssh root@servidor1 --ssh deploy@servidor2
./audita.sh --hosts servidores.txt          # one SSH target per line
```

Exit code: `0` nothing exposed · `1` something is EXPOSTO · `2` a test did not run.

## Fixed versions (eMudhra)

| Layer | Version |
|---|---|
| Ubuntu | `20260816ubuntu0.<Ubuntu version>` (e.g. `20260816ubuntu0.24.04.1`) |
| Debian | `20250419~deb12u2` (12) · `20250419+deb13u1` (13) |
| Alpine | `20261020-r0` |
| Python | `certifi 2026.10.19` · `pip 26.2.2` · `uv 0.13.4` |
| Node | `22.23.4` · `24.22.1` · `26.12.1` (no fix for Node 20) |
| Go | `1.27.3` · `1.26.10` + recompile |
| Firefox / NSS | `158.0.1` · `3.131.1` |
| Electron | `44.9.1` · `43.8.1` · `42.11.16` |
| Rust | `rustls-webpki 0.103.16` · `webpki-roots 1.0.10` |

## PHP2Shell

`CVE-2026-109618` and `CVE-2026-109619`, remote code execution without login. Fixed in **PHP 8.5.12 · 8.4.27 · 8.3.36 · 8.2.35**. Checker: [openai/php2shell-checker](https://github.com/openai/php2shell-checker). Details, temporary mitigations, and signs of compromise are in the guide.

## The process, from start to finish

| # | Step | Command | Who |
|---|---|---|---|
| 1 | Quick curl test on both chains | `curl https://dv-g3b-emudhra.we-have-a-problem.com/` | 🧠 you |
| 2 | Full audit of the machine | `./audita.sh` | ⚙️ script |
| 3 | Audit your servers | `./audita.sh --hosts servidores.txt` | ⚙️ script |
| 4 | Update the system | `sudo apt install --only-upgrade ca-certificates` | 🧠 you |
| 5 | Update certifi in each venv | `<venv>/bin/python -m pip install -U certifi pip` | 🧠 you |
| 6 | Replace Node (20 → 22/24) | `nvm install 22` or the NodeSource repository `setup_22.x` | 🧠 you |
| 7 | Rebuild containers / update n8n (with a backup) | `docker compose build --pull` / `docker compose pull` | 🧠 you |
| 8 | Restart services | `systemctl restart …` · `pm2 restart all` · `docker compose up -d` | 🧠 you |
| 9 | Audit again until it's clean | `./audita.sh` → `0 EXPOSTO · 0 SEM TESTE` | ⚙️ script |
| 10 | PHP: test, update, restart workers | `node phpcheck.js https://seusite` · `apt install --only-upgrade 'php*'` | 🧠 you |
| 11 | Monthly routine | checklist in the Routine section of the guide | 🧠 you |

## Sources

- https://emudhra.we-have-a-problem.com/
- https://bugzilla.mozilla.org/show_bug.cgi?id=2083449
- https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/
- https://socradar.io/blog/emudhra-ca-key-compromise-weak-keys-risks-and-fixes/
- https://www.php.net/archive/2026.php#2026-10-21-5
- https://github.com/openai/php2shell-checker

## License

MIT. Open and free — [INEMA.CLUB](https://inema.club).
