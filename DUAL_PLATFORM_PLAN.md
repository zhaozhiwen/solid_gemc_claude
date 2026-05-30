# Dual-platform plan — Claude Code + Codex CLI

## Context

`solid-gemc-claude` began as a Claude Code plugin. The goal is to make the
**same single repo** drive the identical solid_gemc workflow on two agentic
CLIs: **Claude Code** and **OpenAI Codex CLI**. (Antigravity deferred — not in
scope.)

The model is **obra/superpowers**, which ships one repo across many harnesses:
- One canonical `skills/` dir, platform-agnostic skill bodies — single source of
  truth shared by every platform.
- Per-platform manifest dirs side by side: `.claude-plugin/plugin.json` and
  `.codex-plugin/plugin.json`.
- Per-platform root instruction files: `CLAUDE.md` (Claude) and `AGENTS.md`
  (Codex), same content, each harness reads its own filename.

The enabling facts: the orchestrator skill is already in the Agent Skills
standard format Codex consumes, and `bin/solid-gemc-run` is pure bash. **Codex
installs the plugin** (cached at `~/.codex/plugins/cache/`, the way Claude caches
at `~/.claude/plugins/cache/`), so the skill ships *bundled inside the plugin* —
no manual skill symlink. This is adapter work + path generalization, not a
rewrite.

### Locked decisions
1. **Keep the name** `solid-gemc-claude` / `solid_gemc_claude`. The "claude"
   suffix becomes a historical artifact; README reframes as "Claude Code + Codex."
2. **Wrapper owns the workflow.** `init` / `analyze` logic moves into
   `bin/solid-gemc-run` subcommands so both platforms run identical bash.
3. **Documented install** (no `install.sh`): the Codex install is the plugin
   install command, documented in README. The superpowers marketplace-sync script
   is the future publishing path, not built now.

This supersedes `CODEX_PORT_PLAN.md` (predates v0.0.3; assumed Codex tool
mappings were uncertain — now confirmed).

### Discovery matrix (verified)

| Concern | Claude Code | Codex CLI |
|---|---|---|
| Manifest | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` |
| Install | marketplace `/plugin install` → `~/.claude/plugins/cache/` | Codex plugin install → `~/.codex/plugins/cache/` |
| Skill discovery | bundled `skills/` in the installed plugin | bundled `skills/` in the installed plugin |
| Project rules file | `CLAUDE.md` (symlink → `AGENTS.md`) | `AGENTS.md` (real, canonical) |
| Activation | auto by description | auto by description; `/skills`; `$mention` |
| Lifecycle hook | none — venv installs lazily on first `analyze` | none — same |
| Runtime seam | `bin/solid-gemc-run` | identical |

## Architecture (the unifying move)

`bin/solid-gemc-run` becomes the **single workflow owner**; everything else is a
thin adapter that calls it.

```
                 bin/solid-gemc-run  (pure bash, platform-neutral)
                 init │ analyze │ setup-python │ pull/clone/build/exec/…
                        ▲            ▲              ▲
        ┌───────────────┴────────────┐              │
   orchestrator skill (SKILL.md)      Codex CLI: .codex-plugin manifest
   one canonical, platform-neutral    Claude Code: .claude-plugin manifest
   (no slash commands — see Phase 21) + AGENTS.md (bundled in plugin)
```

One skill, one workflow implementation, two thin discovery layers. Both
platforms install the plugin and get the bundled skill automatically.

## Workstreams

### A. Generalize path resolution in `bin/solid-gemc-run`
Off Claude, `CLAUDE_PLUGIN_DATA` is unset. Add a Codex-install tier and an
XDG/home tier **only when the Claude var is absent**. Codex exposes no
`CLAUDE_PLUGIN_DATA` equivalent, so detect a Codex install by `PLUGIN_ROOT`
being under `~/.codex/plugins/` and co-locate the artifacts with it (the way
`$CLAUDE_PLUGIN_DATA` does on Claude); a bare git clone falls through to XDG:
- Cache: `$SOLID_GEMC_CLAUDE_CACHE` → `$CLAUDE_PLUGIN_DATA/cache` →
  `${PLUGIN_ROOT}/cache` (Codex) → `${XDG_CACHE_HOME:-~/.cache}/solid-gemc-claude`.
- Venv: `$CLAUDE_PLUGIN_DATA/venv` → `${PLUGIN_ROOT}/venv` (Codex) →
  `${XDG_DATA_HOME:-~/.local/share}/solid-gemc-claude/venv`.

**Conflict surfaced:** CLAUDE.md non-negotiable #7 says "no `$HOME` fallback."
This adds one for off-Claude use. Update #7 to record the exception (strict rule
still holds whenever `CLAUDE_PLUGIN_DATA` is set).

### B. Add workflow subcommands to `bin/solid-gemc-run`
Move the **non-interactive** logic out of the Claude command/hook files:
- `setup-python` — idempotent venv install (extracted from `hooks/install-deps.sh`).
- `init [--force]` — workspace scaffold + `pull` + `clone` + `build`
  (deterministic parts of the former `commands/init.md`).
- `analyze <run-dir|id|path>` — uproot plots; extract the embedded Python into a
  new `bin/solid-gemc-analyze.py` the subcommand calls (reusable by both platforms).

The wrapper stays non-interactive and flag-driven; interactive bits (collision
confirmation, approve/edit gate) stay in the adapter/skill layer.

**Lazy venv (no session hook on any platform):** any python path (`analyze`)
calls `setup-python` internally if the venv is missing, so the first `analyze`
self-ensures it on Claude and Codex alike. Same wrapper, no platform branch.
(A Claude `SessionStart` pre-warm hook was tried and then removed for
simplicity — one install path, not two.)

### C. Make the orchestrator skill platform-neutral
`skills/solid-gemc/SKILL.md`:
- Replace "call `/solid-gemc-claude:init` / `:analyze`" with
  "run `bin/solid-gemc-run init` / `analyze`" (works everywhere).
- Replace `AskUserQuestion` references with neutral phrasing: "ask the user
  (Claude Code: via `AskUserQuestion`; Codex: a plain prompt / `/skills` / `$`)."
  Keep the plan-first + log-every-user-input non-negotiables intact.

### D. Adapter cleanup
> **Phase 21 update:** the `commands/` slash-command surface and the `hooks/`
> directory were both **removed** — the orchestrator skill + `bin/solid-gemc-run`
> cover everything on both platforms. The bullets below describe the
> intermediate "thin caller" step that those removals superseded.

- ~~`commands/init.md` → call `bin/solid-gemc-run init`~~ (commands removed).
- ~~`commands/analyze.md` → call `bin/solid-gemc-run analyze`~~ (commands removed).
- `hooks/` removed entirely — no `SessionStart` hook. The venv installs lazily
  on first `analyze` (the same path Codex/standalone use).

### E. Codex manifest (superpowers-style)
- Add `.codex-plugin/plugin.json` mirroring `.claude-plugin/plugin.json` (name,
  version, description, author, homepage). This makes the repo installable as a
  Codex plugin; once installed Codex caches it at `~/.codex/plugins/cache/…` and
  discovers the bundled `skills/solid-gemc/SKILL.md` automatically — **no manual
  skill symlink**.
- Canonical skill stays at `skills/solid-gemc/` (shared by both plugins, no second
  copy → no drift).
- (Optional, deferred) `skills/solid-gemc/agents/openai.yaml` for richer Codex
  skill metadata — not required for discovery; skip unless needed.
- (Future, not built) the superpowers `sync-to-codex-plugin.sh` marketplace-publish
  path, noted in docs as the scale option.

### F. AGENTS.md is canonical; CLAUDE.md is a symlink to it
`AGENTS.md` is the **real, canonical** project-rules file (root, `templates/`,
`templates/workspace/`); `CLAUDE.md` is a **symlink → `AGENTS.md`** in the same
dir. One source, zero drift by construction.

> **Why this direction** (settled during Codex testing): `codex plugin add`
> copies files and **drops symlinks**. Putting the real bytes in `AGENTS.md`
> (the file Codex reads) means the Codex package keeps it; the dropped
> `CLAUDE.md` symlink is one Codex doesn't need. Claude Code installs via git
> clone, which preserves the symlink, so it reads `CLAUDE.md` through it. (We
> first tried the opposite — real `CLAUDE.md` + copied `AGENTS.md` — but a true
> link is cleaner, and this direction survives both installers.)
> `tests/lint-agents-mirror.sh` enforces it (CI fails if `CLAUDE.md` isn't a
> symlink → `AGENTS.md`, or `AGENTS.md` isn't a real file).

`bin/solid-gemc-run init` copies the templates into the user's workspace with
`cp -L` (dereferences): a Claude clone yields real `CLAUDE.md` + `AGENTS.md`; a
Codex install (symlink already dropped) yields just `AGENTS.md`. Since a user
works one harness per workspace, that asymmetry is fine.

### G. Documentation
- `README.md`: platform-support matrix + "Install on Codex CLI" section (plugin
  install → cached at `~/.codex/plugins/cache`, skill auto-loads, `setup-python`
  self-ensured on first analyze); reframe the name as dual-platform; mention the
  superpowers marketplace-sync as the future publishing path.
- `CLAUDE.md`: update non-negotiable #7 (XDG/home exception); add naming note that
  the name is intentionally kept; add a `.codex-plugin` / Codex row to the naming table.
- `BUILD_LOG.md`: append a phase entry — dual-platform decision, the locked answers,
  the superpowers model reference, the #7 softening, the lazy-venv choice.
- Mark `CODEX_PORT_PLAN.md` superseded by this doc (don't delete — ask first).

### H. Tests & version
- Extend `tests/clean-smoke.sh` to exercise `bin/solid-gemc-run init|analyze|setup-python`
  (covers the shared path with no Claude env present, including lazy-venv ensure).
- Add `tests/CODEX-CHECKLIST.md` — manual plugin install + skill auto-load + run on
  Codex. **Flag:** actual Codex host verification can't run in this environment; manual.
- Bump `.claude-plugin/plugin.json` + `marketplace.json` `0.0.3` → `0.0.4`; set
  `.codex-plugin/plugin.json` to the same `0.0.4`.

## Critical files

| File | Change |
|---|---|
| `bin/solid-gemc-run` | + `init`/`analyze`/`setup-python` subcommands; generalize cache+venv resolution; lazy-venv ensure |
| `bin/solid-gemc-analyze.py` | **new** — extracted uproot plotting helper |
| `skills/solid-gemc/SKILL.md` | platform-neutral phrasing (wrapper calls, neutral "ask user") |
| `commands/` | **removed** (Phase 21) — no slash commands; skill + wrapper only |
| `hooks/` | **removed** — no `SessionStart` hook; venv installs lazily |
| `.codex-plugin/plugin.json` | **new** — Codex manifest mirroring the Claude one |
| `AGENTS.md` ×3 (real, canonical); `CLAUDE.md` ×3 (symlink → `AGENTS.md`) | single-source rules files; guarded by `tests/lint-agents-mirror.sh` |
| `README.md`, `CLAUDE.md`, `BUILD_LOG.md` | docs: matrix, Codex install, #7 exception, phase log |
| `tests/clean-smoke.sh`, `tests/CODEX-CHECKLIST.md`, `tests/lint-*` | cover new subcommands; manual Codex checklist; CI lints |
| `.claude-plugin/plugin.json`, `marketplace.json` | version → 0.0.4 |

## Reuse (don't reinvent)
- Wrapper subcommand dispatch, `--bind`/`--pwd` container invocation, env block:
  add cases to the existing `bin/solid-gemc-run`, don't restructure.
- venv install logic: lives in the wrapper's `setup-python` (uv-or-pip,
  Python 3.9+ guard) — the single install path, invoked lazily by `analyze`.
- uproot plotting: lifted from the former `commands/analyze.md` into `bin/solid-gemc-analyze.py`.
- `evio2root -R=flux` and `LIBRARY=shared` flags: keep — load-bearing.
- Structural model: mirror superpowers' side-by-side manifest dirs + dual root
  rules files; do **not** copy its marketplace-sync script yet.

## Verification
1. **Standalone (no Claude env):** unset `CLAUDE_PLUGIN_*`; run
   `SOLID_GEMC_CLAUDE_CACHE=… bin/solid-gemc-run setup-python`, then `init`, then
   `analyze runs/<id>` — confirm XDG/home resolution and end-to-end output.
2. **Smoke:** `tests/clean-smoke.sh` passes on a fresh clone (also exercising the
   three new subcommands + lazy-venv), reusing `SGC_REUSE_SIF` / `SGC_REUSE_SOLID_GEMC`.
3. **Claude Code:** `/solid-gemc-claude:init` and `:analyze` still work (thin
   callers); the orchestrator skill still auto-loads and drives a run.
4. **Codex (manual):** install the plugin; confirm it caches at
   `~/.codex/plugins/cache/…`, the bundled skill auto-activates on "run the PVDIS
   A_PV study on LD2 at 11 GeV", and the wrapper drives init → run → analyze with
   the venv self-ensured. Track via `tests/CODEX-CHECKLIST.md`.
5. **Leakage gate:** re-run the pre-publish `grep` checks from CLAUDE.md over the
   new files (no home paths, no JLab hostnames).
