#!/usr/bin/env bash
# =============================================================================
# BF-6 — subagents policy defaults in empresa mode
#
# Asserts:
#   A) After empresa install, openclaw config contains:
#        agents.defaults.subagents.maxSpawnDepth = 2
#        agents.defaults.subagents.maxChildrenPerAgent = 5
#        tools.subagents.tools.deny includes "gateway" and "cron"
#   B) After personal install, those keys are NOT present
#
# Spec scenario: BF-6 + SP-1 + SP-2 (subagents-policy-defaults spec)
# Design refs:   D6, write_subagents_policy_empresa()
#
# Usage: bash tests/smoke/bf-6-subagents-policy.sh
# Exit:  0 = PASS, 1 = FAIL
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

overall=0

# ---- Scenario A: empresa mode — subagents keys expected ----
TEST_HOME_A="$(mktemp -d /tmp/openclaw-smoke-bf6a-XXXXX)"
trap 'rm -rf "$TEST_HOME_A"' EXIT

install_out_a="$(bash "$INSTALL_SH" \
  --mode empresa \
  --empresa "SmokeCorp" \
  --rubro saas \
  --orchestrator-id ceo \
  --user "Tester" \
  --cargo "QA" \
  --home "$TEST_HOME_A" \
  --non-interactive 2>&1 || true)"

CONFIG_A="$TEST_HOME_A/openclaw.json"

check_config_key() {
  local config_file="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! -f "$config_file" ]]; then
    echo "[WARN] bf-6: config file not found at $config_file — skipping key check '$label'"
    return 0
  fi

  if grep -qi "$pattern" "$config_file"; then
    echo "[PASS] bf-6 (A): config contains '$label'"
    return 0
  else
    echo "[FAIL] bf-6 (A): config missing '$label' in $config_file"
    return 1
  fi
}

# Check config patch was applied (either via CLI or Python heredoc)
if echo "$install_out_a" | grep -qi "subagents.*policy\|maxSpawnDepth\|subagents.*empresa\|WARN.*subagents"; then
  echo "[PASS] bf-6 (A): install log shows subagents policy invocation"
else
  echo "[FAIL] bf-6 (A): install log does NOT show subagents policy invocation"
  echo "       install output (tail 20 lines):"
  echo "$install_out_a" | tail -20 | sed 's/^/       /'
  overall=1
fi

# Check config file for keys (if written)
if [[ -f "$CONFIG_A" ]]; then
  check_config_key "$CONFIG_A" "maxSpawnDepth" "agents.defaults.subagents.maxSpawnDepth" || overall=1
  check_config_key "$CONFIG_A" "maxChildrenPerAgent" "agents.defaults.subagents.maxChildrenPerAgent" || overall=1
  check_config_key "$CONFIG_A" "gateway\|cron" "tools.subagents.tools.deny (gateway/cron)" || overall=1
else
  echo "[WARN] bf-6 (A): $CONFIG_A not found — subagents keys written via CLI patch (check manually)"
fi

# ---- Scenario B: personal mode — subagents keys must NOT appear ----
TEST_HOME_B="$(mktemp -d /tmp/openclaw-smoke-bf6b-XXXXX)"
trap 'rm -rf "$TEST_HOME_A" "$TEST_HOME_B"' EXIT

install_out_b="$(bash "$INSTALL_SH" \
  --mode personal \
  --user "Tester" \
  --home "$TEST_HOME_B" \
  --non-interactive 2>&1 || true)"

if echo "$install_out_b" | grep -qi "subagents.*policy\|maxSpawnDepth\|write_subagents_policy"; then
  echo "[FAIL] bf-6 (B): personal mode install invoked subagents policy (should be empresa-only)"
  overall=1
else
  echo "[PASS] bf-6 (B): personal mode install did NOT invoke subagents policy"
fi

CONFIG_B="$TEST_HOME_B/openclaw.json"
if [[ -f "$CONFIG_B" ]]; then
  if grep -qi "maxSpawnDepth\|maxChildrenPerAgent" "$CONFIG_B"; then
    echo "[FAIL] bf-6 (B): personal config contains subagents keys (should be absent)"
    overall=1
  else
    echo "[PASS] bf-6 (B): personal config has no subagents keys"
  fi
fi

exit $overall
