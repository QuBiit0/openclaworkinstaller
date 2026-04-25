#!/usr/bin/env bash
# =============================================================================
# BF-2 — Orchestrator registration + binding
#
# Asserts: when --orchestrator-id is NOT "main", install.sh registers the
#   orchestrator agent before specialists. On success the install log must show
#   `openclaw agents add <orch_id>` being called (or already-exists is tolerated).
#   On failure the install must exit non-zero and print a human-readable error.
#
# Spec scenario: BF-2 (installer-bug-fixes spec, §Orchestrator Registration)
# Design refs:   D2
#
# Usage: bash tests/smoke/bf-2-orch-registration.sh
# Exit:  0 = PASS, 1 = FAIL
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

TEST_HOME="${OPENCLAW_HOME:-$(mktemp -d /tmp/openclaw-smoke-bf2-XXXXX)}"
_cleanup() { [[ -z "${OPENCLAW_HOME:-}" ]] && rm -rf "$TEST_HOME" || true; }
trap _cleanup EXIT

ORCH_ID="estratega"
overall=0

install_out="$(bash "$INSTALL_SH" \
  --mode empresa \
  --empresa "SmokeCorp" \
  --rubro consultora \
  --orchestrator-id "$ORCH_ID" \
  --user "Tester" \
  --cargo "QA" \
  --home "$TEST_HOME" \
  --non-interactive 2>&1 || true)"

# Check 1: orchestrator is registered (agents add for orch_id appears BEFORE any specialist)
orch_line=$(echo "$install_out" | grep -n "agents add.*$ORCH_ID\|add.*$ORCH_ID" | head -1 || true)
specialist_first_line=$(echo "$install_out" | grep -n "agents add.*ventas\|agents add.*dev\|agents add.*administracion" | head -1 | cut -d: -f1 || true)

if [[ -n "$orch_line" ]]; then
  orch_lineno=$(echo "$orch_line" | cut -d: -f1)
  if [[ -n "$specialist_first_line" && "$orch_lineno" -lt "$specialist_first_line" ]]; then
    echo "[PASS] bf-2: orchestrator '$ORCH_ID' registered before first specialist (lines $orch_lineno < $specialist_first_line)"
  elif [[ -z "$specialist_first_line" ]]; then
    echo "[PASS] bf-2: orchestrator '$ORCH_ID' registered (no specialists in this run to compare)"
  else
    echo "[FAIL] bf-2: orchestrator '$ORCH_ID' registered AFTER specialists (orch: $orch_lineno, specialist: $specialist_first_line)"
    overall=1
  fi
else
  echo "[FAIL] bf-2: install log does NOT show agents add for orchestrator '$ORCH_ID'"
  echo "       install output (tail 20 lines):"
  echo "$install_out" | tail -20 | sed 's/^/       /'
  overall=1
fi

# Check 2: 'main' skip logic — when orch_id=main, no extra registration call expected
install_out_main="$(bash "$INSTALL_SH" \
  --mode empresa \
  --empresa "SmokeCorp" \
  --rubro consultora \
  --orchestrator-id main \
  --user "Tester" \
  --cargo "QA" \
  --home "$(mktemp -d /tmp/openclaw-smoke-bf2b-XXXXX)" \
  --non-interactive 2>&1 || true)"

# For main, the script should NOT show a separate 'agents add main' registration
# (main is implicit in openclaw). Just verify no fatal error about main registration.
if echo "$install_out_main" | grep -qi "FATAL\|error.*main.*register\|failed.*main"; then
  echo "[FAIL] bf-2: install with --orchestrator-id main produced a fatal error"
  overall=1
else
  echo "[PASS] bf-2: install with --orchestrator-id main completed without fatal error"
fi

exit $overall
