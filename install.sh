#!/usr/bin/env bash
#
# OpenClaw Workspace Installer — Modo empresarial o personal
# ---------------------------------------------------------------
# Flujo esperado:
#   1. npm install -g openclaw
#   2. openclaw setup           ← configura canal, modelo LLM, tools, skills
#   3. bash install.sh          ← este script: crea workspaces + agents.list + A2A
#   4. openclaw gateway restart
#
# Este script:
#   - HEREDA modelo, tools y skills del openclaw.json ya configurado
#   - MERGEA con la config existente (preserva channels, auth, defaults)
#   - AUTO-BINDEA el orquestador si detecta un único canal configurado
#   - Hace BACKUP timestamped de archivos previos antes de pisar
#
# Uso:
#   curl -fsSL https://<tu-repo>/install.sh | bash
#   bash install.sh
#   bash install.sh --mode empresa --rubro ferreteria --user "Leandro"
#
# Compatible: Git Bash (Windows), WSL, macOS, Linux.
# ---------------------------------------------------------------

set -euo pipefail

# =====================================================================
# CONFIG
# =====================================================================

VERSION="2.3.0"
# Cuando el script se baja con curl | bash, BASH_SOURCE puede no existir (se lee de stdin)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
TEMPLATES_DIR=""
# URL default al raw de GitHub — usada cuando se ejecuta vía `curl | bash`
TEMPLATES_URL="${TEMPLATES_URL:-https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/templates}"

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"

# Feature flags — poblados por detect_openclaw_features() en check_requirements
# Inicializados en 0 para que should_use_legacy_merger() sea seguro de llamar antes
HAS_OPENCLAW_META="0"
HAS_SET_IDENTITY_NAME=0   # openclaw agents set-identity soporta uno de los flags de display name
HAS_CONFIG_PATCH=0        # openclaw config soporta subcomando 'patch'
SET_IDENTITY_NAME_FLAG="" # flag real detectado: --name | --display-name | --label | ""

# CLI args
ARG_MODE=""
ARG_EMPRESA=""
ARG_RUBRO=""
ARG_AREAS=""
ARG_USER=""
ARG_CARGO=""
ARG_ORCH_ID=""
ARG_ORCH_ID_SET="false"   # true si --orchestrator-id fue pasado explícitamente (incluso vacío)
ARG_NON_INTERACTIVE="false"
ARG_FORCE="false"

# Catálogo de roles disponibles (mapping id → descripción corta)
declare -A ROLE_DESC=(
  [rrhh]="Recursos Humanos — reclutamiento, nómina, políticas internas"
  [administracion]="Administración general — trámites, agenda, correspondencia"
  [ventas]="Ventas y comercial — prospección, cierre, CRM"
  [marketing]="Marketing — contenido, redes, campañas, branding"
  [legal]="Legal — contratos, compliance, propiedad intelectual"
  [contabilidad]="Contabilidad — facturación, impuestos, balances"
  [finanzas]="Finanzas — cashflow, presupuesto, proyecciones"
  [it]="IT / Sistemas — soporte técnico interno, infra, usuarios"
  [logistica]="Logística — envíos, transporte, ruteo"
  [inventario]="Inventario / Stock — existencias, reposición, depósito"
  [atencion-cliente]="Atención al Cliente — soporte, reclamos, post-venta"
  [compras]="Compras / Procurement — proveedores, cotizaciones, OCs"
  [produccion]="Producción / Operaciones — planificación, fábrica, taller"
  [calidad]="Calidad (QA/QC física) — estándares, no conformidades"
  [dev]="Desarrollo de software — senior engineer"
  [qa]="QA de software — testing, regresión, validación"
  [ops]="DevOps / SRE — monitoreo, despliegue, observabilidad"
  [research]="Investigación — análisis profundo, síntesis con fuentes"
  [writer]="Content / Redacción — copy, blog, docs, posts"
  [analyst]="Data / Analista — métricas, reportes, BI"
)

# Sugerencias por rubro (rubro → lista de áreas recomendadas)
declare -A RUBRO_SUGGEST=(
  [software]="dev,qa,ops,atencion-cliente,ventas,marketing"
  [saas]="dev,qa,ops,atencion-cliente,ventas,marketing,analyst"
  [ecommerce]="ventas,atencion-cliente,inventario,logistica,marketing,contabilidad"
  [ferreteria]="ventas,atencion-cliente,inventario,compras,administracion"
  [distribuidora]="logistica,ventas,inventario,compras,administracion,contabilidad"
  [estudio-contable]="contabilidad,administracion,legal"
  [estudio-juridico]="legal,administracion,atencion-cliente"
  [restaurante]="compras,produccion,atencion-cliente,marketing,administracion"
  [fabrica]="produccion,calidad,inventario,compras,logistica,rrhh"
  [retail]="ventas,atencion-cliente,inventario,marketing,compras"
  [consultora]="ventas,administracion,contabilidad,marketing"
  [inmobiliaria]="ventas,atencion-cliente,legal,administracion,marketing"
  [salud]="atencion-cliente,administracion,rrhh,calidad,legal"
  [educacion]="administracion,atencion-cliente,marketing,rrhh"
  [logistica-empresa]="logistica,ventas,administracion,contabilidad,atencion-cliente"
  [agencia-marketing]="marketing,writer,ventas,atencion-cliente,analyst"
  [custom]=""
)

# =====================================================================
# UI
# =====================================================================

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m';  C_BOLD=$'\033[1m';  C_DIM=$'\033[2m'
  C_RED=$'\033[31m';   C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m';  C_CYAN=$'\033[36m';  C_GREY=$'\033[90m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_GREY=""
fi

log()   { printf '%s[·]%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
info()  { printf '%s[i]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()    { printf '%s[✓]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s[✗]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
step()  { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }

banner() {
  cat <<'BANNER'

   ____                       ________
  / __ \____  ___  ____  / ____/ /___ __      __
 / / / / __ \/ _ \/ __ \/ /   / / __ `/ | /| / /
/ /_/ / /_/ /  __/ / / / /___/ / /_/ /| |/ |/ /
\____/ .___/\___/_/ /_/\____/_/\__,_/ |__/|__/
    /_/          Workspace Installer (empresas / personal)

BANNER
  printf '   %sv%s%s — A2A habilitado, adaptable a cualquier rubro\n\n' "$C_DIM" "$VERSION" "$C_RESET"
}

# =====================================================================
# ARGS
# =====================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)               ARG_MODE="$2"; shift 2 ;;
    --empresa)            ARG_EMPRESA="$2"; shift 2 ;;
    --rubro)              ARG_RUBRO="$2"; shift 2 ;;
    --areas)              ARG_AREAS="$2"; shift 2 ;;
    --user)               ARG_USER="$2"; shift 2 ;;
    --cargo)              ARG_CARGO="$2"; shift 2 ;;
    --orchestrator-id)
      [[ $# -ge 2 ]] || die "--orchestrator-id requiere un valor (puede estar vacío con: --orchestrator-id \"\")"
      ARG_ORCH_ID="$2"; ARG_ORCH_ID_SET="true"; shift 2
      ;;
    --templates-dir)      TEMPLATES_DIR="$2"; shift 2 ;;
    --templates-url)      TEMPLATES_URL="$2"; shift 2 ;;
    --home)               OPENCLAW_HOME="$2"; CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"; shift 2 ;;
    --non-interactive|-y) ARG_NON_INTERACTIVE="true"; shift ;;
    --force|-f)           ARG_FORCE="true"; shift ;;
    --help|-h)
      cat <<EOF
OpenClaw Workspace Installer v$VERSION

Uso:
  $0 [opciones]

Modos:
  personal    un solo agente (tu asistente)
  empresa     orquestador (gerencia) + áreas que elijas

Opciones:
  --mode <personal|empresa>   Modo de instalación
  --empresa <nombre>          Nombre de la empresa (solo modo empresa)
  --rubro <rubro>             Rubro — sugiere áreas adecuadas. Ej:
                              software, saas, ecommerce, ferreteria,
                              distribuidora, estudio-contable, restaurante,
                              fabrica, retail, consultora, inmobiliaria,
                              salud, educacion, custom
  --areas <lista>             Áreas separadas por coma. Si no se especifica,
                              se toman las sugeridas por rubro.
  --user <nombre>             Nombre del usuario humano principal
  --cargo <cargo>             Cargo del usuario (ej: "Dueño", "Gerente General")
  --orchestrator-id <id>      ID del agente principal (default: gerencia).
                              Ejemplos: gerencia, main, ceo, director, orquestador
                              Debe ser lowercase, letras/números/guiones.
  --templates-dir <ruta>      Directorio local con las plantillas
  --templates-url <url>       URL base para descargar plantillas remotas
  --home <ruta>               Override de \$HOME/.openclaw
  --non-interactive, -y       Modo no-interactivo (requiere args suficientes)
  --force, -f                 Sobrescribir workspaces existentes
  --help, -h                  Esta ayuda

Áreas disponibles:
EOF
      for id in "${!ROLE_DESC[@]}"; do
        printf "  %-20s %s\n" "$id" "${ROLE_DESC[$id]}"
      done | sort
      cat <<EOF

Ejemplos:
  # Wizard interactivo completo
  bash $0

  # Asistente personal, no-interactivo
  bash $0 --mode personal --user "Leandro" -y

  # Ferretería con áreas sugeridas del rubro
  bash $0 --mode empresa --empresa "Ferretería El Tornillo" \\
          --rubro ferreteria --user "Leandro" --cargo "Dueño" -y

  # Empresa custom con áreas específicas
  bash $0 --mode empresa --empresa "Mi PyME" --rubro custom \\
          --areas ventas,contabilidad,atencion-cliente \\
          --user "Leandro" --cargo "Gerente" -y
EOF
      exit 0
      ;;
    *)
      warn "Argumento desconocido: $1"
      shift
      ;;
  esac
done

# BF-5 (C1 fix): validar --orchestrator-id explícitamente vacío en modo --non-interactive.
# Lo hacemos acá (post-arg-parser) y NO dentro del wizard porque el spec aplica
# independientemente del modo (personal o empresa). En modo interactivo el wizard
# re-pregunta, así que solo enforced en --non-interactive.
if [[ "$ARG_ORCH_ID_SET" == "true" && -z "$ARG_ORCH_ID" && "$ARG_NON_INTERACTIVE" == "true" ]]; then
  die "Error: --orchestrator-id no puede estar vacío en modo --non-interactive. Usá: --orchestrator-id <id> (ej: gerencia, ceo, director)"
fi

# =====================================================================
# CHECKS
# =====================================================================

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando requerido no encontrado: $1"
}

# Comprueba si el output de `openclaw <subcmd> --help` contiene un flag dado.
# Uso: cli_has_flag "agents set-identity" "--name"
# Retorna 0 si está presente, 1 si no.
cli_has_flag() {
  local subcmd="$1" flag="$2"
  has_openclaw_cli || return 1
  # shellcheck disable=SC2086
  openclaw $subcmd --help 2>/dev/null | grep -qE "(^|[[:space:]])${flag}([[:space:]]|=|$)"
}

# Compara la versión del CLI instalado contra una versión mínima en formato YYYY.M.D.
# Uso: cli_version_gte 2026.4.23
# Retorna 0 si la versión instalada es >= la pedida, 1 si no o si no se puede determinar.
cli_version_gte() {
  local required="$1"
  has_openclaw_cli || return 1
  local actual
  actual="$(openclaw --version 2>/dev/null | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+' | head -1 || true)"
  [[ -z "$actual" ]] && return 1

  # Convertir YYYY.M.D → entero comparable: YYYYMMDD (con zero-padding de mes y día)
  _ver_to_int() {
    local v="$1"
    local y m d
    IFS='.' read -r y m d <<< "$v"
    printf '%d%02d%02d' "${y:-0}" "${m:-0}" "${d:-0}"
  }

  local v_actual v_required
  v_actual="$(_ver_to_int "$actual")"
  v_required="$(_ver_to_int "$required")"
  [[ "$v_actual" -ge "$v_required" ]]
}

# Devuelve 0 (verdadero) si IDENTITY.md existe y está suficientemente relleno.
# Heurística (clarifications #338): cuenta placeholders del template real:
#   `[...]`  `[YYYY-MM-DD]`  `[v1.0]`  `[ej: ...]`
# Un IDENTITY.md vacío / recién copiado tiene ≥8 placeholders.
# Una vez que el usuario completa los campos básicos (nombre, criatura, vibra),
# el conteo baja de 5 — consideramos el archivo "relleno" con <5 placeholders.
is_identity_filled() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local unfilled
  unfilled="$(grep -cE '\`\[(\.\.\.|YYYY-MM-DD|v[0-9]\.[0-9]|ej:)' "$file" 2>/dev/null || true)"
  [[ "${unfilled:-0}" -lt 5 ]]
}

# Valida y normaliza el ID del orquestador.
# - Convierte a lowercase y elimina espacios.
# - En modo fatal (default): llama die() con mensaje claro (para --non-interactive).
# - En modo silencioso (pasar cualquier segundo arg): escribe error a stderr y retorna 1
#   (para uso en loops interactivos donde die() abortaría el proceso entero).
# Uso no-interactivo:  orch_id="$(sanitize_orchestrator_id "$ARG_ORCH_ID")"
# Uso interactivo:     if orch_id="$(sanitize_orchestrator_id "$raw" quiet 2>/dev/null)"; then
sanitize_orchestrator_id() {
  local raw="$1" quiet="${2:-}" sanitized msg=""
  sanitized="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  if [[ -z "$sanitized" ]]; then
    msg="orchestrator-id vacío. Usá --orchestrator-id <id> (ej: gerencia, ceo, director)."
  elif [[ "$sanitized" == "main" ]]; then
    msg="ID 'main' está reservado por OpenClaw. Elegí otro (ej: gerencia, ceo, director)."
  elif ! [[ "$sanitized" =~ ^[a-z][a-z0-9_-]{1,31}$ ]]; then
    msg="orchestrator-id inválido: '$raw'. Solo lowercase, letras/números/guiones/subguiones, debe empezar con letra, máx 32 chars."
  fi

  if [[ -n "$msg" ]]; then
    if [[ -n "$quiet" ]]; then
      # Modo interactivo: error a stderr y retornar 1 (no die)
      echo "$msg" >&2
      return 1
    else
      # Modo no-interactivo / fatal: die aborta con exit 1
      die "$msg"
    fi
  fi

  echo "$sanitized"
}

check_requirements() {
  step "Verificando requisitos"
  require_cmd bash
  require_cmd mkdir
  require_cmd cat
  require_cmd sed

  if command -v openclaw >/dev/null 2>&1; then
    local v
    v="$(openclaw --version 2>/dev/null || echo 'desconocida')"
    ok "openclaw CLI detectado (versión $v)"
  else
    warn "openclaw CLI no está en PATH."
    info "Recomendado: npm install -g openclaw && openclaw setup"
    info "El script deja todo listo — instalalo después y corré 'openclaw gateway restart'."
  fi

  # Detectar capacidades del CLI una sola vez — los flags se usan en todo el script
  detect_openclaw_features
}

# Detecta qué features opcionales tiene la versión instalada del CLI.
# Exporta: HAS_SET_IDENTITY_NAME, HAS_CONFIG_PATCH,
#          SET_IDENTITY_NAME_FLAG (el nombre exacto del flag para set-identity).
# Se llama UNA VEZ desde check_requirements; seguro de llamar aunque CLI no esté.
detect_openclaw_features() {
  has_openclaw_cli || return 0

  # --- set-identity display-name flag (D1 / clarifications #338) ---
  # Probar en orden de probabilidad: --name, --display-name, --label.
  # Usar el primero que aparezca en la ayuda del subcomando.
  local si_help
  si_help="$(openclaw agents set-identity --help 2>/dev/null || true)"
  for flag_candidate in --name --display-name --label; do
    if echo "$si_help" | grep -qE "(^|[[:space:]])${flag_candidate}([[:space:]]|=|$)"; then
      SET_IDENTITY_NAME_FLAG="$flag_candidate"
      HAS_SET_IDENTITY_NAME=1
      break
    fi
  done

  # --- config patch subcomando (D3 / D6) ---
  if openclaw config --help 2>/dev/null | grep -qE "(^|[[:space:]])patch([[:space:]]|$)"; then
    HAS_CONFIG_PATCH=1
  fi

  # NOTA: subagents policy (D6) NO tiene un --help probe específico; el gate vive
  # directamente en write_subagents_policy_empresa() vía cli_version_gte 2026.4.23
  # + HAS_CONFIG_PATCH. No persistimos un HAS_SUBAGENTS_POLICY redundante.

  # Loguear resultados para troubleshooting
  info "Feature flags CLI: set-identity=${SET_IDENTITY_NAME_FLAG:-none}, config-patch=$HAS_CONFIG_PATCH"
}

# =====================================================================
# PYTHON DETECTION (para merge inteligente del config)
# =====================================================================

PYTHON=""
MERGE_SCRIPT=""

find_python() {
  # Buscar un Python real (no el stub de Windows Store)
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then
      if "$cand" -c "import json, re, sys; sys.exit(0)" 2>/dev/null; then
        echo "$cand"; return 0
      fi
    fi
  done
  # Windows: rutas comunes de Python oficial
  for cand in \
      "/c/Program Files/Python313/python.exe" \
      "/c/Program Files/Python312/python.exe" \
      "/c/Program Files/Python311/python.exe" \
      "/c/Program Files/Python310/python.exe"; do
    if [[ -x "$cand" ]]; then
      echo "$cand"; return 0
    fi
  done
  return 1
}

setup_python_merger() {
  PYTHON="$(find_python 2>/dev/null || true)"
  if [[ -z "$PYTHON" ]]; then
    warn "Python 3 no detectado — fallback: config mínimo sin merge"
    return 1
  fi
  ok "Python detectado: $PYTHON"

  MERGE_SCRIPT="$(mktemp --suffix=.py 2>/dev/null || mktemp)"
  cat > "$MERGE_SCRIPT" <<'PYEOF'
"""
OpenClaw config merger.
- Lee config existente (JSON5 con comentarios) preservando TODO.
- Reemplaza agents.list con los nuevos.
- Agrega/actualiza tools.agentToAgent.
- Bumpea bootstrapMaxChars a 16000 si es menor/ausente.
- Auto-bindea el orquestador si hay un solo canal configurado y no hay binding previo.
- Escribe JSON (pierde comentarios, preserva datos).
"""
import json, re, os, sys

CFG = os.environ['CONFIG_PATH']
NEW = os.environ['NEW_AGENTS_PATH']

def strip_json5(s: str) -> str:
    # Sacar comentarios de línea y bloque
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.DOTALL)
    # Quoted keys (JSON5 permite unquoted)
    s = re.sub(r'(?<=[{,\s])([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r'"\1":', s)
    # Trailing commas
    s = re.sub(r',(\s*[}\]])', r'\1', s)
    return s

def load_existing():
    if not os.path.exists(CFG):
        return {}
    with open(CFG, 'r', encoding='utf-8') as f:
        raw = f.read()
    try:
        return json.loads(strip_json5(raw))
    except Exception as e:
        print(f"ERROR: no pude parsear {CFG}: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    with open(NEW, 'r', encoding='utf-8') as f:
        new = json.load(f)

    cfg = load_existing()

    # agents.list ← reemplazar
    cfg.setdefault('agents', {})
    cfg['agents']['list'] = new['agents_list']

    # agents.defaults: bumpear bootstrapMaxChars y warning si no estaban o eran menores
    cfg['agents'].setdefault('defaults', {})
    defaults = cfg['agents']['defaults']
    cur_max = defaults.get('bootstrapMaxChars', 0) or 0
    if cur_max < 16000:
        defaults['bootstrapMaxChars'] = 16000
    defaults.setdefault('bootstrapPromptTruncationWarning', 'once')

    # tools.agentToAgent ← habilitado con allowlist
    cfg.setdefault('tools', {})
    cfg['tools']['agentToAgent'] = {
        'enabled': True,
        'allow': new['a2a_allow'],
    }

    # agents.defaults.subagents + tools.subagents policy (BF-6 / SP-1 / SP-2)
    # Solo en modo empresa (WIZARD_MODE=empresa pasado por el caller)
    if os.environ.get('WIZARD_MODE') == 'empresa':
        subagents_defaults = defaults.setdefault('subagents', {})
        subagents_defaults['maxSpawnDepth'] = 2
        subagents_defaults['maxChildrenPerAgent'] = 5
        cfg['tools'].setdefault('subagents', {}).setdefault('tools', {})['deny'] = ['gateway', 'cron']

    # Auto-bindear orquestador si hay UN solo canal configurado
    orch_id = new['orchestrator_id']
    channels = list((cfg.get('channels') or {}).keys())
    bindings = cfg.get('bindings', []) or []
    orch_already_bound = any(
        (b.get('agentId') == orch_id) and (b.get('match') or {}).get('channel')
        for b in bindings
    )
    if len(channels) == 1 and not orch_already_bound and orch_id:
        bindings.append({
            'agentId': orch_id,
            'match': {'channel': channels[0]},
        })
        print(f"AUTO_BIND={orch_id}:{channels[0]}")
    cfg['bindings'] = bindings

    # Imprimir datos detectados para que el bash los muestre en el resumen
    detected_model = (defaults.get('model') or '') or (cfg.get('agent') or {}).get('model', '')
    print(f"DETECTED_MODEL={detected_model}")
    print(f"DETECTED_CHANNELS={','.join(channels)}")
    print(f"BOOTSTRAP_MAX={defaults.get('bootstrapMaxChars')}")

    # Escribir JSON con indentación legible
    with open(CFG, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    print("MERGE=OK")

if __name__ == '__main__':
    main()
PYEOF

  # Verificar que el script es válido (compile-only, sin ejecutar)
  if ! "$PYTHON" -m py_compile "$MERGE_SCRIPT" 2>/dev/null; then
    warn "Merge script tiene error de sintaxis — fallback a modo sin merge"
    PYTHON=""
    MERGE_SCRIPT=""
    return 1
  fi
  return 0
}

# Solo lee y reporta (no modifica)
detect_openclaw_config() {
  DETECTED_MODEL=""
  DETECTED_CHANNELS=""

  if [[ ! -f "$CONFIG_FILE" ]]; then
    info "No hay \`openclaw.json\` previo en $CONFIG_FILE"
    info "Recomendado: corré primero \`openclaw setup\` para configurar canal + modelo."
    return
  fi
  if [[ -z "$PYTHON" ]]; then
    warn "Sin Python no puedo leer el config previo."
    return
  fi

  # Convertir path a Windows nativo para que Python lo pueda leer
  local config_path_native
  config_path_native="$(to_windows_path "$CONFIG_FILE" 2>/dev/null || echo "$CONFIG_FILE")"

  local tmp_out
  tmp_out="$(mktemp)"
  "$PYTHON" - "$config_path_native" > "$tmp_out" 2>/dev/null <<'PYEOF' || true
import json, re, os, sys
p = sys.argv[1]
if not os.path.exists(p):
    sys.exit(0)
with open(p, 'r', encoding='utf-8') as f: s = f.read()
s = re.sub(r'//[^\n]*', '', s)
s = re.sub(r'/\*.*?\*/', '', s, flags=re.DOTALL)
s = re.sub(r'(?<=[{,\s])([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r'"\1":', s)
s = re.sub(r',(\s*[}\]])', r'\1', s)
try:
    d = json.loads(s)
except Exception:
    sys.exit(0)
defaults = (d.get('agents') or {}).get('defaults', {}) or {}
model_obj = defaults.get('model') or (d.get('agent') or {}).get('model') or ''
# model puede ser string o dict {"primary": "..."}
if isinstance(model_obj, dict):
    model = model_obj.get('primary', '') or model_obj.get('default', '') or ''
else:
    model = model_obj
channels = list((d.get('channels') or {}).keys())
# Detectar si tiene meta (firma de integridad) — AVISAR al user
has_meta = 'meta' in d
has_gateway = 'gateway' in d
print(f"MODEL={model}")
print(f"CHANNELS={','.join(channels)}")
print(f"HAS_META={'1' if has_meta else '0'}")
print(f"HAS_GATEWAY={'1' if has_gateway else '0'}")
PYEOF
  DETECTED_MODEL="$(grep '^MODEL=' "$tmp_out" 2>/dev/null | cut -d= -f2- 2>/dev/null || true)"
  DETECTED_CHANNELS="$(grep '^CHANNELS=' "$tmp_out" 2>/dev/null | cut -d= -f2- 2>/dev/null || true)"
  local has_meta
  has_meta="$(grep '^HAS_META=' "$tmp_out" 2>/dev/null | cut -d= -f2- 2>/dev/null || echo 0)"
  DETECTED_MODEL="${DETECTED_MODEL:-}"
  DETECTED_CHANNELS="${DETECTED_CHANNELS:-}"
  rm -f "$tmp_out"

  # Si el config tiene meta (firma integridad de openclaw setup/onboard),
  # preferimos usar openclaw CLI que respeta esa firma
  if [[ "$has_meta" == "1" ]]; then
    HAS_OPENCLAW_META="1"
  else
    HAS_OPENCLAW_META="0"
  fi

  if [[ -n "$DETECTED_MODEL" ]] || [[ -n "$DETECTED_CHANNELS" ]]; then
    info "Detectado en \`openclaw.json\`:"
    if [[ -n "$DETECTED_MODEL" ]]; then
      echo "   Modelo default:       ${C_BOLD}$DETECTED_MODEL${C_RESET}"
    else
      warn "No se encontró modelo default — heredarán de defaults internos de OpenClaw"
    fi
    if [[ -n "$DETECTED_CHANNELS" ]]; then
      echo "   Canales configurados: ${C_BOLD}$DETECTED_CHANNELS${C_RESET}"
    else
      warn "No hay canales configurados — agregalos con: openclaw channels login --channel <name>"
    fi
  fi
}

detect_templates() {
  step "Localizando plantillas"

  # Prioridad 1: directorio explícito por CLI
  if [[ -n "$TEMPLATES_DIR" ]] && [[ -d "$TEMPLATES_DIR" ]]; then
    ok "Usando plantillas de: $TEMPLATES_DIR"
    return
  fi

  # Prioridad 2: templates/ adyacente al script (modo desarrollo)
  if [[ -n "$SCRIPT_DIR" ]] && [[ -d "$SCRIPT_DIR/templates" ]]; then
    TEMPLATES_DIR="$SCRIPT_DIR/templates"
    ok "Usando plantillas locales: $TEMPLATES_DIR"
    return
  fi

  # Prioridad 3: descargar desde URL (modo `curl | bash`)
  require_cmd curl
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/roles"
  info "Descargando plantillas desde $TEMPLATES_URL"
  for f in AGENTS.md BOOT.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md; do
    curl -fsSL "$TEMPLATES_URL/$f" -o "$tmp/$f" || die "No pude descargar $f desde $TEMPLATES_URL"
  done
  # Roles: todos los del catálogo ROLE_DESC (best-effort)
  for r in "${!ROLE_DESC[@]}"; do
    curl -fsSL "$TEMPLATES_URL/roles/$r.md" -o "$tmp/roles/$r.md" 2>/dev/null || true
  done
  TEMPLATES_DIR="$tmp"
  ok "Plantillas descargadas en $TEMPLATES_DIR"
}

# =====================================================================
# WIZARD
# =====================================================================

ask() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    prompt="$prompt [$C_DIM$default$C_RESET]"
  fi
  read -r -p "$(printf '%s?%s %s: ' "$C_CYAN" "$C_RESET" "$prompt")" answer
  echo "${answer:-$default}"
}

ask_choice() {
  local prompt="$1" opts="$2" default="${3:-}" answer
  local display
  display="$(echo "$opts" | tr '|' '/')"
  while true; do
    read -r -p "$(printf '%s?%s %s [%s]: ' "$C_CYAN" "$C_RESET" "$prompt" "$display")" answer
    answer="${answer:-$default}"
    if echo "|$opts|" | grep -q "|$answer|"; then
      echo "$answer"
      return
    fi
    warn "Opción inválida. Elegí entre: $display"
  done
}

show_role_catalog() {
  info "Áreas disponibles:"
  for id in rrhh administracion ventas marketing legal contabilidad finanzas it logistica inventario atencion-cliente compras produccion calidad dev qa ops research writer analyst; do
    printf "   ${C_BOLD}%-20s${C_RESET} %s\n" "$id" "${ROLE_DESC[$id]}"
  done
  echo
  info "También podés escribir nombres custom (ej: 'tesoreria', 'capacitacion') — se usa plantilla genérica."
}

show_rubros() {
  info "Rubros con áreas sugeridas:"
  for r in software saas ecommerce ferreteria distribuidora estudio-contable estudio-juridico restaurante fabrica retail consultora inmobiliaria salud educacion logistica-empresa agencia-marketing; do
    printf "   ${C_BOLD}%-22s${C_RESET} → %s\n" "$r" "${RUBRO_SUGGEST[$r]}"
  done
  echo
  info "Si ninguno encaja, escribí ${C_BOLD}custom${C_RESET} y elegís las áreas a mano."
}

run_wizard() {
  local mode empresa rubro areas user cargo

  # Modo
  if [[ -n "$ARG_MODE" ]]; then
    mode="$ARG_MODE"
  elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
    mode="personal"
  else
    step "Configuración"
    echo
    info "¿Qué tipo de instalación querés?"
    echo "   ${C_BOLD}1) personal${C_RESET}  — un solo agente, tu asistente diario"
    echo "   ${C_BOLD}2) empresa${C_RESET}   — orquestador + áreas de la empresa (con A2A)"
    echo
    local choice
    choice=$(ask_choice "Elegí" "1|2|personal|empresa" "2")
    case "$choice" in
      1|personal) mode="personal" ;;
      2|empresa)  mode="empresa"  ;;
    esac
  fi

  if [[ "$mode" == "empresa" ]]; then
    # Nombre empresa
    if [[ -n "$ARG_EMPRESA" ]]; then
      empresa="$ARG_EMPRESA"
    elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
      empresa="Mi Empresa"
    else
      empresa=$(ask "Nombre de la empresa" "Mi Empresa")
    fi

    # ID del agente principal (orquestador). BF-5 C1 (--orchestrator-id "" en --non-interactive)
    # ya fue validado a nivel module después del arg parser.
    if [[ -n "$ARG_ORCH_ID" ]]; then
      # --orchestrator-id provisto: sanitize_orchestrator_id hace die() si es inválido
      orch_id="$(sanitize_orchestrator_id "$ARG_ORCH_ID")"
    elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
      # Sin flag y no-interactivo: default seguro "gerencia" (ya pasa validación)
      orch_id="$(sanitize_orchestrator_id "gerencia")"
    else
      echo
      info "ID del agente principal (el que coordina al equipo y habla con vos)."
      info "Sugerencias comunes: ${C_BOLD}gerencia${C_RESET} / ${C_BOLD}ceo${C_RESET} / ${C_BOLD}director${C_RESET} / ${C_BOLD}orquestador${C_RESET}"
      info "Debe ser lowercase, letras/números/guiones/subguiones. Nombre/personalidad se define en BOOTSTRAP."
      while true; do
        orch_id=$(ask "ID del agente principal" "gerencia")
        # Modo silencioso (segundo arg): retorna 1 en lugar de die(), así el loop puede continuar
        if orch_id="$(sanitize_orchestrator_id "$orch_id" quiet 2>/dev/null)"; then
          break
        fi
        warn "ID inválido. Solo lowercase, letras/números/guiones/subguiones, debe empezar con letra, máx 32 chars, no puede ser 'main'."
      done
    fi

    # Rubro
    if [[ -n "$ARG_RUBRO" ]]; then
      rubro="$ARG_RUBRO"
    elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
      rubro="custom"
    else
      echo
      show_rubros
      rubro=$(ask "Rubro de la empresa (dejá vacío para custom)" "custom")
      rubro="${rubro,,}"  # lowercase
    fi

    # Áreas
    if [[ -n "$ARG_AREAS" ]]; then
      areas="$ARG_AREAS"
    elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
      areas="${RUBRO_SUGGEST[$rubro]:-ventas,administracion,atencion-cliente}"
    else
      echo
      local suggested="${RUBRO_SUGGEST[$rubro]:-}"
      if [[ -n "$suggested" ]]; then
        info "Áreas sugeridas para ${C_BOLD}$rubro${C_RESET}: $suggested"
        echo
      fi
      show_role_catalog
      echo
      info "Escribí las áreas separadas por coma. Ej: ventas,contabilidad,rrhh"
      info "Dejá vacío para usar las sugeridas del rubro."
      areas=$(ask "Áreas (el orquestador 'gerencia' se crea siempre)" "$suggested")
      [[ -z "$areas" ]] && areas="$suggested"
    fi
  fi

  # Usuario
  if [[ -n "$ARG_USER" ]]; then
    user="$ARG_USER"
  elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
    user="Responsable"
  else
    user=$(ask "Nombre del responsable principal" "Responsable")
  fi

  # Cargo (solo en modo empresa)
  if [[ "$mode" == "empresa" ]]; then
    if [[ -n "$ARG_CARGO" ]]; then
      cargo="$ARG_CARGO"
    elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
      cargo="Dueño/Gerente"
    else
      cargo=$(ask "Cargo en la empresa" "Dueño/Gerente")
    fi
  else
    cargo=""
    empresa=""
    rubro=""
    areas=""
    orch_id=""
  fi

  # Confirmación
  if [[ "$ARG_NON_INTERACTIVE" != "true" ]]; then
    echo
    info "Resumen:"
    echo "   Modo:         ${C_BOLD}$mode${C_RESET}"
    if [[ "$mode" == "empresa" ]]; then
      echo "   Empresa:      ${C_BOLD}$empresa${C_RESET} (rubro: $rubro)"
      echo "   Orquestador:  ${C_BOLD}$orch_id${C_RESET}"
      echo "   Especialistas: ${C_BOLD}$areas${C_RESET}"
    fi
    echo "   Usuario:      ${C_BOLD}$user${C_RESET}${cargo:+ — $cargo}"
    echo "   Home:         ${C_BOLD}$OPENCLAW_HOME${C_RESET}"
    if [[ -n "${DETECTED_MODEL:-}" ]]; then
      echo "   Modelo (de openclaw.json): ${C_BOLD}$DETECTED_MODEL${C_RESET}"
    fi
    if [[ -n "${DETECTED_CHANNELS:-}" ]]; then
      echo "   Canales (de openclaw.json): ${C_BOLD}$DETECTED_CHANNELS${C_RESET}"
    fi
    echo
    local confirm
    confirm=$(ask_choice "¿Proceder?" "s|n" "s")
    [[ "$confirm" == "s" ]] || die "Abortado."
  fi

  # Exportar
  WIZARD_MODE="$mode"
  WIZARD_EMPRESA="$empresa"
  WIZARD_RUBRO="$rubro"
  WIZARD_AREAS="$areas"
  WIZARD_USER="$user"
  WIZARD_CARGO="$cargo"
  WIZARD_ORCH_ID="$orch_id"
}

# =====================================================================
# MODELOS POR ROL
# =====================================================================

model_for_role() {
  case "$1" in
    gerencia)          echo "anthropic/claude-sonnet-4-6" ;;
    legal|finanzas|research|dev)
                       echo "anthropic/claude-opus-4-6"   ;;
    inventario|ops)    echo "anthropic/claude-haiku-4-5"  ;;
    *)                 echo "anthropic/claude-sonnet-4-6" ;;
  esac
}

# Nombre legible para el campo 'name' del openclaw.json
display_name_for_role() {
  case "$1" in
    rrhh)             echo "Recursos Humanos" ;;
    administracion)   echo "Administración" ;;
    ventas)           echo "Ventas" ;;
    marketing)        echo "Marketing" ;;
    legal)            echo "Legal" ;;
    contabilidad)     echo "Contabilidad" ;;
    finanzas)         echo "Finanzas" ;;
    it)               echo "IT / Sistemas" ;;
    logistica)        echo "Logística" ;;
    inventario)       echo "Inventario" ;;
    atencion-cliente) echo "Atención al Cliente" ;;
    compras)          echo "Compras" ;;
    produccion)       echo "Producción" ;;
    calidad)          echo "Calidad" ;;
    dev)              echo "Dev" ;;
    qa)               echo "QA" ;;
    ops)              echo "Ops / DevOps" ;;
    research)         echo "Research" ;;
    writer)           echo "Writer" ;;
    analyst)          echo "Analyst" ;;
    gerencia)         echo "Gerencia" ;;
    # IDs comunes para orquestador
    main)             echo "Main" ;;
    ceo)              echo "CEO" ;;
    director)         echo "Director" ;;
    direccion)        echo "Dirección" ;;
    orquestador)      echo "Orquestador" ;;
    oficina)          echo "Oficina" ;;
    coordinador)      echo "Coordinador" ;;
    # Roles custom: capitalizar primera letra
    *)                echo "$1" | sed 's/./\U&/' ;;
  esac
}

# =====================================================================
# GENERACIÓN
# =====================================================================

copy_base_templates() {
  local workspace="$1"
  mkdir -p "$workspace/memory"

  # Backup timestamped de archivos previos (ej: defaults de `openclaw setup` en inglés)
  local files_to_handle="AGENTS.md BOOT.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md"
  local need_backup=0
  for f in $files_to_handle; do
    [[ -f "$workspace/$f" ]] && need_backup=1 && break
  done

  if [[ $need_backup -eq 1 ]]; then
    local backup_dir="$workspace/.installer-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    for f in $files_to_handle; do
      [[ -f "$workspace/$f" ]] && mv "$workspace/$f" "$backup_dir/"
    done
    log "Archivos previos respaldados en $backup_dir"
  fi

  # Pisar con nuestras plantillas
  for f in AGENTS.md BOOT.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md; do
    cp "$TEMPLATES_DIR/$f" "$workspace/$f"
  done
}

inject_company_context() {
  local workspace="$1" empresa="$2" rubro="$3" role="$4" team_list="$5"
  local agents_file="$workspace/AGENTS.md"
  [[ -f "$agents_file" ]] || return

  # Reemplazar placeholders de §0 Contexto de la Empresa
  sed -i.tmp "s|^- \*\*Empresa:\*\* \`\[\\.\\.\\.\]\`$|- **Empresa:** $empresa|" "$agents_file"
  sed -i.tmp "s|^- \*\*Rubro / actividad:\*\* \`\[ej: fintech B2B / retail de indumentaria / estudio contable / SaaS\]\`$|- **Rubro / actividad:** $rubro|" "$agents_file"
  sed -i.tmp "s|^- \*\*Tu área:\*\* \`\[ej: Recursos Humanos / Ventas / Administración / Gerencia\]\`$|- **Tu área:** $role|" "$agents_file"

  local role_desc
  if [[ "$role" == "gerencia" ]]; then
    role_desc="orquestador (punto de contacto con el humano, coordina al equipo)"
  else
    role_desc="especialista de área (recibe delegaciones del orquestador gerencia)"
  fi
  sed -i.tmp "s|^- \*\*Tu rol en el equipo multi-agente:\*\* \`\[ej: orquestador / especialista de área / asistente único\]\`$|- **Tu rol en el equipo multi-agente:** $role_desc|" "$agents_file"

  # Inyectar lista de equipo: reemplazo línea por línea del marker
  if [[ -n "$team_list" ]]; then
    # Escribimos team_list a un archivo temporal para evitar problemas con caracteres especiales en sed
    local team_file
    team_file="$(mktemp)"
    printf '%s' "$team_list" > "$team_file"
    # Usamos awk para reemplazar la línea exacta del marker por el contenido del archivo
    awk -v team_file="$team_file" '
      /<!-- INSTALLER:INJECT:TEAM -->/ {
        while ((getline line < team_file) > 0) print line
        close(team_file)
        next
      }
      { print }
    ' "$agents_file" > "$agents_file.new"
    mv "$agents_file.new" "$agents_file"
    rm -f "$team_file"
  fi

  rm -f "$agents_file.tmp"
}

personalize_user_md() {
  local workspace="$1" user_name="$2" cargo="$3"
  local user_file="$workspace/USER.md"
  [[ -f "$user_file" ]] || return
  sed -i.tmp "s|^- \*\*Nombre:\*\* \`\[\\.\\.\\.\]\`$|- **Nombre:** $user_name|" "$user_file"
  sed -i.tmp "s|^- \*\*Cómo llamarlo/a:\*\* \`\[nombre, apodo, iniciales\]\`$|- **Cómo llamarlo/a:** $user_name|" "$user_file"
  if [[ -n "$cargo" ]]; then
    sed -i.tmp "s|^- \*\*Cargo / área en la empresa:\*\* \`\[ej: Director de RRHH / Dueño / Socio gerente\]\`$|- **Cargo / área en la empresa:** $cargo|" "$user_file"
  fi
  rm -f "$user_file.tmp"
}

personalize_identity_md() {
  local workspace="$1" agent_id="$2" model="$3" role="$4"
  local id_file="$workspace/IDENTITY.md"
  [[ -f "$id_file" ]] || return
  cat >> "$id_file" <<EOF

---

## Metadata del Agente (auto-generada)

- **Agent ID:** \`$agent_id\`
- **Rol / Área:** \`$role\`
- **Modelo asignado:** \`$model\`
- **Fecha de instalación:** \`$(date +%Y-%m-%d)\`
- **Workspace:** \`$workspace\`
EOF
}

append_role_to_agents_md() {
  local workspace="$1" role="$2"
  local role_file="$TEMPLATES_DIR/roles/$role.md"
  local agents_file="$workspace/AGENTS.md"

  if [[ ! -f "$role_file" ]]; then
    # Rol custom sin plantilla — inyectamos skeleton genérico
    cat >> "$agents_file" <<EOF

---

# Apéndice: Rol Especializado — $role

## Propósito

Sos el agente del área **$role**. Tu alcance, responsabilidades y reglas operativas se definen durante el bootstrap con el dueño del área.

## Reglas mínimas

- Confidencialidad sobre datos internos.
- Escalación al orquestador cuando excede tu dominio.
- Coordinación interdepartamental vía A2A con otros agentes del equipo.
- Tono alineado con la voz de la empresa (ver \`AGENTS.md §0\`).
EOF
    return
  fi

  cat >> "$agents_file" <<EOF

---

# Apéndice: Rol Especializado

EOF
  cat "$role_file" >> "$agents_file"
}

write_bootstrap_personal() {
  local workspace="$1" user_name="$2"
  cp "$TEMPLATES_DIR/BOOTSTRAP.md" "$workspace/BOOTSTRAP.md"
  local tmp="$workspace/BOOTSTRAP.md.new"
  cat > "$tmp" <<EOF
> **MODO: Asistente Personal**
> Instalado por \`install.sh\` v$VERSION el $(date +%Y-%m-%d).
> Humano: $user_name.
> Sos el único agente. No hay equipo — respondés todo vos.

EOF
  cat "$workspace/BOOTSTRAP.md" >> "$tmp"
  mv "$tmp" "$workspace/BOOTSTRAP.md"
}

write_bootstrap_empresa_orquestador() {
  local workspace="$1" user_name="$2" cargo="$3" empresa="$4" rubro="$5" team_list="$6" orch_id="$7"
  local orch_display
  orch_display="$(display_name_for_role "$orch_id")"
  cat > "$workspace/BOOTSTRAP.md" <<EOF
> ## Índice de Documentación
> Consultá el índice completo en: https://docs.openclaw.ai/llms.txt

# BOOTSTRAP.md — Primer Arranque ($orch_display / Orquestador)

> **MODO: Multi-Agente Empresa — Rol: $orch_display (orquestador, ID: \`$orch_id\`)**
> Empresa: **$empresa** (rubro: $rubro)
> Interlocutor principal: **$user_name** (${cargo:-Responsable})
> Instalado por \`install.sh\` v$VERSION el $(date +%Y-%m-%d).

## Sos el coordinador del equipo

Este workspace es el **punto de entrada** del dueño/gerencia al sistema. Mensajes directos (WhatsApp, Telegram, Slack) llegan a vos. Tu trabajo:

1. **Entender la pregunta/pedido** — clarificá antes de delegar si hace falta.
2. **Derivar al área correcta** — usá \`sessions_spawn\` o \`openclaw agent --agent <id> --message "..."\`.
3. **Consolidar el resultado** — sintetizá la respuesta del especialista antes de devolvérsela al dueño.
4. **Mantener el contexto global** — solo vos ves todo. Las áreas son profundas en lo suyo, angostas en lo ajeno.

## Tu equipo

$team_list

La comunicación agente-a-agente (A2A) está **habilitada** (\`tools.agentToAgent.enabled: true\`). Podés delegar hacia cualquiera del allowlist.

## Primera conversación con $user_name

1. Presentate: explicá que sos el orquestador y que detrás tenés un equipo.
2. Confirmá tu nombre, criatura, vibra y emoji (completá \`IDENTITY.md\`).
3. Validá los datos de la empresa que ya están en \`AGENTS.md §0\`.
4. Preguntá por políticas transversales: tono, confidencialidad, horarios, escalación (refiná \`SOUL.md §10\`).
5. Repasá con $user_name cada área del equipo y confirmá alcance/responsabilidades.

## Cuándo hacer vs delegar

- **Hacés vos:** conversaciones, decisiones de coordinación, resúmenes de estado, seguimiento transversal.
- **Delegás:** todo lo que cae en el dominio de un especialista — ver lista de áreas arriba.

## Cuando termines el bootstrap

Borrá este archivo. Empezá a operar.

---

*El $user_name te contrató como coordinador. No como empleado de todas las áreas. Hacelos sonar juntos.*
EOF
}

write_bootstrap_empresa_especialista() {
  local workspace="$1" user_name="$2" cargo="$3" empresa="$4" rubro="$5" role="$6" orch_id="$7"
  cat > "$workspace/BOOTSTRAP.md" <<EOF
> ## Índice de Documentación
> Consultá el índice completo en: https://docs.openclaw.ai/llms.txt

# BOOTSTRAP.md — Primer Arranque (Área: $role)

> **MODO: Multi-Agente Empresa — Rol: $role (especialista)**
> Empresa: **$empresa** (rubro: $rubro)
> Orquestador: \`$orch_id\` — él recibe los mensajes del humano y te delega.
> Instalado por \`install.sh\` v$VERSION el $(date +%Y-%m-%d).

## Sos especialista del área

No sos el punto de entrada del humano. El **orquestador (\`$orch_id\`)** recibe los pedidos de $user_name (${cargo:-Responsable}) y te delega tareas del área **$role**.

Tu trabajo:

1. **Recibir tareas** vía \`sessions_spawn\` desde \`$orch_id\` u otros agentes del equipo.
2. **Ejecutar dentro de tu dominio** — las reglas específicas de tu rol están en \`AGENTS.md\` (apéndice de rol, al final del archivo).
3. **Devolver resultados limpios** — el orquestador consolida y comunica al humano; no le mandes walls of text.
4. **Coordinar con otras áreas** cuando tu tarea dependa de ellas (vía A2A con el allowlist del equipo).

## Primera vez

- Revisá \`AGENTS.md §0\` — contiene el contexto de la empresa (nombre, rubro, políticas transversales, otros departamentos). Si algo no encaja, notalo.
- Completá \`IDENTITY.md\` con nombre/criatura/vibra — ya viene con sugerencias del rol, ajustalas si querés algo propio.
- Leé el apéndice de rol al final de \`AGENTS.md\` — es la diferencia entre hacer bien tu trabajo y hacerlo genérico.
- Si hay stakeholders específicos de tu área (jefe del área, equipo directo), agregalos a \`USER.md\`.

## Reglas firmes

- **Confidencialidad** sobre datos de tu área (nóminas, clientes, proveedores, contratos, números) — nunca salen del workspace salvo orden explícita y verificada.
- **Tono alineado** con la voz de la empresa (ver \`AGENTS.md §0\` → reglas transversales).
- **Escalá** decisiones que exceden tu dominio — al orquestador o al área correspondiente.
- **No hablás directamente con $user_name** salvo que \`$orch_id\` te ceda la palabra o el canal esté específicamente ruteado a vos.

## Cuando termines el bootstrap

Borrá este archivo.

---

*Especialista. Profundo en $role. Conciso en lo que no.*
EOF
}

# =====================================================================
# openclaw.json
# =====================================================================

backup_existing_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local backup="$CONFIG_FILE$BACKUP_SUFFIX"
    cp "$CONFIG_FILE" "$backup"
    ok "Config previo respaldado en: $backup"
  fi
}

write_config_personal() {
  local workspace="$OPENCLAW_HOME/workspace"
  local workspace_native
  workspace_native="$(to_windows_path "$workspace")"
  mkdir -p "$OPENCLAW_HOME"

  # En modo personal no hay agents.list — solo ajustamos workspace paths
  # Si openclaw CLI está instalado, el usuario ya tiene config propio — no hay nada que registrar
  # Si hay Python, mergeamos preservando todo lo previo

  if [[ ! -f "$CONFIG_FILE" ]]; then
    # Sin config previo → generar uno mínimo (requiere openclaw setup después)
    cat > "$CONFIG_FILE" <<EOF
// OpenClaw config — generado por install.sh v$VERSION el $(date +%Y-%m-%d)
// Modo: personal. Corré \`openclaw setup\` para configurar canal y modelo.
{
  "agent": {
    "workspace": "$workspace_native"
  },
  "agents": {
    "defaults": {
      "workspace": "$workspace_native"
    }
  },
  "bindings": []
}
EOF
    warn "No hay config previo — escribí uno mínimo. Corré 'openclaw setup' para completar."
    return
  fi

  if [[ -z "$PYTHON" ]]; then
    info "Config previo detectado — no lo modifico (sin Python no puedo mergear de forma segura)"
    info "Si necesitás cambiar el workspace, hacelo con: openclaw config patch"
    return
  fi

  # Con Python + config existente → mergear de forma mínima, preservando TODO
  local config_native
  config_native="$(to_windows_path "$CONFIG_FILE")"

  CONFIG_PATH="$config_native" WORKSPACE_PATH="$workspace_native" \
    "$PYTHON" - <<'PYEOF' || warn "Merge personal falló — tu config previo se mantiene intacto"
import json, re, os, sys
CFG = os.environ['CONFIG_PATH']
WS  = os.environ['WORKSPACE_PATH']
def strip_json5(s):
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.DOTALL)
    s = re.sub(r'(?<=[{,\s])([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r'"\1":', s)
    s = re.sub(r',(\s*[}\]])', r'\1', s)
    return s
if not os.path.exists(CFG):
    print(f"ERROR: config no existe en {CFG}")
    sys.exit(1)
with open(CFG, 'r', encoding='utf-8') as f:
    cfg = json.loads(strip_json5(f.read()))
cfg.setdefault('agent', {})['workspace'] = WS
cfg.setdefault('agents', {}).setdefault('defaults', {})['workspace'] = WS
with open(CFG, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print("MERGE=OK (personal)")
PYEOF
}

# Convierte path POSIX (/c/Users/x) → Windows nativo (C:\Users\x) si cygpath existe
# Necesario para pasar paths a Python de Windows desde Git Bash
to_windows_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p" 2>/dev/null || echo "$p"
  else
    echo "$p"
  fi
}

# Detectar si openclaw CLI está instalado y funcional
has_openclaw_cli() {
  command -v openclaw >/dev/null 2>&1
}

# Decide si hay que usar el merger Python para writes de config (D5).
# El merger SOLO es necesario cuando:
#   a) No hay CLI instalado — es la única forma de escribir config.
#   b) No hay firma de integridad (HAS_OPENCLAW_META=0) — no hay nada que romper.
# En la ruta CLI + meta, el merger se SALTA para no corromper la firma.
should_use_legacy_merger() {
  if ! has_openclaw_cli; then
    return 0  # sin CLI → usar merger (único path disponible)
  fi
  if [[ "${HAS_OPENCLAW_META:-0}" != "1" ]]; then
    return 0  # sin meta/firma → no hay integridad que preservar, merger es seguro
  fi
  return 1    # CLI + meta presentes → NUNCA pasar por el merger
}

# =====================================================================
# ESTRATEGIA PRIMARIA: usar `openclaw agents add` (respeta firmas meta)
# =====================================================================
register_agents_via_cli() {
  local orch_id="$1" areas_list="$2"

  info "Usando ${C_BOLD}openclaw agents add${C_RESET} (respeta firmas de integridad del config)"

  # ---------------------------------------------------------------------------
  # BF-2: Registrar el orquestador ANTES que los especialistas cuando no es 'main'.
  # El modelo previo asumía que OpenClaw trata cualquier orch_id como 'main' implícito
  # — eso fue desmentido en 2026.4.x: si orch_id != 'main', queda sin registrar.
  # ---------------------------------------------------------------------------
  if [[ "$orch_id" != "main" ]]; then
    local gws="$OPENCLAW_HOME/workspace"
    local gws_native
    gws_native="$(to_windows_path "$gws")"
    local orch_display
    orch_display="$(display_name_for_role "$orch_id") (Orquestador)"

    # BF-2 C2 fix: distinguir re-ejecución idempotente de falla real.
    # Primero probamos si el agente ya existe; si es así, saltamos el add sin error.
    if openclaw agents list 2>/dev/null | grep -q "^$orch_id\b\|\"$orch_id\""; then
      info "Orquestador '$orch_id' ya existe — saltando registro (idempotente)"
    elif ! openclaw agents add "$orch_id" --workspace "$gws_native" --non-interactive >/dev/null 2>&1; then
      die "Error: no se pudo registrar el orquestador '$orch_id' (openclaw agents add falló)"
    else
      ok "Orquestador registrado: $orch_id"
    fi

    # BF-1: set-identity del orquestador con display name
    if [[ "$HAS_SET_IDENTITY_NAME" == "1" ]]; then
      openclaw agents set-identity --agent "$orch_id" \
        "$SET_IDENTITY_NAME_FLAG" "$orch_display" \
        --workspace "$gws_native" --non-interactive >/dev/null 2>&1 \
        || warn "set-identity para orquestador '$orch_id' falló — el display name se derivará del id"
    else
      warn "set-identity --name no detectado en el CLI — display name del orquestador derivará del id"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Registrar especialistas
  # ---------------------------------------------------------------------------
  IFS=',' read -ra ROLES <<< "$areas_list"
  for role in "${ROLES[@]}"; do
    role="$(echo "$role" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ -z "$role" ]] && continue
    [[ "$role" == "$orch_id" ]] && continue
    [[ "$role" == "main" ]] && continue  # 'main' es reservado para el default
    local ws="$OPENCLAW_HOME/workspace-$role"
    local ws_native
    ws_native="$(to_windows_path "$ws")"
    local display_name
    display_name="$(display_name_for_role "$role")"

    # openclaw agents add <id> --workspace <path> --non-interactive
    if openclaw agents add "$role" --workspace "$ws_native" --non-interactive >/dev/null 2>&1; then
      ok "Agente registrado: $role"

      # BF-1: set display name via set-identity (solo si el CLI lo soporta)
      if [[ "$HAS_SET_IDENTITY_NAME" == "1" ]]; then
        openclaw agents set-identity --agent "$role" \
          "$SET_IDENTITY_NAME_FLAG" "$display_name" \
          --workspace "$ws_native" --non-interactive >/dev/null 2>&1 \
          || warn "set-identity para '$role' falló — display name derivará del id"
      else
        warn "set-identity (--name|--display-name|--label) no detectado en CLI — display name de '$role' derivará del id"
      fi
    else
      # Puede fallar si ya existe — probar actualización de identidad
      warn "Agente '$role' quizá ya existía — intentando update..."

      # BF-4: solo pasar --from-identity si IDENTITY.md está relleno
      # (no mezclar placeholder de template con identidad real ya guardada)
      if is_identity_filled "$ws/IDENTITY.md"; then
        openclaw agents set-identity --agent "$role" --from-identity --workspace "$ws_native" \
          >/dev/null 2>&1 \
          || warn "No se pudo re-registrar $role — agregalo manualmente con: openclaw agents add $role --workspace \"$ws_native\""
      else
        info "IDENTITY.md de '$role' aún no fue completada — saltando --from-identity (el agente lo completará en su primer arranque)"
        warn "Para re-registrar manualmente: openclaw agents add $role --workspace \"$ws_native\""
      fi
    fi
  done

  # ---------------------------------------------------------------------------
  # BF-3: Habilitar A2A — CLI path NO usa merger Python (evita corromper firma)
  # La función enable_a2a_via_cli intenta config patch; si no está disponible,
  # imprime el snippet manual. El merger SOLO corre en fallback (should_use_legacy_merger).
  # ---------------------------------------------------------------------------
  enable_a2a_via_cli "$orch_id" "$areas_list"

  # ---------------------------------------------------------------------------
  # BF-6 + SP-1 + SP-2: escribir subagents policy (empresa mode + CLI 2026.4.23+)
  # ---------------------------------------------------------------------------
  write_subagents_policy_empresa
}

# Habilita A2A via CLI (config patch) o imprime instrucciones manuales.
# No invoca el merger Python — ese queda SOLO para write_config_empresa_fallback.
enable_a2a_via_cli() {
  local orch_id="$1" areas_list="$2"
  local allow_list="\"main\""

  IFS=',' read -ra ROLES <<< "$areas_list"
  for role in "${ROLES[@]}"; do
    role="$(echo "$role" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ -z "$role" ]] && continue
    [[ "$role" == "$orch_id" ]] && continue
    [[ "$role" == "main" ]] && continue
    allow_list="$allow_list,\"$role\""
  done

  if [[ "$HAS_CONFIG_PATCH" == "1" ]]; then
    # CLI tiene config patch — úsalo para no tocar la firma
    local a2a_patch
    a2a_patch='{"tools":{"agentToAgent":{"enabled":true,"allow":['"$allow_list"']}}}'
    if openclaw config patch --merge "$a2a_patch" >/dev/null 2>&1; then
      ok "A2A habilitado via CLI (allowlist: $allow_list)"
    else
      warn "config patch falló — A2A debe habilitarse manualmente en openclaw.json:"
      warn "  tools.agentToAgent.enabled: true"
      warn "  tools.agentToAgent.allow: [$allow_list]"
    fi
  elif should_use_legacy_merger && [[ -n "$PYTHON" ]] && [[ -n "$MERGE_SCRIPT" ]]; then
    # Sin config patch pero tenemos merger disponible y es seguro usarlo
    warn "Usando legacy Python merge para A2A — verificá integridad con: openclaw doctor"
    enable_a2a_via_merger "$orch_id" "$areas_list"
  else
    warn "A2A debe habilitarse manualmente en openclaw.json:"
    warn '  tools.agentToAgent.enabled: true'
    warn "  tools.agentToAgent.allow: [$allow_list]"
  fi
}

# Escribe la política de subagents para modo empresa (BF-6, SP-1, SP-2).
# Requiere: WIZARD_MODE == empresa, HAS_CONFIG_PATCH == 1, cli_version_gte 2026.4.23.
# Solo es llamada desde register_agents_via_cli (CLI path).
write_subagents_policy_empresa() {
  # Solo en modo empresa
  [[ "${WIZARD_MODE:-}" == "empresa" ]] || return 0

  # SP-2: verificar que el CLI es suficientemente nuevo
  if ! cli_version_gte 2026.4.23; then
    warn "CLI anterior a 2026.4.23 — subagents policy no se escribirá. Actualizá con: npm update -g openclaw"
    warn "(2026.4.23) subagents policy skipped — versión detectada no soporta config patch --merge"
    return 0
  fi

  if [[ "$HAS_CONFIG_PATCH" != "1" ]]; then
    warn "config patch no disponible — subagents policy skipped. Configurá manualmente:"
    warn "  agents.defaults.subagents.maxSpawnDepth: 2"
    warn "  agents.defaults.subagents.maxChildrenPerAgent: 5"
    warn "  tools.subagents.tools.deny: [\"gateway\",\"cron\"]"
    return 0
  fi

  # SP-1: escribir los tres campos requeridos via config patch --merge
  local policy_patch
  policy_patch='{"agents":{"defaults":{"subagents":{"maxSpawnDepth":2,"maxChildrenPerAgent":5}}},"tools":{"subagents":{"tools":{"deny":["gateway","cron"]}}}}'
  if openclaw config patch --merge "$policy_patch" >/dev/null 2>&1; then
    ok "Subagents policy escrita (maxSpawnDepth=2, maxChildrenPerAgent=5, deny=[gateway,cron])"
  else
    warn "No se pudo escribir subagents policy — configurá manualmente:"
    warn "  agents.defaults.subagents.maxSpawnDepth: 2"
    warn "  agents.defaults.subagents.maxChildrenPerAgent: 5"
    warn "  tools.subagents.tools.deny: [\"gateway\",\"cron\"]"
  fi
}

# Merger Python SOLO para agregar tools.agentToAgent (preserva TODO lo demás)
enable_a2a_via_merger() {
  local orch_id="$1" areas_list="$2"
  local allow_json="\"main\""

  IFS=',' read -ra ROLES <<< "$areas_list"
  for role in "${ROLES[@]}"; do
    role="$(echo "$role" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ -z "$role" ]] && continue
    [[ "$role" == "$orch_id" ]] && continue
    [[ "$role" == "main" ]] && continue
    allow_json="$allow_json,\"$role\""
  done

  local payload="$(mktemp)"
  cat > "$payload" <<EOF
{
  "a2a_allow": [$allow_json]
}
EOF

  local config_native payload_native
  config_native="$(to_windows_path "$CONFIG_FILE")"
  payload_native="$(to_windows_path "$payload")"

  CONFIG_PATH="$config_native" NEW_AGENTS_PATH="$payload_native" \
    "$PYTHON" - <<'PYEOF' 2>&1 | tail -5 || warn "A2A no habilitado — hacelo manual"
import json, re, os, sys
CFG = os.environ['CONFIG_PATH']
NEW = os.environ['NEW_AGENTS_PATH']
def strip_json5(s):
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.DOTALL)
    s = re.sub(r'(?<=[{,\s])([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r'"\1":', s)
    s = re.sub(r',(\s*[}\]])', r'\1', s)
    return s
if not os.path.exists(CFG):
    print(f"ERROR: no encuentro config en {CFG}")
    sys.exit(1)
with open(CFG,'r',encoding='utf-8') as f:
    cfg = json.loads(strip_json5(f.read()))
with open(NEW,'r',encoding='utf-8') as f:
    new = json.load(f)
cfg.setdefault('tools', {})
cfg['tools']['agentToAgent'] = {'enabled': True, 'allow': new['a2a_allow']}
cfg.setdefault('agents', {}).setdefault('defaults', {})
d = cfg['agents']['defaults']
if (d.get('bootstrapMaxChars', 0) or 0) < 16000:
    d['bootstrapMaxChars'] = 16000
d.setdefault('bootstrapPromptTruncationWarning', 'once')
with open(CFG,'w',encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print("A2A_ENABLED")
PYEOF
  rm -f "$payload"
  ok "A2A habilitado (allowlist: $allow_json)"
}

# =====================================================================
# ESTRATEGIA FALLBACK: merger Python directo (si openclaw CLI no está)
# =====================================================================
write_config_empresa_fallback() {
  local empresa="$1" user_name="$2" areas_list="$3" orch_id="$4"
  warn "openclaw CLI no está instalado — usando merger Python directo"
  warn "CUIDADO: si OpenClaw tiene firmas de integridad (meta), puede detectar tampering."
  warn "Recomendado: instalá openclaw primero (npm install -g openclaw) y re-ejecutá este script."

  mkdir -p "$OPENCLAW_HOME"

  local new_agents_file agents_json="" allow_json=""
  new_agents_file="$(mktemp)"

  local orch_display
  orch_display="$(display_name_for_role "$orch_id") (Orquestador)"
  local orch_ws_native
  orch_ws_native="$(to_windows_path "$OPENCLAW_HOME/workspace")"
  agents_json="{\"id\":\"$orch_id\",\"name\":\"$orch_display\",\"default\":true,\"workspace\":\"$orch_ws_native\"}"
  allow_json="\"$orch_id\""

  IFS=',' read -ra ROLES <<< "$areas_list"
  for role in "${ROLES[@]}"; do
    role="$(echo "$role" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ -z "$role" ]] && continue
    [[ "$role" == "$orch_id" ]] && continue
    local display_name ws_native
    display_name="$(display_name_for_role "$role")"
    ws_native="$(to_windows_path "$OPENCLAW_HOME/workspace-$role")"
    agents_json="$agents_json,{\"id\":\"$role\",\"name\":\"$display_name\",\"workspace\":\"$ws_native\"}"
    allow_json="$allow_json,\"$role\""
  done

  cat > "$new_agents_file" <<EOF
{
  "orchestrator_id": "$orch_id",
  "agents_list": [$agents_json],
  "a2a_allow": [$allow_json]
}
EOF

  if [[ -n "$PYTHON" ]] && [[ -n "$MERGE_SCRIPT" ]]; then
    local config_native payload_native
    config_native="$(to_windows_path "$CONFIG_FILE")"
    payload_native="$(to_windows_path "$new_agents_file")"

    local merge_out
    merge_out="$(mktemp)"
    # WIZARD_MODE pasado al merger para que aplique subagents policy solo en empresa (BF-6)
    CONFIG_PATH="$config_native" NEW_AGENTS_PATH="$payload_native" WIZARD_MODE="${WIZARD_MODE:-}" \
      "$PYTHON" "$MERGE_SCRIPT" > "$merge_out" 2>&1 || {
        cat "$merge_out" >&2
        die "Falló el merge del config"
      }
    if grep -q "AUTO_BIND=" "$merge_out"; then
      local bind
      bind="$(grep '^AUTO_BIND=' "$merge_out" | cut -d= -f2-)"
      ok "Auto-bindeado orquestador: $bind"
    fi
    ok "Config mergeado preservando channels/auth/defaults previos"
    rm -f "$merge_out" "$new_agents_file"
    return
  fi

  # Último fallback: escribir desde cero (AVISO claro)
  warn "Sin openclaw CLI y sin Python — escribiendo config MÍNIMO desde cero."
  warn "Perderás channels/auth/defaults previos. Restaura desde: ${CONFIG_FILE}${BACKUP_SUFFIX}"
  cat > "$CONFIG_FILE" <<EOF
// OpenClaw config — generado por install.sh v$VERSION el $(date +%Y-%m-%d)
// Empresa: $empresa  |  Responsable: $user_name
{
  "agents": {
    "defaults": {
      "bootstrapMaxChars": 16000,
      "bootstrapPromptTruncationWarning": "once",
      "subagents": {
        "maxSpawnDepth": 2,
        "maxChildrenPerAgent": 5
      }
    },
    "list": [$agents_json]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": [$allow_json]
    },
    "subagents": {
      "tools": {
        "deny": ["gateway", "cron"]
      }
    }
  },
  "bindings": []
}
EOF
  rm -f "$new_agents_file"
}

# Función principal: elige la estrategia según el entorno
write_config_empresa() {
  local empresa="$1" user_name="$2" areas_list="$3" orch_id="$4"

  if has_openclaw_cli; then
    register_agents_via_cli "$orch_id" "$areas_list"
  else
    write_config_empresa_fallback "$empresa" "$user_name" "$areas_list" "$orch_id"
  fi
}

# =====================================================================
# INSTALL
# =====================================================================

install_personal() {
  local user_name="$1"
  local workspace="$OPENCLAW_HOME/workspace"

  step "Creando workspace personal en $workspace"
  mkdir -p "$workspace"
  copy_base_templates "$workspace"
  personalize_user_md "$workspace" "$user_name" ""
  write_bootstrap_personal "$workspace" "$user_name"

  step "Generando $CONFIG_FILE"
  backup_existing_config
  write_config_personal

  ok "Workspace personal listo en $workspace"
}

install_empresa() {
  local empresa="$1" rubro="$2" user_name="$3" cargo="$4" areas_list="$5" orch_id="$6"

  # Construir team_list por agente (excluyendo al propio rol y al orquestador)
  build_team_list() {
    local exclude_role="$1" list=""
    IFS=',' read -ra ROLES2 <<< "$areas_list"
    for r in "${ROLES2[@]}"; do
      r="$(echo "$r" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
      [[ -z "$r" ]] && continue
      [[ "$r" == "$orch_id" ]] && continue
      [[ "$r" == "$exclude_role" ]] && continue
      local desc="${ROLE_DESC[$r]:-área custom}"
      local dname
      dname="$(display_name_for_role "$r")"
      list="${list}- \`$r\` (**$dname**) → $desc
"
    done
    printf '%s' "$list"
  }

  # Lista completa (para el BOOTSTRAP del orquestador)
  local full_team_list
  full_team_list="$(build_team_list "")"

  # Orquestador (workspace default, ID configurable)
  local gws="$OPENCLAW_HOME/workspace"
  step "Creando orquestador '$orch_id' en $gws"
  mkdir -p "$gws"
  copy_base_templates "$gws"
  personalize_user_md "$gws" "$user_name" "$cargo"
  personalize_identity_md "$gws" "$orch_id" "$(model_for_role gerencia)" "orchestrator"
  inject_company_context "$gws" "$empresa" "$rubro" "$orch_id" "$full_team_list"
  append_role_to_agents_md "$gws" "gerencia"
  write_bootstrap_empresa_orquestador "$gws" "$user_name" "$cargo" "$empresa" "$rubro" "$full_team_list" "$orch_id"

  # Especialistas
  IFS=',' read -ra ROLES <<< "$areas_list"
  for role in "${ROLES[@]}"; do
    role="$(echo "$role" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ -z "$role" ]] && continue
    [[ "$role" == "$orch_id" ]] && continue
    local ws="$OPENCLAW_HOME/workspace-$role"
    local model team_list_self
    model="$(model_for_role "$role")"
    team_list_self="$(build_team_list "$role")"
    step "Creando área '$role' en $ws"
    mkdir -p "$ws"
    copy_base_templates "$ws"
    personalize_user_md "$ws" "$user_name" "$cargo"
    personalize_identity_md "$ws" "$role" "$model" "$role"
    inject_company_context "$ws" "$empresa" "$rubro" "$role" "$team_list_self"
    append_role_to_agents_md "$ws" "$role"
    write_bootstrap_empresa_especialista "$ws" "$user_name" "$cargo" "$empresa" "$rubro" "$role" "$orch_id"
  done

  step "Generando $CONFIG_FILE con A2A habilitado"
  backup_existing_config
  write_config_empresa "$empresa" "$user_name" "$areas_list" "$orch_id"

  ok "Equipo multi-agente empresarial listo — empresa: $empresa"
}

# =====================================================================
# POST-INSTALL SMOKE TEST (ST-1, ST-2, D7)
# =====================================================================

# Ejecuta un comando con timeout y captura stdout+stderr.
# Detecta 'timeout' (Linux/Git Bash) o 'gtimeout' (macOS via coreutils).
# Si no hay ninguno, corre el comando sin timeout (degradado pero funcional).
# Uso interno: output="$(run_check "label" "comando" timeout_segundos)"
# No falla — siempre devuelve el output capturado (puede estar vacío).
run_check() {
  local label="$1" cmd="$2" timeout_s="$3"
  local out
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "$timeout_s" bash -c "$cmd" 2>&1)" || true
  elif command -v gtimeout >/dev/null 2>&1; then
    out="$(gtimeout "$timeout_s" bash -c "$cmd" 2>&1)" || true
  else
    # Sin timeout disponible — correr igual (no bloquear la instalación)
    out="$(bash -c "$cmd" 2>&1)" || true
  fi
  echo "$out"
}

# Corre tres verificaciones post-install y emite una línea [PASS|WARN|FAIL] por check.
# Agrega un banner final según el peor resultado observado.
# NUNCA retorna non-zero — los fallos son advisory, no bloquean la instalación.
post_install_smoke_test() {
  echo
  step "Verificación post-instalación (smoke test)"

  local overall=0   # 0=pass 1=warn 2=fail

  # Helpers de output — formato ST-2: "[PASS|WARN|FAIL] <check>: <detalle>"
  _smoke_pass() { printf '%s[PASS]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
  _smoke_warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; [[ $overall -lt 1 ]] && overall=1; }
  _smoke_fail() { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*"; [[ $overall -lt 2 ]] && overall=2; }

  # ------------------------------------------------------------------
  # Check 1: openclaw doctor (10 segundos) — verifica integridad firma
  # ------------------------------------------------------------------
  # NOTA (W2 deferred a v2.4): la detección de PASS/FAIL es por keywords del output
  # (no por exit code) porque run_check absorbe el exit code para no propagar fallos
  # del timeout. Mejorar a detección por exit code en v2.4.
  local doctor_out
  doctor_out="$(run_check "doctor" "openclaw doctor" 10)"
  if [[ -z "$doctor_out" ]]; then
    _smoke_warn "doctor: sin respuesta en 10s (timeout o CLI no instalado)"
  elif echo "$doctor_out" | grep -qi "signature\|tampering\|corrupt\|error"; then
    _smoke_fail "doctor: error de integridad detectado — corré 'openclaw doctor' para diagnóstico"
  elif echo "$doctor_out" | grep -qi "ok\|healthy\|✓\|passed"; then
    _smoke_pass "doctor: firma de integridad verificada"
  else
    # doctor corrió pero no hay indicador explícito — asumir OK si exit fue 0
    _smoke_warn "doctor: output no reconocido — verificá manualmente con 'openclaw doctor'"
  fi

  # ------------------------------------------------------------------
  # Check 2: openclaw agents list (5 segundos) — agentes registrados
  # ------------------------------------------------------------------
  local agents_out orch="${WIZARD_ORCH_ID:-gerencia}"
  agents_out="$(run_check "agents-list" "openclaw agents list 2>&1" 5)"
  if [[ -z "$agents_out" ]]; then
    _smoke_warn "agents-list: sin respuesta en 5s — verificá con 'openclaw agents list'"
  elif echo "$agents_out" | grep -q "$orch"; then
    _smoke_pass "agents-list: orquestador '$orch' presente en agents list"
  else
    _smoke_fail "agents-list: orquestador '$orch' NO encontrado — registración puede haber fallado"
  fi

  # ------------------------------------------------------------------
  # Check 3: bindings (empresa only, 5 segundos)
  # ------------------------------------------------------------------
  if [[ "${WIZARD_MODE:-}" == "empresa" ]]; then
    local bindings_out
    bindings_out="$(run_check "bindings" "openclaw agents list --bindings 2>&1" 5)"
    if [[ -z "$bindings_out" ]]; then
      _smoke_warn "bindings: sin respuesta en 5s — verificá con 'openclaw agents list --bindings'"
    elif echo "$bindings_out" | grep -q "$orch"; then
      if [[ -n "${DETECTED_CHANNELS:-}" ]] && echo "$bindings_out" | grep -q "${DETECTED_CHANNELS%%,*}"; then
        _smoke_pass "bindings: orquestador '$orch' bindeado al canal ${DETECTED_CHANNELS%%,*}"
      else
        _smoke_warn "bindings: '$orch' aparece en lista pero sin canal detectado — bindéalo con: openclaw agents bind --agent $orch --bind <canal>"
      fi
    else
      _smoke_warn "bindings: sin bindings para '$orch' aún — bindéalo después con: openclaw agents bind --agent $orch --bind <canal>"
    fi
  fi

  # ------------------------------------------------------------------
  # Banner resumen
  # ------------------------------------------------------------------
  echo
  case $overall in
    0) printf '%s[✓] Smoke test: equipo verificado correctamente.%s\n' "$C_GREEN" "$C_RESET" ;;
    1) printf '%s[⚠] Smoke test: instalación completa pero con advertencias — revisá los warnings arriba.%s\n' "$C_YELLOW" "$C_RESET" ;;
    2) printf '%s[✗] Smoke test: verificaciones críticas fallaron — corré "openclaw doctor" para diagnóstico.%s\n' "$C_RED" "$C_RESET" ;;
  esac
  echo
  # Smoke failures son advisory — NO retornar non-zero
  return 0
}

# =====================================================================
# NEXT STEPS
# =====================================================================

print_next_steps() {
  step "Próximos pasos"

  local orch="${WIZARD_ORCH_ID:-gerencia}"
  local detected_channel=""
  [[ -n "${DETECTED_CHANNELS:-}" ]] && detected_channel="${DETECTED_CHANNELS%%,*}"

  if [[ "$WIZARD_MODE" == "empresa" ]]; then
    if [[ -n "$detected_channel" ]]; then
      cat <<EOF

${C_GREEN}Tu equipo ya está operativo.${C_RESET}

El orquestador \`$orch\` está ${C_BOLD}auto-bindeado al canal $detected_channel${C_RESET} que configuraste con \`openclaw setup\`.
Los especialistas reciben trabajo vía A2A (delegación interna del orquestador).

${C_BOLD}Solo te queda reiniciar el gateway:${C_RESET}
   ${C_DIM}openclaw gateway restart${C_RESET}

${C_BOLD}Después, mandale un mensaje a $detected_channel:${C_RESET}
   El orquestador va a leer su BOOTSTRAP.md y charlar con vos
   para elegir nombre, vibra y emoji. Los especialistas harán
   lo mismo la primera vez que les delegues una tarea.
EOF
    else
      cat <<EOF

${C_YELLOW}Workspaces creados pero sin canal detectado.${C_RESET}

${C_BOLD}1) Conectá un canal:${C_RESET}
   ${C_DIM}openclaw setup                              # wizard oficial${C_RESET}
   ${C_DIM}# o directo:${C_RESET}
   ${C_DIM}openclaw channels login --channel telegram${C_RESET}

${C_BOLD}2) Bindeá el orquestador al canal:${C_RESET}
   ${C_DIM}openclaw agents bind --agent $orch --bind telegram${C_RESET}

${C_BOLD}3) Reiniciá el gateway:${C_RESET}
   ${C_DIM}openclaw gateway restart${C_RESET}
EOF
    fi

    cat <<EOF

${C_DIM}---${C_RESET}

${C_BOLD}Opcional: canal propio por agente${C_RESET}
Si querés que un especialista tenga su propio canal (ej: ventas con
su propio bot de Telegram), bindealo después:
   ${C_DIM}openclaw channels login --channel telegram --account ventas_bot${C_RESET}
   ${C_DIM}openclaw agents bind --agent ventas --bind telegram:ventas_bot${C_RESET}

${C_BOLD}Verificá el equipo:${C_RESET}
   ${C_DIM}openclaw agents list --bindings${C_RESET}
EOF
  else
    # Modo personal
    if [[ -n "$detected_channel" ]]; then
      cat <<EOF

${C_GREEN}Tu asistente está listo en el canal $detected_channel.${C_RESET}

${C_BOLD}Solo reiniciá el gateway:${C_RESET}
   ${C_DIM}openclaw gateway restart${C_RESET}
EOF
    else
      cat <<EOF

${C_BOLD}1) Configurá canal con el wizard oficial:${C_RESET}
   ${C_DIM}openclaw setup${C_RESET}

${C_BOLD}2) Reiniciá:${C_RESET}
   ${C_DIM}openclaw gateway restart${C_RESET}
EOF
    fi
  fi

  cat <<EOF

${C_DIM}---${C_RESET}

${C_BOLD}Workspaces creados:${C_RESET}
EOF
  for d in "$OPENCLAW_HOME"/workspace "$OPENCLAW_HOME"/workspace-*; do
    [[ -d "$d" ]] && echo "   $d"
  done
  cat <<EOF

${C_BOLD}Config:${C_RESET}
   $CONFIG_FILE

${C_GREEN}Listo.${C_RESET}
EOF
}

# =====================================================================
# MAIN
# =====================================================================

main() {
  banner
  check_requirements
  setup_python_merger || true   # opcional — sin Python tenemos fallback
  detect_openclaw_config        # lee modelo/canales del openclaw.json existente
  detect_templates
  run_wizard

  case "$WIZARD_MODE" in
    personal) install_personal "$WIZARD_USER" ;;
    empresa)  install_empresa  "$WIZARD_EMPRESA" "$WIZARD_RUBRO" "$WIZARD_USER" "$WIZARD_CARGO" "$WIZARD_AREAS" "$WIZARD_ORCH_ID" ;;
    *)        die "Modo inválido: $WIZARD_MODE" ;;
  esac

  # ST-1: ejecutar smoke test post-install solo cuando hay CLI disponible.
  # Es non-fatal — nunca cambia el exit code de install.sh.
  if has_openclaw_cli; then
    post_install_smoke_test || true
  fi

  print_next_steps
}

main "$@"
