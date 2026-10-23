# 🛡️ auditoria-seguranca

[![GRAVE: actualiza tus sistemas](guia/assets/banner-es.jpg)](https://inematds.github.io/auditoria-seguranca/guia/es/)

**🇧🇷 [Português](README.md) · 🇺🇸 [English](README.en.md) · 🇪🇸 [Español](README.es.md)**

**Guía v1.1.2 · actualizada el 23/10/2026** <!-- versao: ferramentas/versao.py -->

## Qué es

Esta es una guía de seguridad para quien tiene un servidor, un sitio, una automatización o un agente de IA en funcionamiento. En octubre de 2026 llegaron juntas dos noticias graves: se filtraron las claves secretas de 8 certificados de la certificadora eMudhra (una de ellas era literalmente el número 4), y una falla en PHP, llamada PHP2Shell, permite invadir sitios sin contraseña. La guía muestra cómo comprobar si cada herramienta sigue expuesta, con un script que no instala ni altera nada (solo ejecuta las pruebas), y cómo actualizar cada capa. Solo necesitas una terminal en la máquina que quieres revisar.

## 📖 Guía de uso

Guía completa (qué pasó, cómo auditar, cómo actualizar, caso real, PHP2Shell, rutina): **https://inematds.github.io/auditoria-seguranca/guia/es/**

## Prueba en 10 segundos

```bash
curl https://dv-g3b-emudhra.we-have-a-problem.com/
curl https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
# "SSL certificate problem" = protegido · mostrou a página = EXPOSTO
```

El navegador ya está protegido. curl antiguo, Python (certifi), Node, Deno, Bun, Java, Go, Docker, n8n y agentes de IA tienen una lista propia de certificados (o siguen la del sistema/contenedor) y necesitan una corrección propia.

## ⚠ Antes y después de actualizar

> **Antes de actualizar cualquier cosa:** haz una copia de seguridad (base de datos, volúmenes, imagen antigua con etiqueta de respaldo, configuración) y comprueba que el sistema está sano **antes**.
>
> ```bash
> docker exec meu-postgres pg_dumpall -U postgres > backup-$(date +%F).sql   # base de datos
> docker tag meuapp:latest meuapp:pre-update                              # imagen antigua de respaldo
> docker inspect meuapp > meuapp.inspect.json                             # puertos, env, volúmenes
> curl -fsS https://meusite/health && echo OK                             # salud antes
> docker exec meu-postgres psql -U postgres -d app -c "select count(*) from clientes"   # anota los números
> ```
>
> **Después de actualizar:** muchas cosas que funcionaban pueden volverse incompatibles con la versión nueva (vimos una dependencia sin versión fija romper una app, un venv resincronizarse y deshacer la corrección, un proxy con dirección antigua dando 502). Prueba y valida: el servicio arrancó, responde, hace lo que hacía y los datos están ahí (mismos conteos). Da por terminado solo cuando esté ok **y en línea**.

## El script `audita.sh` (no altera nada)

Prueba la **conexión real** (no solo lista certificados) con curl, wget, cada Node, Deno y Bun del disco (incluidos los embebidos), el Python del sistema, cada venv y entorno conda con su certifi y cada contenedor Docker en ejecución. También revisa la lista de Java (`cacerts`, con `keytool`), la versión de PHP en el servidor y en los contenedores (PHP2Shell) y los procesos que necesitan reiniciarse. Al final, agrupa lo que encontró por tipo con la corrección sugerida.

Estados: `EXPOSTO` (expuesto: conectó), `protegido` (protegido: el certificado fue rechazado, con código o mensaje de verificación), `SEM TESTE` (sin prueba: la prueba no terminó o no prueba nada: red, DNS, timeout, contenedor sin shell o sin la herramienta, salida cortada, SSH que falló, búsqueda en el disco interrumpida, programa que no es seguro ejecutar — nunca cuenta como protegido), `VERIFIQUE` (verifica: PHP en versión de prueba, o de distribución por debajo de la versión corregida, comprueba el backport) y `REINICIE` (reinicia: proceso ejecutándose con el programa o la lista antigua).

```bash
curl -fsSLO https://raw.githubusercontent.com/inematds/auditoria-seguranca/main/audita.sh
less audita.sh                              # lee antes de ejecutar
chmod +x audita.sh
./audita.sh                                 # esta máquina (hasta 3 min)
./audita.sh --rapido                        # sin búsqueda en el disco
./audita.sh --comandos                      # lista los comandos de corrección (no los ejecuta)
./audita.sh --go                            # prueba real de Go (compila en carpeta temporal, ~100 MB, borrada al final)
./audita.sh --ssh root@servidor1 --ssh deploy@servidor2
./audita.sh --chave ~/.ssh/minha_chave --ssh root@servidor1
./audita.sh --hosts servidores.txt          # un destino SSH por línea
./audita.sh --raiz /opt --raiz /srv         # busca en el disco solo en esas carpetas
```

Salida: `0` las verificaciones hechas pasaron, **dentro del alcance impreso al final** (`--rapido`, `--sem-docker`, `--raiz`, `--php-ok` y el usuario aparecen ahí) · `1` hay EXPOSTO · `2` hay SEM TESTE · `3` falta reiniciar procesos o comprobar PHP.

> **El script señala problemas; no es un certificado de "todo protegido".** La salida `0` no quiere decir que toda la máquina esté segura, y no debe liberar un deploy por sí sola. No instala, no altera y no corrige nada, pero ejecuta las herramientas que prueba. Con `sudo`, un programa encontrado en el disco solo se ejecuta si el archivo, cada enlace y cada carpeta del camino son del root o del dueño y nadie más puede escribir en ellos; el de un usuario se ejecuta como ese usuario (`runuser`), nunca como root. Lo que no pasa queda como `SEM TESTE`.

Pruebas del propio script (sin red, sin contenedores reales): `bash testes/roda.sh`.

## Versiones corregidas (eMudhra)

| Capa | Versión |
|---|---|
| Ubuntu | `20260816ubuntu0.<versión de Ubuntu>` (ej.: `20260816ubuntu0.24.04.1`) |
| Debian | `20250419~deb12u2` (12) · `20250419+deb13u1` (13) |
| Alpine | `20261020-r0` |
| Python | `certifi 2026.10.19` · `pip 26.2.2` · `uv 0.13.5` · el propio Python `3.15.1` · `3.14.9` · `3.13.17` |
| Node | `22.23.4` · `24.22.1` · `26.12.1` (Node 20 sin corrección) |
| Go | `1.27.3` · `1.26.10` + recompilar (en Linux sigue la lista del sistema) |
| Java | quitar las dos raíces del `cacerts` con `keytool -delete` (el `update-ca-certificates -f` solo no las quita) o un JDK nuevo |
| Deno · Bun | rechazaron en nuestra prueba: `2.9.8` · `1.4.4` |
| Firefox / NSS | `158.0.1` · `3.131.1` |
| Electron | `44.9.1` · `43.8.1` · `42.11.16` |
| Rust | `rustls-webpki 0.103.16` · `webpki-roots 1.0.10` |
| FreeBSD | `ca_root_nss 1.131.1` (ports) · base `15.1-RELEASE-p6` · `14.5-RELEASE-p3` · `14.4-RELEASE-p12` (FreeBSD-SA-26:73) |

## PHP2Shell

`CVE-2026-109618` y `CVE-2026-109619`, ejecución remota sin login. Corregido en **PHP 8.5.12 · 8.4.27 · 8.3.36 · 8.2.35**. Verificador: [openai/php2shell-checker](https://github.com/openai/php2shell-checker). Detalles, mitigaciones temporales y señales de intrusión en la guía.

**Nuevo aviso de PHP (23/10/2026, `CVE-2026-115560`):** mantén `session.upload_progress.enabled = 0` incluso después de actualizar, hasta la próxima versión regular. Solo afecta a apps que cambian el `session.serialize_handler` a `php` en tiempo de ejecución (con `ini_set()` antes de `session_start()`); quien nunca lo cambia puede dejar la función activada.

## El proceso, de principio a fin

| # | Paso | Comando | Quién |
|---|---|---|---|
| 1 | Prueba rápida con curl en las dos cadenas | `curl https://dv-g3b-emudhra.we-have-a-problem.com/` | 🧠 tú |
| 2 | Auditoría completa de la máquina, con la lista de correcciones | `./audita.sh --comandos` | ⚙️ script |
| 3 | Auditoría de los servidores | `./audita.sh --hosts servidores.txt` | ⚙️ script |
| 4 | Copia de seguridad (base de datos, volúmenes, imagen antigua con etiqueta de respaldo, configuración) y salud ANTES | `pg_dumpall` · `docker tag <img> <img>:pre-update` · `docker inspect > x.json` · `curl -fsS …/health` | 🧠 tú |
| 5 | PHP2Shell primero (ataques en curso): probar, actualizar, reiniciar workers (servidor y contenedores) | `node phpcheck.js https://seusite` · `sudo apt install --only-upgrade $(dpkg -l 'php*' \| awk '/^ii/{print $2}')` | 🧠 tú |
| 6 | Actualizar el sistema (y el `cacerts` de Java) | `sudo apt install --only-upgrade ca-certificates` · `sudo keytool -delete -alias … -keystore /etc/ssl/certs/java/cacerts` | 🧠 tú |
| 7 | Actualizar el certifi de cada venv / conda | `<venv>/bin/python -m pip install -U certifi` · `uv pip install --python <venv>/bin/python -U certifi` | 🧠 tú |
| 8 | Cambiar Node (20 → 22/24), actualizar Deno y Bun | `nvm install 22` · `sudo apt install --only-upgrade nodejs` · `deno upgrade` · `bun upgrade` | 🧠 tú |
| 9 | Contenedores por grupo: A descargar y recrear · B capa por encima · C subir la versión / Supabase | `docker compose up -d --pull always <svc>` · `FROM <img>:pre-emudhra` · `pg_dumpall` + `npx -y supabase@latest stop && npx -y supabase@latest start` | 🧠 tú |
| 10 | Encontrar y reiniciar servicios (fuera de job/upload/live) | sección `processos a reiniciar` del script · `systemctl restart …` · `pm2 restart all` | 🧠 tú |
| 11 | Probar y validar: arrancó, responde, hace lo que hacía, datos iguales (conteos); solo se cierra ok y en línea | `docker compose ps` · `curl -fsS …/health` · `select count(*)` | 🧠 tú |
| 12 | Auditar de nuevo hasta dejar en cero (pasada completa, alcance sin nada importante afuera) | `./audita.sh` → `0 EXPOSTO · 0 SEM TESTE · 0 VERIFIQUE · 0 REINICIE` (salida 0; PHP de paquete comprobado: `--php-ok`) | ⚙️ script |
| 13 | Rutina mensual | checklist de la sección Rutina de la guía | 🧠 tú |

El historial de versiones está en [CHANGELOG.md](CHANGELOG.md).

## Fuentes

- https://emudhra.we-have-a-problem.com/
- https://bugzilla.mozilla.org/show_bug.cgi?id=2083449
- https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/
- https://socradar.io/blog/emudhra-ca-key-compromise-weak-keys-risks-and-fixes/
- https://www.php.net/archive/2026.php#2026-10-21-5
- https://www.php.net/archive/2026.php (aviso del 23/10/2026, CVE-2026-115560)
- https://github.com/openai/php2shell-checker

## Licencia

MIT. Abierto y gratuito — [INEMA.CLUB](https://inema.club).
