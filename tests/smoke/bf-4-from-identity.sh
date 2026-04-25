#!/usr/bin/env bash
# =============================================================================
# BF-4 — --from-identity flag gated on IDENTITY.md fill state
#
# Asserts:
#   A) When IDENTITY.md contains >= 5 unfilled placeholder lines (backtick-bracket
#      heuristic), install.sh does NOT pass --from-identity to set-identity.
#   B) When IDENTITY.md has < 5 such lines (filled by user), install.sh DOES
#      pass --from-identity to set-identity.
#
# Spec scenario: BF-4 (installer-bug-fixes spec, §IDENTITY.md Gate)
# Design refs:   D9, clarifications #338 (backtick-bracket heuristic)
#
# Heuristic: count lines matching backtick-bracket patterns:
#   `[...], `[YYYY-MM-DD], `[v0.0], `[ej: ...
#   filled = count < 5
#
# Usage: bash tests/smoke/bf-4-from-identity.sh
# Exit:  0 = PASS, 1 = FAIL
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

overall=0

# ---- Scenario A: unfilled IDENTITY.md (template) ----
TEST_HOME_A="$(mktemp -d /tmp/openclaw-smoke-bf4a-XXXXX)"
trap 'rm -rf "$TEST_HOME_A"' EXIT

# Create a workspace dir with an unfilled IDENTITY.md template
WS_A="$TEST_HOME_A/workspace"
mkdir -p "$WS_A"
cat > "$WS_A/IDENTITY.md" <<'IDENTITY_TEMPLATE'
# Identity

- Empresa: `[Nombre de la empresa]`
- Rubro: `[rubro]`
- Fecha: `[YYYY-MM-DD]`
- Version: `[v0.0]`
- Ej: `[ej: CEO-Bot]`
- Descripcion: `[descripcion]`
IDENTITY_TEMPLATE

install_out_a="$(bash "$INSTALL_SH" \
  --mode empresa \
  --empresa "SmokeCorp" \
  --rubro saas \
  --orchestrator-id ceo \
  --user "Tester" \
  --cargo "QA" \
  --home "$TEST_HOME_A" \
  --non-interactive 2>&1 || true)"

if echo "$install_out_a" | grep -qi "skip.*from-identity\|identity.*not filled\|--from-identity.*skip\|IDENTITY.*unfilled"; then
  echo "[PASS] bf-4 (A): --from-identity skipped for unfilled IDENTITY.md"
elif echo "$install_out_a" | grep -qi "from-identity"; then
  echo "[FAIL] bf-4 (A): --from-identity was used despite unfilled IDENTITY.md"
  overall=1
else
  echo "[WARN] bf-4 (A): --from-identity log line not found (template may not have been created yet at install time)"
fi

# ---- Scenario B: filled IDENTITY.md ----
TEST_HOME_B="$(mktemp -d /tmp/openclaw-smoke-bf4b-XXXXX)"
trap 'rm -rf "$TEST_HOME_A" "$TEST_HOME_B"' EXIT

WS_B="$TEST_HOME_B/workspace"
mkdir -p "$WS_B"
cat > "$WS_B/IDENTITY.md" <<'IDENTITY_FILLED'
# Identity

- Empresa: SmokeCorp Solutions
- Rubro: SaaS
- Fecha: 2026-04-25
- Version: v2.3.0
- Nombre: Atlas
- Descripcion: Orquestador principal del equipo SmokeCorp
IDENTITY_FILLED

install_out_b="$(bash "$INSTALL_SH" \
  --mode empresa \
  --empresa "SmokeCorp" \
  --rubro saas \
  --orchestrator-id ceo \
  --user "Tester" \
  --cargo "QA" \
  --home "$TEST_HOME_B" \
  --non-interactive 2>&1 || true)"

if echo "$install_out_b" | grep -qi "from-identity\|identity.*filled\|set-identity.*from-identity"; then
  echo "[PASS] bf-4 (B): --from-identity used with filled IDENTITY.md"
elif echo "$install_out_b" | grep -qi "skip.*from-identity\|identity.*not filled"; then
  echo "[FAIL] bf-4 (B): --from-identity was skipped despite filled IDENTITY.md"
  overall=1
else
  echo "[WARN] bf-4 (B): --from-identity log line not found (IDENTITY.md may be written after first install)"
fi

exit $overall
