> ## Índice de Documentación
> Consultá el índice completo en: https://docs.openclaw.ai/llms.txt
> Usalo para descubrir todas las páginas antes de explorar más a fondo.

# TOOLS.md — Notas Locales

> Los skills definen **cómo** funcionan las herramientas. Este archivo es para **lo tuyo** — lo específico de tu setup.

**Por qué separar:** los skills son compartidos. Tu setup es tuyo. Mantenerlos aparte significa que podés actualizar skills sin perder tus notas, y compartir skills sin filtrar tu infraestructura.

**Regla:** no pongas secretos acá (tokens, passwords, claves API). Para eso, `.env` o un gestor de secretos.

---

## 🎥 Cámaras

<!-- Completá con las cámaras que uses (skill: camsnap, u otras) -->

<!--
- `living-room` → sala principal, 180° gran angular, ONVIF 192.168.1.10
- `front-door` → entrada, detección de movimiento, RTSP 192.168.1.11
- `office` → escritorio, solo captura manual, 192.168.1.12
-->

---

## 🖥️ SSH

<!-- Aliases y hosts habituales -->

<!--
- `home-server` → 192.168.1.100, usuario: admin, puerto: 22
- `vps-prod` → vps.miempresa.com, usuario: deploy, puerto: 2222, SSH key: ~/.ssh/id_ed25519
- `pi` → 192.168.1.50, usuario: pi, Raspberry Pi con scripts de automatización
-->

---

## 🔊 TTS (skill: sag / ElevenLabs)

<!-- Voces y parlantes preferidos -->

<!--
- Voz preferida: "Nova" (cálida, levemente británica)
- Voz para cuentos: "Rachel"
- Voz para noticias: "Adam"
- Parlante por defecto: Kitchen HomePod
- Parlante dormitorio: Sonos Play:1 "Cuarto"
-->

---

## 🏠 Dispositivos y Casa Inteligente

<!-- Aliases de dispositivos -->

<!--
### Philips Hue (skill: OpenHue)
- `sala` → grupo: Sala (4 bombitas)
- `escritorio` → grupo: Escritorio (Hue Play + lamp)
- Escena preferida nocturna: "Dimmed"

### Sonos (skill: sonos-cli)
- `cocina` → Sonos One en la isla
- `sala` → Sonos Beam + sub
- Grupo default "casa": cocina + sala + dormitorio

### BluOS (skill: blucli)
- `Node` → Bluesound Node principal del living
-->

---

## 📱 Cuentas y Canales

<!-- Aliases de cuentas / canales que uses habitualmente. SIN TOKENS. -->

<!--
### WhatsApp
- Cuenta personal vinculada — QR renovado el [fecha]
- Contactos VIP: Juan, Mariana, Mamá (ver USER.md para IDs si aplica)

### Discord
- Server principal: "Mi server" (ID: 123456789)
- Canal de logs: #agente-logs
- Usar `user:<id>` y `channel:<id>` para targets — IDs numéricos solos son ambiguos.

### Telegram
- Bot configurado vía @BotFather — nombre: @mi_bot
- Chat principal ID: -100xxxxxxxxxx

### Slack
- Workspace: miempresa.slack.com
- Canal default para notificaciones: #personal-assistant
-->

---

## 🛠️ Scripts Personales

<!-- Rutas a scripts custom que usás frecuentemente -->

<!--
- `~/scripts/deploy.sh` → deploy del proyecto principal
- `~/scripts/morning-brief.sh` → genera resumen matutino
- `~/bin/notas` → CLI personal para notas rápidas
-->

---

## 🌐 Navegador (skill: openclaw browser)

<!-- Perfiles y preferencias de browser -->

<!--
- Perfil default: OpenClaw-managed Chrome
- Para scraping autenticado: perfil "work" (con cookies de sesión)
- Resolución por defecto para screenshots: 1440x900
- User agent personalizado: [ninguno / custom]
-->

---

## ⚙️ Preferencias de Ejecución

<!-- Cómo preferís que se comporten ciertas operaciones -->

<!--
- Confirmar antes de `git push` a main: SÍ siempre
- Confirmar antes de `rm -rf`: SÍ siempre
- Usar `trash` en lugar de `rm`: SÍ por defecto
- Backup antes de migraciones DB: SÍ siempre
- Verificar diff antes de commits automáticos: SÍ
-->

---

## 🔗 Shortcuts y Aliases

<!-- Combinaciones de teclas, aliases del shell, snippets que usás -->

<!--
- `g` → git status + git log --oneline -5
- `dc` → docker compose
- `k` → kubectl
- `tf` → terraform
-->

---

## 📚 Referencias Rápidas

<!-- Documentación o enlaces que consultás seguido -->

<!--
- API del proyecto: https://api.miempresa.com/docs
- Wiki interna: https://wiki.miempresa.com
- Dashboard de monitoring: https://grafana.internal/d/main
- Status page: https://status.miempresa.com
-->

---

## Notas

Agregá lo que te ayude a hacer tu laburo. **Esta es tu cheat sheet personal.**

- ❌ No guardes secretos acá (tokens, claves, passwords).
- ✅ Sí guardá aliases, nombres descriptivos, rutas, preferencias.
- ✅ Actualizalo cuando agregues un dispositivo, skill o servicio nuevo.
