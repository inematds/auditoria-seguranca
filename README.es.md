# 🛡️ auditoria-seguranca

[![GRAVE: actualiza tus sistemas](guia/assets/banner-es.jpg)](https://inematds.github.io/auditoria-seguranca/guia/es/)

**🇧🇷 [Português](README.md) · 🇺🇸 [English](README.en.md) · 🇪🇸 [Español](README.es.md)**

## Qué es

Esta es una guía de seguridad para quien tiene un servidor, un sitio, una automatización o un agente de IA en funcionamiento. En octubre de 2026 llegaron juntas dos noticias graves: se filtraron las claves secretas de 8 certificados de la certificadora eMudhra (una de ellas era literalmente la número 4), y una falla en PHP, llamada PHP2Shell, permite invadir sitios sin contraseña. La guía muestra cómo comprobar si cada herramienta sigue expuesta, con un script que solo lee y no cambia nada, y cómo actualizar cada capa. Solo necesitas una terminal en la máquina que quieres revisar.

## 📖 Guía de uso

Guía completa (qué ocurrió, cómo auditar, cómo actualizar, caso real, PHP2Shell, rutina): **https://inematds.github.io/auditoria-seguranca/guia/es/**

## Prueba en 10 segundos

```bash
curl https://dv-g3b-emudhra.we-have-a-problem.com/
curl https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
# "SSL certificate problem" = protegido · mostrou a página = EXPOSTO
```

El navegador ya está protegido. Las versiones antiguas de curl, Python (certifi), Node, Go, Docker, n8n y los agentes de IA tienen su propia lista de certificados y necesitan su propia corrección.

## El script `audita.sh` (solo lectura)

Prueba la **conexión real** (no solo lista certificados) con curl, wget, cada Node del disco (incluido el Node embebido), el Python del sistema, cada venv con su propio certifi y cada contenedor Docker en ejecución. Tres estados: `EXPOSTO` (expuesto: logró conectarse), `protegido` (error de certificado) y `SEM TESTE` (sin prueba: red/DNS/timeout — no cuenta como protegido).

```bash
curl -fsSLO https://raw.githubusercontent.com/inematds/auditoria-seguranca/main/audita.sh
less audita.sh                              # lee antes de ejecutar
chmod +x audita.sh
./audita.sh                                 # esta máquina (hasta 3 min)
./audita.sh --rapido                        # sin búsqueda en el disco
./audita.sh --ssh root@servidor1 --ssh deploy@servidor2
./audita.sh --hosts servidores.txt          # un destino SSH por línea
```

Salida: `0` nada expuesto · `1` hay EXPOSTO · `2` hay una prueba que no se ejecutó.

## Versiones corregidas (eMudhra)

| Capa | Versión |
|---|---|
| Ubuntu | `20260816ubuntu0.<versión de Ubuntu>` (ej.: `20260816ubuntu0.24.04.1`) |
| Debian | `20250419~deb12u2` (12) · `20250419+deb13u1` (13) |
| Alpine | `20261020-r0` |
| Python | `certifi 2026.10.19` · `pip 26.2.2` · `uv 0.13.4` |
| Node | `22.23.4` · `24.22.1` · `26.12.1` (Node 20 sin corrección) |
| Go | `1.27.3` · `1.26.10` + recompilar |
| Firefox / NSS | `158.0.1` · `3.131.1` |
| Electron | `44.9.1` · `43.8.1` · `42.11.16` |
| Rust | `rustls-webpki 0.103.16` · `webpki-roots 1.0.10` |

## PHP2Shell

`CVE-2026-109618` y `CVE-2026-109619`, ejecución remota sin inicio de sesión. Corregido en **PHP 8.5.12 · 8.4.27 · 8.3.36 · 8.2.35**. Verificador: [openai/php2shell-checker](https://github.com/openai/php2shell-checker). Los detalles, las mitigaciones temporales y las señales de intrusión están en la guía.

## El proceso, de principio a fin

| # | Paso | Comando | Quién |
|---|---|---|---|
| 1 | Prueba rápida con curl en las dos cadenas | `curl https://dv-g3b-emudhra.we-have-a-problem.com/` | 🧠 tú |
| 2 | Auditoría completa de la máquina | `./audita.sh` | ⚙️ script |
| 3 | Auditoría de los servidores | `./audita.sh --hosts servidores.txt` | ⚙️ script |
| 4 | Actualizar el sistema | `sudo apt install --only-upgrade ca-certificates` | 🧠 tú |
| 5 | Actualizar el certifi de cada venv | `<venv>/bin/python -m pip install -U certifi pip` | 🧠 tú |
| 6 | Cambiar el Node (20 → 22/24) | `nvm install 22` o repositorio NodeSource `setup_22.x` | 🧠 tú |
| 7 | Reconstruir contenedores / actualizar n8n (con respaldo) | `docker compose build --pull` / `docker compose pull` | 🧠 tú |
| 8 | Reiniciar servicios | `systemctl restart …` · `pm2 restart all` · `docker compose up -d` | 🧠 tú |
| 9 | Auditar de nuevo hasta dejar en cero | `./audita.sh` → `0 EXPOSTO · 0 SEM TESTE` | ⚙️ script |
| 10 | PHP: probar, actualizar, reiniciar workers | `node phpcheck.js https://seusite` · `apt install --only-upgrade 'php*'` | 🧠 tú |
| 11 | Rutina mensual | checklist de la sección Rutina de la guía | 🧠 tú |

## Fuentes

- https://emudhra.we-have-a-problem.com/
- https://bugzilla.mozilla.org/show_bug.cgi?id=2083449
- https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/
- https://socradar.io/blog/emudhra-ca-key-compromise-weak-keys-risks-and-fixes/
- https://www.php.net/archive/2026.php#2026-10-21-5
- https://github.com/openai/php2shell-checker

## Licencia

MIT. Abierto y gratuito — [INEMA.CLUB](https://inema.club).
