# Changelog

All notable changes to this project will be documented in this file.

Format: `[version] — YYYY-MM-DD` / sections: Fixed · Added · Changed

---

## [2.3.0] — 2026-04-25

### Fixed

- **BF-1** — Display name now set via `openclaw agents set-identity --name` (preserves integrity signature). Probes `--name`, `--display-name`, `--label` flags in order; prints WARN and continues if none found on older CLIs.
- **BF-2** — Non-main orchestrator is now registered with `openclaw agents add <orch_id>` BEFORE specialist agents are added. Previously the orchestrator was silently skipped when `orch_id != main`, causing it to never appear in `agents list --bindings`.
- **BF-3** — Python merger is now skipped on the CLI path. `enable_a2a_via_cli` is called instead of the Python heredoc when `openclaw` CLI is present and `HAS_OPENCLAW_META=1`. Python merger is preserved as a fallback for legacy environments (no CLI or no meta file).
- **BF-4** — `--from-identity` flag gated on IDENTITY.md fill state. Uses backtick-bracket heuristic (counts lines matching `` `[...] `` patterns); skips flag when ≥ 5 unfilled placeholders remain.
- **BF-5** — `--orchestrator-id` now validated via `sanitize_orchestrator_id()`: enforces `^[a-z][a-z0-9_-]{1,31}$`, rejects empty string and reserved id `main`. In `--non-interactive` mode exits 1 with error message containing "orchestrator-id"; in interactive mode re-prompts until valid.
- **BF-6** — Subagents policy defaults written to config in empresa mode: `agents.defaults.subagents.maxSpawnDepth=2`, `agents.defaults.subagents.maxChildrenPerAgent=5`, `tools.subagents.tools.deny=["gateway","cron"]`. Skipped (WARN) on CLI < 2026.4.23.

### Added

- **SP-1** — `write_subagents_policy_empresa()` helper: aplica los tres defaults requeridos (`maxSpawnDepth=2`, `maxChildrenPerAgent=5`, `tools.subagents.tools.deny=["gateway","cron"]`) via `openclaw config patch --merge` en path CLI; extiende el Python MERGE_SCRIPT en path fallback; no-op en modo personal.
- **SP-2** — Gate de versión: la subagents policy solo se escribe si `cli_version_gte 2026.4.23` retorna true. CLIs anteriores reciben WARN explícito ("subagents policy skipped — versión detectada no soporta config patch --merge") y la instalación continúa sin la política.
- **ST-1** — Smoke test post-instalación (`post_install_smoke_test`): corre `openclaw doctor` (10s timeout), `openclaw agents list` (5s) y bindings check (5s, solo empresa). Output formato `[PASS|WARN|FAIL] <check>: <detail>`. **No bloqueante** — el installer siempre termina con exit 0.
- **ST-2** — Banner agregado: `[✓]` (verde, todo OK), `[⚠]` (amarillo, warnings), `[✗]` (rojo, fallos críticos), según el peor resultado observado entre los checks.
- `tests/smoke/` — Scripts de regresión runnable por maintainers (6 scripts por-BF + umbrella runner). Sin dependencia de bats. Plain bash, exit 0 = PASS.
- Feature flag detection (`detect_openclaw_features`): probea `openclaw <subcmd> --help` para setear `HAS_SET_IDENTITY_NAME`, `HAS_CONFIG_PATCH`, `SET_IDENTITY_NAME_FLAG` (probe 3-flag: `--name` → `--display-name` → `--label`).
- Legacy merger gate (`should_use_legacy_merger`): salta el Python merger cuando hay CLI presente Y el config tiene `meta` (firma de integridad).

### Changed

- Compatibility bumped to OpenClaw CLI **2026.4.23+** (was 2026.4.15+).
- Python merger (`MERGE_SCRIPT`) now a last-resort path, not the default path.
- Version: `install.sh` → `2.3.0`, `install.ps1` `$WRAPPER_VERSION` → `2.3.0`.

---

## [2.2.0] — 2026-04-21

- feat: usar openclaw CLI (`agents add`) como path principal para registro de agentes
- fix: preservar config ante fallos — backup timestamped antes de cualquier escritura
- fix(ps1): rechazar stub de WSL sin distro + mensaje claro de instalacion
- fix(ps1): pausa al final cuando se ejecuta via `irm | iex`
- fix(ps1): remover ValidateSet que rompia `irm | iex` sin args
- chore(ps1): agregar `$WRAPPER_VERSION` explícito al wrapper

---

## [2.1.0] — 2026-04-21

- initial: openclaw workspace installer v2.1.0
- Wizard interactivo + modo `--non-interactive`
- Soporte empresa y personal
- Merge inteligente con `openclaw.json` existente (Python heredoc)
- Catálogo de 16 rubros con áreas sugeridas
- Auto-binding del orquestador al canal detectado
- Plantillas en español: AGENTS.md, SOUL.md, BOOTSTRAP.md, IDENTITY.md, USER.md
- Apéndices de rol por área (21 áreas)
- Backup timestamped antes de sobrescribir archivos
