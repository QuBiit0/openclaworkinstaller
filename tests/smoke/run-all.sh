#!/usr/bin/env bash
# =============================================================================
# run-all.sh — Umbrella smoke test runner
#
# Iterates all bf-*.sh scripts in this directory, runs each one, and prints a
# per-script PASS/FAIL summary. Exits non-zero if any script failed.
#
# Usage: bash tests/smoke/run-all.sh
# Exit:  0 = all passed, 1 = one or more failed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colours (no-op if stdout is not a tty)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

passed=0
failed=0
warned=0
results=()

echo "======================================================================"
echo "  OpenClaw Workspace Installer — Smoke Test Suite"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================================"
echo ""

# Run each bf-*.sh script
for script in "$SCRIPT_DIR"/bf-*.sh; do
  [[ -f "$script" ]] || continue
  name="$(basename "$script")"

  echo "----------------------------------------------------------------------"
  echo "  Running: $name"
  echo "----------------------------------------------------------------------"

  exit_code=0
  bash "$script" 2>&1 || exit_code=$?

  echo ""
  if [[ "$exit_code" -eq 0 ]]; then
    echo -e "${GREEN}[PASS]${NC} $name"
    ((passed++)) || true
    results+=("PASS: $name")
  else
    echo -e "${RED}[FAIL]${NC} $name (exit $exit_code)"
    ((failed++)) || true
    results+=("FAIL: $name (exit $exit_code)")
  fi
  echo ""
done

echo "======================================================================"
echo "  SUMMARY"
echo "======================================================================"
for r in "${results[@]}"; do
  if [[ "$r" == PASS* ]]; then
    echo -e "  ${GREEN}${r}${NC}"
  else
    echo -e "  ${RED}${r}${NC}"
  fi
done
echo ""
echo "  Total: $((passed + failed)) scripts"
echo -e "  ${GREEN}Passed: $passed${NC}"
if [[ "$failed" -gt 0 ]]; then
  echo -e "  ${RED}Failed: $failed${NC}"
else
  echo "  Failed: $failed"
fi
echo "======================================================================"

if [[ "$failed" -gt 0 ]]; then
  echo ""
  echo -e "${RED}SMOKE TEST SUITE FAILED ($failed script(s) failed)${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}SMOKE TEST SUITE PASSED (all $passed scripts passed)${NC}"
  exit 0
fi
