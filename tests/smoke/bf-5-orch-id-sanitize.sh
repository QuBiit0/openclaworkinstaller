#!/usr/bin/env bash
# =============================================================================
# BF-5 — --orchestrator-id validation in non-interactive mode
#
# Asserts:
#   A) Empty --orchestrator-id in --non-interactive mode → exit 1,
#      stderr contains "orchestrator-id"
#   B) Reserved id "main" passed as --orchestrator-id in --non-interactive mode
#      → exit 1, stderr contains "orchestrator-id" or "reserved"
#   C) Valid id "ceo" → install proceeds (exit 0 or only WARN-level errors)
#   D) Invalid id "MAIN" (uppercase) → exit 1
#
# Spec scenario: BF-5 (installer-bug-fixes spec, §Orchestrator ID Validation)
# Design refs:   D8, sanitize_orchestrator_id()
#
# Usage: bash tests/smoke/bf-5-orch-id-sanitize.sh
# Exit:  0 = all checks passed, 1 = any check failed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

overall=0

run_scenario() {
  local label="$1"
  local expect_fail="$2"  # "yes" = expect exit 1; "no" = expect exit 0
  local expect_pattern="$3"
  shift 3
  local args=("$@")

  local tmp_home
  tmp_home="$(mktemp -d /tmp/openclaw-smoke-bf5-XXXXX)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_home'" RETURN

  local out exit_code
  out="$(bash "$INSTALL_SH" \
    --mode empresa \
    --empresa "SmokeCorp" \
    --rubro saas \
    --user "Tester" \
    --cargo "QA" \
    --home "$tmp_home" \
    --non-interactive \
    "${args[@]}" 2>&1)" || exit_code=$?
  exit_code="${exit_code:-0}"

  local status="PASS"

  if [[ "$expect_fail" == "yes" ]]; then
    if [[ "$exit_code" -ne 0 ]]; then
      if [[ -n "$expect_pattern" ]] && ! echo "$out" | grep -qi "$expect_pattern"; then
        echo "[FAIL] bf-5 ($label): exited $exit_code but output missing pattern '$expect_pattern'"
        overall=1
        return
      fi
      echo "[PASS] bf-5 ($label): exited $exit_code as expected — pattern '$expect_pattern' found"
    else
      echo "[FAIL] bf-5 ($label): expected exit 1 but got exit 0"
      echo "       output: $(echo "$out" | tail -5 | sed 's/^/       /')"
      overall=1
    fi
  else
    if [[ "$exit_code" -ne 0 ]]; then
      echo "[FAIL] bf-5 ($label): expected exit 0 but got exit $exit_code"
      echo "       output: $(echo "$out" | tail -5 | sed 's/^/       /')"
      overall=1
    else
      echo "[PASS] bf-5 ($label): exited 0 as expected"
    fi
  fi
}

# A: empty orchestrator-id → should fail with "orchestrator-id" in output
run_scenario "empty-id"   "yes" "orchestrator-id" --orchestrator-id ""

# B: reserved id "main" passed via flag → die() con mensaje "ID 'main' está reservado"
run_scenario "reserved-main" "yes" "reservado\|reserved\|main" --orchestrator-id "main"

# C: valid id "ceo" → should succeed
run_scenario "valid-ceo"  "no"  "" --orchestrator-id "ceo"

# D: uppercase "MAIN" → sanitize() lo lowercasea → "main" → die() con "reservado"
# (no "lowercase" en el mensaje porque el sanitize lo aceptó como lowercase válido y luego
# falló por reserved). Si en algún momento agregamos validación pre-lowercase, este patrón
# debe expandirse a "reservado\|invalid\|lowercase".
run_scenario "uppercase-MAIN" "yes" "reservado\|reserved" --orchestrator-id "MAIN"

exit $overall
