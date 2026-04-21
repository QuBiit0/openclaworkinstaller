# OpenClaw Workspace Installer

Scaffold de workspaces OpenClaw con plantillas optimizadas en español.
Extiende tu OpenClaw ya instalado para operar en modo **multi-agente empresa** o como **asistente personal**.

**v2.1.0** — Merge inteligente con tu `openclaw.json` existente. Cero fricción.

---

## 🎯 Flujo correcto

El instalador está pensado para correrse **después** de haber configurado OpenClaw con el wizard oficial. Así hereda todo (canal, modelo LLM, tools, skills) sin pisar nada.

```
1)  npm install -g openclaw                    ← instalás OpenClaw
2)  openclaw setup                             ← wizard oficial (canal + modelo + tools)
3)  bash install.sh                            ← nuestro script (workspaces + agents.list + A2A)
4)  openclaw gateway restart                   ← reiniciás
5)  mandale un mensaje al canal configurado    ← el orquestador te saluda
```

### Qué hace nuestro script

| Hace | No hace |
|------|---------|
| Crea workspaces (`workspace/`, `workspace-<area>/`) | Instalar OpenClaw |
| Copia plantillas optimizadas en español | Configurar canal (Telegram/WhatsApp/etc) |
| Genera apéndices de rol por área | Elegir modelo LLM |
| Agrega `agents.list` + `tools.agentToAgent` al config | Tocar tus tools/skills ya configurados |
| Auto-bindea el orquestador si detecta un único canal | Pisar tu `botToken`, auth o defaults |
| Hace backup timestamped de archivos previos | |

### Qué hereda automáticamente

Al detectar tu `~/.openclaw/openclaw.json`:
- **Modelo**: todos los agentes usan `agents.defaults.model` (el que elegiste con `openclaw setup`)
- **Canal**: si tenés uno configurado, el orquestador se auto-bindea a él
- **Tools / skills**: heredados de `agents.defaults.*` o `agents.list[].*`
- **Auth tokens**: preservados tal cual (nunca los toca)

---

## 🚀 Instalación — un solo comando

### Linux / macOS / Git Bash / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.sh | bash
```

### Windows PowerShell (wrapper que invoca install.sh via Git Bash)

```powershell
irm https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.ps1 | iex
```

> Requiere Git para Windows instalado (trae Git Bash). Si no lo tenés: https://git-scm.com/download/win

### Modo no-interactivo (ideal para scripts CI/CD)

```bash
# Bash
curl -fsSL https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.sh | \
  bash -s -- --mode empresa --empresa "OneFix" --rubro saas \
  --orchestrator-id ceo --user "Leandro" --cargo "CEO" -y
```

```powershell
# PowerShell
iwr -useb https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/install.ps1 -OutFile install.ps1
.\install.ps1 -Mode empresa -Empresa "OneFix" -Rubro saas `
  -OrchestratorId ceo -User "Leandro" -Cargo "CEO" -NonInteractive
```

### Desde clon local (desarrollo)

```bash
git clone https://github.com/QuBiit0/openclaworkinstaller.git
cd openclaworkinstaller
bash install.sh          # o: .\install.ps1
```

El wizard te hace estas preguntas:

```
? ¿Modo?                             [personal / empresa]
? Nombre de la empresa               (solo modo empresa)
? Rubro                              (sugiere áreas del catálogo)
? ID del agente principal            [default: gerencia — podés poner ceo, main, director, custom]
? Áreas del equipo                   (pre-cargadas del rubro, editables)
? Tu nombre                          (para USER.md)
? Cargo                              (solo modo empresa)
? ¿Proceder?                         [s/n]
```

---

## 📋 Ejemplos concretos

### OneFix — Consultora de software e IA

```bash
bash install.sh --mode empresa \
  --empresa "OneFix - Soluciones Informáticas" \
  --rubro saas \
  --orchestrator-id ceo \
  --areas "dev,research,ops,qa,ventas,atencion-cliente,marketing,contabilidad" \
  --user "Leandro Álvarez" --cargo "CEO / Fundador" -y
```

### Ferretería con áreas sugeridas

```bash
bash install.sh --mode empresa \
  --empresa "Ferretería El Tornillo" \
  --rubro ferreteria \
  --user "Juan Pérez" --cargo "Dueño" -y
```
(Áreas auto: `ventas, atencion-cliente, inventario, compras, administracion`)

### Asistente personal

```bash
bash install.sh --mode personal --user "Leandro" -y
```

---

## 🏢 Rubros con sugerencias automáticas

| Rubro | Áreas sugeridas |
|-------|-----------------|
| `software` | dev, qa, ops, atencion-cliente, ventas, marketing |
| `saas` | dev, qa, ops, atencion-cliente, ventas, marketing, analyst |
| `ecommerce` | ventas, atencion-cliente, inventario, logistica, marketing, contabilidad |
| `ferreteria` | ventas, atencion-cliente, inventario, compras, administracion |
| `distribuidora` | logistica, ventas, inventario, compras, administracion, contabilidad |
| `estudio-contable` | contabilidad, administracion, legal |
| `estudio-juridico` | legal, administracion, atencion-cliente |
| `restaurante` | compras, produccion, atencion-cliente, marketing, administracion |
| `fabrica` | produccion, calidad, inventario, compras, logistica, rrhh |
| `retail` | ventas, atencion-cliente, inventario, marketing, compras |
| `consultora` | ventas, administracion, contabilidad, marketing |
| `inmobiliaria` | ventas, atencion-cliente, legal, administracion, marketing |
| `salud` | atencion-cliente, administracion, rrhh, calidad, legal |
| `educacion` | administracion, atencion-cliente, marketing, rrhh |
| `agencia-marketing` | marketing, writer, ventas, atencion-cliente, analyst |
| `custom` | elegís todo vos |

---

## 📚 Catálogo completo de áreas (21)

**Administración & Finanzas:** `administracion` · `contabilidad` · `finanzas`
**Comercial:** `ventas` · `marketing` · `atencion-cliente`
**Operaciones:** `logistica` · `inventario` · `compras` · `produccion` · `calidad`
**Soporte interno:** `rrhh` · `legal` · `it`
**Software / Tech:** `dev` · `qa` · `ops` · `research` · `writer` · `analyst`
**Coordinación:** `gerencia` (default orquestador — podés renombrarlo)

**Custom**: cualquier nombre válido (ej: `tesoreria`, `capacitacion`, `innovacion`). El script genera skeleton genérico.

---

## 🎭 Agente principal: tres niveles de naming

| Nivel | Ejemplo | Quién lo elige | Cuándo |
|-------|---------|----------------|--------|
| **ID técnico** | `ceo`, `gerencia`, `main`, `director` | Vos, en el wizard | Al instalar |
| **Display name** | "CEO (Orquestador)", "Gerencia (Orquestador)" | Automático según ID | Al instalar |
| **Nombre propio** | "Atlas", "Kairo", "CEO-Bot" | El agente con vos | En la primera conversación (BOOTSTRAP.md) |

El **ID** es para routing (`openclaw agents bind --agent ceo`).
El **nombre propio** es el que usás en el chat ("Che Atlas, pedile a ventas...").

---

## 🔀 Política de canales

**Por default**: un canal → el orquestador. Todo lo demás vía A2A interno.

**Opcional**: canal propio por agente (sin fricción). Agregalo después:

```bash
# Ejemplo: bot exclusivo de Telegram para el área de ventas
openclaw channels login --channel telegram --account ventas_bot
openclaw agents bind --agent ventas --bind telegram:ventas_bot
```

---

## 🧠 Cómo funciona el merge del config

Si ya tenés `~/.openclaw/openclaw.json` (porque corriste `openclaw setup`), nuestro script:

1. **Respaldá** tu config actual a `openclaw.json.bak-YYYYMMDD-HHMMSS`
2. **Parsea** el JSON5 con comentarios
3. **Reemplaza** `agents.list` con los nuevos agentes (sin tocar `model` default)
4. **Agrega** `tools.agentToAgent` con allowlist completo
5. **Auto-agrega** binding del orquestador si detecta un único canal y no hay binding previo
6. **Bumpa** `bootstrapMaxChars` a 16000 si era menor o no estaba
7. **Preserva** `channels.*`, auth tokens, `hooks`, `userTimezone`, `skills`, cualquier otra sección

El resultado se escribe como JSON indentado (pierde los comentarios anteriores pero preserva **todos los datos**).

Si corrés el script dos veces, los backups se apilan con distinto timestamp. No se duplican bindings ni agentes.

---

## 📁 Qué se crea en disco

### Modo personal
```
~/.openclaw/
├── openclaw.json                   ← mergeado (preserva lo tuyo)
└── workspace/
    ├── .installer-backup-<ts>/     ← defaults previos (si existían)
    ├── AGENTS.md · SOUL.md · ...   ← plantillas en español
    └── memory/
```

### Modo empresa
```
~/.openclaw/
├── openclaw.json                   ← agents.list + A2A + binding auto
├── workspace/                      ← orquestador (ceo/gerencia/etc)
│   ├── AGENTS.md                   ← con §0 empresa + apéndice gerencia
│   ├── BOOTSTRAP.md                ← dirigido a orquestador
│   ├── IDENTITY.md                 ← metadata de rol
│   ├── .installer-backup-<ts>/     ← archivos previos
│   └── ... (resto)
├── workspace-dev/                  ← especialista con apéndice dev
├── workspace-ventas/
├── workspace-ops/
└── ... (uno por área)
```

---

## 🔧 Argumentos del script

```
--mode <personal|empresa>         Modo de instalación
--empresa <nombre>                Nombre de la empresa (modo empresa)
--rubro <rubro>                   Rubro — sugiere áreas
--orchestrator-id <id>            ID del agente principal (default: gerencia)
--areas <lista>                   Áreas separadas por coma
--user <nombre>                   Nombre del usuario principal
--cargo <cargo>                   Cargo del usuario
--templates-dir <ruta>            Plantillas desde directorio local
--templates-url <url>             Plantillas desde URL remota
--home <ruta>                     Override de ~/.openclaw
--non-interactive, -y             Sin prompts
--force, -f                       (compatibilidad — por default ya hace backup)
--help, -h                        Ayuda completa
```

---

## ⚙️ Tips de producción

- **Corré primero `openclaw setup`** para que el script herede canal, modelo y tools.
- **Python 3 instalado** activa el merge inteligente (Windows: viene con Git, Linux/Mac: incluido).
- **Backups timestamped** en cada workspace y en el config — podés volver atrás.
- **Revisá `~/.openclaw/openclaw.json`** después de la corrida — está JSON-ifiado (sin comentarios) pero con todo lo tuyo adentro.
- **Commit del workspace** con git: `cd ~/.openclaw/workspace && git init && git add .` — versiona tu contexto.

---

## 🧪 Verificación post-instalación

```bash
# Agentes y bindings
openclaw agents list --bindings

# Estado de canales
openclaw channels status --probe

# Smoke test del orquestador
openclaw agent --agent <orch_id> --message "Presentate y listá tu equipo"
```

---

## Versión

- Installer: **v2.1.0**
- Compatible con OpenClaw: **2026.4.15+**
- Plantillas respetan límites oficiales: `bootstrapMaxChars: 16000` por archivo (auto-setea), `bootstrapTotalMaxChars: 60000` total.
