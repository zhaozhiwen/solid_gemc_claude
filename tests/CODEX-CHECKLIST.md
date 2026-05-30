# Codex CLI manual checklist

`tests/clean-smoke.sh` covers the platform-neutral plumbing
(`bin/solid-gemc-run` + workspace template + run loop + analyze) with no
harness in the loop. This checklist covers what only a real **Codex CLI**
session exercises: plugin install, skill auto-activation, and the approval
gate. Run it on a host with apptainer + git + wget + python3.

> Cannot be automated here — Codex is interactive. Tick each box by hand.

> **Sandbox caveat (verified 2026-05-29):** apptainer does **not** run under
> Codex's `workspace-write` sandbox (`socket communication error: getsockopt:
> operation not permitted`). The container steps (`validate-gcard`, the gemc +
> evio2root run) must run **outside** the sandbox — approve Codex's per-command
> escalation prompt, or launch with a full-access policy. Skill load, planning,
> the approval gate, project scaffolding, and gcard prep all work under the
> sandbox; only the apptainer calls need the escalation.

## 1. Install

- [ ] `codex plugin marketplace add zhaozhiwen/solid_gemc_claude` then
      `codex plugin add solid-gemc-claude@solid-gemc-claude`; confirm it caches
      under `~/.codex/plugins/cache/…` and the bundled `solid-gemc` skill loads
      (ask "is the solid-gemc skill available?"). **No YAML load error** in the
      logs (frontmatter must be strict-YAML clean — CI lint guards this).
- [ ] `solid-gemc-run` resolves: either `command -v solid-gemc-run` succeeds,
      or symlink it (`ln -s <cache>/bin/solid-gemc-run ~/.local/bin/`). The skill
      falls back to `command -v solid-gemc-run` when `CLAUDE_PLUGIN_ROOT` is unset.
- [ ] `AGENTS.md` is present in the installed plugin as a **real file** (it is
      the canonical source; `CLAUDE.md` is a symlink → `AGENTS.md` that
      `codex plugin add` drops — harmless, Codex reads `AGENTS.md`).
- [ ] No hook-trust prompt at session start (the plugin ships no hooks; the
      venv installs lazily on first `analyze`).

## 2. Skill auto-activation

- [ ] Plain-language request — "run the PVDIS A_PV study on LD2 at 11 GeV" —
      activates the `solid-gemc` skill (not a generic response).
- [ ] The skill resolves `$SGC_RUN` and `$SGC_ROOT` (no `CLAUDE_PLUGIN_*`
      errors) and prints the seven-field plan.

## 3. Approval gate (no AskUserQuestion on Codex)

- [ ] The gate appears as an explicit numbered **Approve / Edit / Plan-only**
      question — not prose ending in "let me know."
- [ ] Picking "Plan only" writes **no** files. Picking "Approve" proceeds.
- [ ] No artifact is created before an explicit approval in the same turn.

## 4. End-to-end run

- [ ] First run triggers `init` (workspace scaffold drops both `CLAUDE.md` and
      `AGENTS.md`; `.sif` pulled; `solid_gemc` cloned + built).
- [ ] The simulation produces `<project>/runs/<id>/{gcard.gcard, out.evio,
      out.root, log.txt, config.json}`.
- [ ] `analyze` installs the venv lazily on first use (no `SessionStart` hook
      on Codex), under the Codex plugin install
      (`$CODEX_HOME/plugins/cache/solid-gemc-claude/solid-gemc-claude/<ver>/venv`;
      `CODEX_HOME` defaults to `~/.codex` but may be a custom dir), and writes
      PNGs into the run dir.
- [ ] `<project>/log.md` gets the four-section verbatim entry (user input →
      plan → decision → outcome).

## 5. Path hygiene

- [ ] Cache (the `.sif`) landed under the Codex plugin install
      (`$CODEX_HOME/plugins/cache/solid-gemc-claude/solid-gemc-claude/<ver>/cache/sif`),
      **not** in `~/.cache` or `$HOME` root. This is the regression from the
      2026-05-30 field report: a custom `CODEX_HOME` (e.g. `…/codex_home`, no
      leading dot) used to miss the Codex tier and fall to `~/.cache`. Confirm
      with `solid-gemc-run info` — cache line tagged `[Codex plugin install …]`,
      not `[XDG/home fallback …]`.
- [ ] Re-running `init` is idempotent (existing files skipped without `--force`).
