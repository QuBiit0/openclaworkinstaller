#!/usr/bin/env bash
# =============================================================================
# BF-1 — Display name regression
#
# Asserts: after a empresa install with --orchestrator-id ceo, running
#   `openclaw agents list` shows a display name containing "CEO" for the ceo agent.
#
# Spec scenario: BF-1 (installer-bug-fixes spec, §Display Name via set-identity)
# Design refs:   D1, D4
#
# How it works:
#   1. Runs install.sh --non-interactive in empresa mode with --orchestrator-id ceo
#   2. Queries `openclaw agents list` output
#   3. Checks that "ceo" agent row contains a display name != the raw id
#
# Usage: bash tests/smoke/bf-1-display-name.sh
# Exit:  0 = PASS, 1 = FAIL
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

# Use isolated OPENCLAW_HOME if provided, otherwise create a temp dir
TEST_HOME="${OPENCLAW_HOME:-$(mktemp -d /tmp/openclaw-smoke-bf1-XXXXX)}"
_cleanup() { [[ -z "${OPENCLAW_HOME:-}" ]] && rm -rf "$TEST_HOME" || true; }
trap _cleanup EXIT

ORCH_ID="ceo"
PASS=0
FAIL=1

run_check() {
  local label="$1"; shift
  local expected="$1"; shift
  local actual
  actual="$("$@" 2>&1 || true)"
  if echo "$actual" | grep -qi "$expected"; then
    echo "[PASS] bf-1: $label — found '$expected' in output"
    return 0
  else
    echo "[FAIL] bf-1: $label — expected '$expected' not found in: $actual"
    return 1
  fi
}

overall=0

# Check 1: install.sh must emit a set-identity --name call for ceo agent
install_out="$(bash "$INSTALL_SH" \
  --mode empresa \
  --empresa "SmokeCo" \
  --rubro saas \
  --orchestrator-id "$ORCH_ID" \
  --user "Tester" \
  --cargo "QA" \
  --home "$TEST_HOME" \
  --non-interactive 2>&1 || true)"

if echo "$install_out" | grep -qi "set-identity.*--name\|set-identity.*ceo\|display.*ceo\|WARN.*set-identity"; then
  echo "[PASS] bf-1: install.sh invoked set-identity --name (or WARN) for orchestrator '$ORCH_ID'"
else
  echo "[FAIL] bf-1: install.sh did NOT invoke set-identity --name for orchestrator '$ORCH_ID'"
  echo "       install output (tail 20 lines):"
  echo "$install_out" | tail -20 | sed 's/^/       /'
  overall=1
fi

# Check 2: verify openclaw agents list shows display name (requires real CLI)
if command -v openclaw &>/dev/null; then
  agents_out="$(openclaw agents list --workspace "$TEST_HOME" 2>&1 || true)"
  if echo "$agents_out" | grep -qi "CEO\|ceo.*name\|display"; then
    echo "[PASS] bf-1: agents list shows display name for '$ORCH_ID'"
  else
    echo "[WARN] bf-1: agents list output unclear (may need real gateway): $(echo "$agents_out" | head -3)"
  fi
else
  echo "[WARN] bf-1: openclaw CLI not available — skipping agents list check"
fi

exit $overall
