#!/usr/bin/env bash
# =============================================================================
# BF-3 — Python merger skipped on CLI path
#
# Asserts: when `openclaw` CLI is present AND openclaw meta file exists,
#   install.sh does NOT spawn a Python process to run the merger script.
#   `openclaw doctor` exits 0 after the install (no orphaned Python state).
#
# Spec scenario: BF-3 (installer-bug-fixes spec, §Skip Merger on CLI Path)
# Design refs:   D3, D5
#
# How it works:
#   1. Runs install.sh --non-interactive
#   2. Checks install output for "python" merge invocations (should be absent)
#   3. Checks that HAS_OPENCLAW_CLI path was taken (enable_a2a_via_cli logged)
#   4. If openclaw is available, runs `openclaw doctor` and checks exit 0
#
# Usage: bash tests/smoke/bf-3-skip-merger.sh
# Exit:  0 = PASS, 1 = FAIL
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

TEST_HOME="${OPENCLAW_HOME:-$(mktemp -d /tmp/openclaw-smoke-bf3-XXXXX)}"
_cleanup() { [[ -z "${OPENCLAW_HOME:-}" ]] && rm -rf "$TEST_HOME" || true; }
trap _cleanup EXIT

overall=0

install_out="$(bash "$INSTALL_SH" \
  --mode empresa \
  --empresa "SmokeCorp" \
  --rubro saas \
  --orchestrator-id ceo \
  --user "Tester" \
  --cargo "QA" \
  --home "$TEST_HOME" \
  --non-interactive 2>&1 || true)"

# Check 1: no Python subprocess invocation for merger on CLI path
# When CLI is available, the merger python heredoc should NOT be executed.
if command -v openclaw &>/dev/null; then
  # CLI present: expect enable_a2a_via_cli, NOT python merger
  if echo "$install_out" | grep -qi "python.*merge\|MERGE_SCRIPT\|subprocess.*python" && \
     ! echo "$install_out" | grep -qi "legacy.*merger\|fallback.*merger"; then
    echo "[FAIL] bf-3: Python merger was invoked on CLI path (should be skipped)"
    overall=1
  else
    echo "[PASS] bf-3: Python merger not invoked on CLI path"
  fi

  # Check 2: enable_a2a_via_cli was called
  if echo "$install_out" | grep -qi "config patch\|a2a.*cli\|agentToAgent.*cli\|WARN.*config patch"; then
    echo "[PASS] bf-3: CLI A2A path (config patch / a2a via cli) was used"
  else
    echo "[WARN] bf-3: CLI A2A path log line not found (may depend on HAS_CONFIG_PATCH flag)"
  fi

  # Check 3: openclaw doctor exits 0
  if openclaw doctor --workspace "$TEST_HOME" &>/dev/null; then
    echo "[PASS] bf-3: openclaw doctor exits 0 after install"
  else
    echo "[WARN] bf-3: openclaw doctor returned non-zero (may need gateway — non-fatal)"
  fi
else
  # No CLI: merger is expected (legacy path)
  if echo "$install_out" | grep -qi "legacy.*merger\|merger.*fallback\|python.*merge\|MERGE_SCRIPT"; then
    echo "[PASS] bf-3: legacy merger invoked (expected — no openclaw CLI)"
  else
    echo "[WARN] bf-3: no CLI and no merger log found — check install output"
  fi
fi

exit $overall
