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

VERSION="2.1.0"
# Cuando el script se baja con curl | bash, BASH_SOURCE puede no existir (se lee de stdin)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
TEMPLATES_DIR=""
# URL default al raw de GitHub — usada cuando se ejecuta vía `curl | bash`
TEMPLATES_URL="${TEMPLATES_URL:-https://raw.githubusercontent.com/QuBiit0/openclaworkinstaller/main/templates}"

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"

# CLI args
ARG_MODE=""
ARG_EMPRESA=""
ARG_RUBRO=""
ARG_AREAS=""
ARG_USER=""
ARG_CARGO=""
ARG_ORCH_ID=""
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
    --orchestrator-id)    ARG_ORCH_ID="$2"; shift 2 ;;
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

# =====================================================================
# CHECKS
# =====================================================================

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando requerido no encontrado: $1"
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

  local tmp_out
  tmp_out="$(mktemp)"
  "$PYTHON" - "$CONFIG_FILE" > "$tmp_out" 2>/dev/null <<'PYEOF' || true
import json, re, os, sys
p = sys.argv[1]
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
model = defaults.get('model') or (d.get('agent') or {}).get('model', '') or ''
channels = list((d.get('channels') or {}).keys())
print(f"MODEL={model}")
print(f"CHANNELS={','.join(channels)}")
PYEOF
  DETECTED_MODEL="$(grep '^MODEL=' "$tmp_out" 2>/dev/null | cut -d= -f2- 2>/dev/null || true)"
  DETECTED_CHANNELS="$(grep '^CHANNELS=' "$tmp_out" 2>/dev/null | cut -d= -f2- 2>/dev/null || true)"
  DETECTED_MODEL="${DETECTED_MODEL:-}"
  DETECTED_CHANNELS="${DETECTED_CHANNELS:-}"
  rm -f "$tmp_out"

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

    # ID del agente principal (orquestador)
    if [[ -n "$ARG_ORCH_ID" ]]; then
      orch_id="$ARG_ORCH_ID"
    elif [[ "$ARG_NON_INTERACTIVE" == "true" ]]; then
      orch_id="gerencia"
    else
      echo
      info "ID del agente principal (el que coordina al equipo y habla con vos)."
      info "Sugerencias comunes: ${C_BOLD}gerencia${C_RESET} / ${C_BOLD}main${C_RESET} / ${C_BOLD}ceo${C_RESET} / ${C_BOLD}director${C_RESET} / ${C_BOLD}orquestador${C_RESET}"
      info "Debe ser lowercase, letras/números/guiones. Nombre propio/personalidad se define después en BOOTSTRAP."
      while true; do
        orch_id=$(ask "ID del agente principal" "gerencia")
        orch_id="$(echo "$orch_id" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        if [[ "$orch_id" =~ ^[a-z][a-z0-9-]*$ ]]; then
          break
        fi
        warn "ID inválido. Solo lowercase, letras/números/guiones, debe empezar con letra."
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
  mkdir -p "$OPENCLAW_HOME"

  if [[ -z "$PYTHON" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
    # Sin Python o sin config previo → generar uno mínimo
    cat > "$CONFIG_FILE" <<EOF
// OpenClaw config — generado por install.sh v$VERSION el $(date +%Y-%m-%d)
// Modo: personal (single agent)
// Nota: este archivo se crea si no existía. Si corriste \`openclaw setup\` antes,
// tu config previa se respetó y estos son solo ajustes mínimos.
{
  "agent": {
    "workspace": "$workspace"
  },
  "agents": {
    "defaults": {
      "workspace": "$workspace"
    }
  },
  "bindings": []
}
EOF
    return
  fi

  # Con Python + config existente → mergear para preservar todo
  local new_agents_file
  new_agents_file="$(mktemp)"
  cat > "$new_agents_file" <<EOF
{
  "orchestrator_id": "",
  "agents_list": [],
  "a2a_allow": []
}
EOF
  # Para personal no tocamos agents.list. Solo actualizamos agent.workspace.
  # Ejecutamos un merger simplificado inline.
  CONFIG_PATH="$CONFIG_FILE" NEW_AGENTS_PATH="$new_agents_file" \
    WORKSPACE_PATH="$workspace" \
    "$PYTHON" - <<'PYEOF'
import json, re, os, sys
CFG = os.environ['CONFIG_PATH']
WS  = os.environ['WORKSPACE_PATH']
def strip_json5(s):
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.DOTALL)
    s = re.sub(r'(?<=[{,\s])([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r'"\1":', s)
    s = re.sub(r',(\s*[}\]])', r'\1', s)
    return s
with open(CFG, 'r', encoding='utf-8') as f:
    cfg = json.loads(strip_json5(f.read()))
cfg.setdefault('agent', {})['workspace'] = WS
cfg.setdefault('agents', {}).setdefault('defaults', {})['workspace'] = WS
with open(CFG, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
print("MERGE=OK (personal)")
PYEOF
  rm -f "$new_agents_file"
}

write_config_empresa() {
  local empresa="$1" user_name="$2" areas_list="$3" orch_id="$4"
  mkdir -p "$OPENCLAW_HOME"

  # Construir payload con los nuevos agentes (sin model — heredan del default)
  local new_agents_file
  new_agents_file="$(mktemp)"

  # Agents list como JSON array
  local agents_json=""
  local allow_json=""

  local orch_display
  orch_display="$(display_name_for_role "$orch_id") (Orquestador)"
  agents_json="{\"id\":\"$orch_id\",\"name\":\"$orch_display\",\"default\":true,\"workspace\":\"$OPENCLAW_HOME/workspace\"}"
  allow_json="\"$orch_id\""

  IFS=',' read -ra ROLES <<< "$areas_list"
  for role in "${ROLES[@]}"; do
    role="$(echo "$role" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ -z "$role" ]] && continue
    [[ "$role" == "$orch_id" ]] && continue
    local display_name
    display_name="$(display_name_for_role "$role")"
    agents_json="$agents_json,{\"id\":\"$role\",\"name\":\"$display_name\",\"workspace\":\"$OPENCLAW_HOME/workspace-$role\"}"
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
    # Modo merge: preserva channels/auth/defaults del config existente
    local merge_out
    merge_out="$(mktemp)"
    CONFIG_PATH="$CONFIG_FILE" NEW_AGENTS_PATH="$new_agents_file" \
      "$PYTHON" "$MERGE_SCRIPT" > "$merge_out" 2>&1 || {
        cat "$merge_out" >&2
        die "Falló el merge del config"
      }
    # Mostrar info relevante del merge
    if grep -q "AUTO_BIND=" "$merge_out"; then
      local bind
      bind="$(grep '^AUTO_BIND=' "$merge_out" | cut -d= -f2-)"
      ok "Auto-bindeado orquestador: $bind"
    fi
    ok "Config mergeado preservando channels/auth/defaults previos"
    rm -f "$merge_out" "$new_agents_file"
    return
  fi

  # Fallback: sin Python → escribir config desde cero (avisar)
  warn "Generando openclaw.json desde cero (sin Python no pude hacer merge)"
  warn "Si tenías config previa con channels/auth, recuperala desde el backup: $CONFIG_FILE$BACKUP_SUFFIX"
  cat > "$CONFIG_FILE" <<EOF
// OpenClaw config — generado por install.sh v$VERSION el $(date +%Y-%m-%d)
// Empresa: $empresa  |  Responsable: $user_name
// Modo: multi-agente. Corré \`openclaw setup\` para agregar canal/modelo.
{
  "agents": {
    "defaults": {
      "bootstrapMaxChars": 16000,
      "bootstrapPromptTruncationWarning": "once"
    },
    "list": [$agents_json]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": [$allow_json]
    }
  },
  "bindings": []
}
EOF
  rm -f "$new_agents_file"
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

  print_next_steps
}

main "$@"
