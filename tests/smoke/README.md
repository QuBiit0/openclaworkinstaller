# Smoke Tests — OpenClaw Workspace Installer

Maintainer-runnable regression scripts that exercise each bug-fix scenario after a real install.

## Purpose

These are **plain bash scripts** (no bats dependency, per design D10). They are intended to be run manually by maintainers before tagging a release, from a clean Windows VM or Linux/macOS machine that already has the `openclaw` CLI installed and configured.

Each script:
- Targets one specific Bug Fix (BF) or Stability Point (SP) from the v2.3.0 spec
- Prints one line per check in the format: `[PASS|FAIL] <bf-id>: <detail>`
- Exits 0 on PASS, non-zero on FAIL
- Is self-contained and runs standalone with `bash tests/smoke/bf-N-*.sh`

## Requirements

- `openclaw` CLI installed (`npm install -g openclaw`)
- `openclaw setup` already run (workspace installer needs an existing config)
- `OPENCLAW_HOME` environment variable pointing to a temp/test directory (recommended)
- Bash 4.0+

## Running

### All scripts (recommended)

```bash
bash tests/smoke/run-all.sh
```

### Individual script

```bash
bash tests/smoke/bf-1-display-name.sh
bash tests/smoke/bf-5-orch-id-sanitize.sh
```

## Scripts

| Script | BF/SP | What it tests |
|--------|-------|---------------|
| `bf-1-display-name.sh` | BF-1 | `agents list` shows expected display name after empresa install |
| `bf-2-orch-registration.sh` | BF-2 | Non-main orchestrator is registered and bound before specialists |
| `bf-3-skip-merger.sh` | BF-3 | CLI path does NOT invoke Python merger (`openclaw doctor` exits 0) |
| `bf-4-from-identity.sh` | BF-4 | `--from-identity` flag gated on IDENTITY.md fill state |
| `bf-5-orch-id-sanitize.sh` | BF-5 | Empty `--orchestrator-id` in non-interactive mode → exit 1 with "orchestrator-id" in stderr |
| `bf-6-subagents-policy.sh` | BF-6 | Config has `agents.defaults.subagents.maxSpawnDepth=2` after empresa install |
| `run-all.sh` | ALL | Umbrella runner — prints per-script PASS/FAIL + summary |

## Design Notes (D10)

- No bats, no external test framework — pure bash assertions
- `OPENCLAW_HOME` override allows running against isolated directories
- Scripts do NOT modify the caller's real `~/.openclaw` when `OPENCLAW_HOME` is set
- All scripts source helpers from `install.sh` using `INSTALL_SH_SOURCE_ONLY=1 source install.sh`
  when possible; otherwise they call `install.sh` as a subprocess with `--non-interactive`
