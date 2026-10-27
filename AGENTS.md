# AGENTS.md

Maintainer rules for this repository. Edit `AGENTS.md` (Codex reads it); `CLAUDE.md`
is the one-line import `@AGENTS.md` for Claude Code, here and in `templates/`.

## Repo state

v0.0.12, dual-platform (Claude Code + Codex CLI). No slash commands and no hooks:
the `solid-gemc` skill (auto-loads on SoLID-flavored natural language) drives
`bin/solid-gemc-run`; `bin/solid-gemc-run help` lists its subcommands.

**Read order for a code-writing task:** `BUILD_LOG.md` (current state, locked
decisions, history), then this file, then `PLAN.md` (the original, superseded plan)
only for the history behind a structural choice. Known issues no test fails on yet
live in `BACKLOG.md`; remove an item once it is fixed. All three are gitignored.
User-facing design and decisions: `docs/DESIGN.md`; known limitations: `README.md`.

**Template repo.** [`zhaozhiwen/geant4_claude`](https://github.com/zhaozhiwen/geant4_claude)
is the structural template this plugin was ported from — clone it to compare.
Share patterns, not code: copy-and-modify is fine (note it in BUILD_LOG); never
call or source its code. Each plugin owns its own copy of every file.

## Non-negotiables

1. **Single runtime seam.** Every container invocation (`gemc`, `xmllint`, ROOT,
   `evio2root`, scons) goes through `bin/solid-gemc-run`. The skill never calls
   `apptainer exec` (or `singularity`/`docker`) directly.
2. **Pinned image, one source of truth.** The container tag lives only in
   `bin/solid-gemc-run`; `info` prints it from there. The one exception is the
   README's download link, kept equal by a pre-publish check. Never put the tag in
   the skill, templates, or CI.
3. **No host-side ROOT requirement.** Default analysis runs ROOT inside the
   container (`analyze`, `.C` macros via `bin/solid-gemc-run root`); that ROOT has
   no PNG writer, so plots are SVG/PDF. Host Python (`analyze --python`) is an
   option, never required.
4. **Fresh-clone reproducibility.** Every command works after `git clone` on a
   machine with apptainer + Python 3 (stdlib; packages only for
   `analyze --python`). No reliance on the maintainer's `$HOME` or absolute paths.
5. **No leakage.** No JLab-internal hostnames, absolute home paths, API tokens or
   personal email in committed files. Allowed: `gemc.jlab.org` as a documentation
   reference URL (call it out in any new doc that uses it), and the upstream links
   inside the `reference/` mirrors of published JLab documents.
6. **Idempotent operations.** Running anything twice must not corrupt state;
   `init` re-detects existing files and refuses to overwrite without `--force`.
7. **Image cache = the running agent tool's plugin data dir**
   (`<tool-home>/plugins/data/solid-gemc-claude-solid-gemc-claude/cache/sif/`),
   shared by all workspaces and kept across plugin updates. No override, no
   workspace copy. A plain terminal (or a nested session) uses an image already
   there read-only and never downloads. Detection and the reasons are in the
   comments at the top of `bin/solid-gemc-run`. The venv is
   `<workspace-root>/venv`; `init` writes the workspace launcher
   `bin/solid-gemc-run`; the skill keeps its own lookup (`${CLAUDE_PLUGIN_ROOT}`
   is the exact install).

## Naming

| Surface | Form |
|---|---|
| Plugin name (Claude Code + Codex) | `solid-gemc-claude` — kebab-case, mandatory; "claude" is historical, not a platform restriction |
| Manifests | `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` (same `name`/`version`) |
| Marketplaces | `.claude-plugin/marketplace.json`; `.agents/plugins/marketplace.json` (Codex discovery; it still reads `.codex-plugin/plugin.json`) |
| GitHub repo | `solid_gemc_claude` — underscore, mirrors `geant4_claude` |
| Run IDs | `YYYYMMDD-HHMMSS-<6char>` (UTC) |
| Skills | `skills/solid-gemc/` is the one workflow skill; reference material goes in `reference/`. A second workflow skill needs a reason comparable to auto-loading. |

The orchestrator contract — the seven-field spec, the gated init (Step 0) and the
approval gate — lives in `skills/solid-gemc/SKILL.md`. Changing it needs a basic test.

## Tests

`tests/quick-test.sh`, `tests/basic-test.sh setup|verify|cleanup` and
`tests/full-test.sh setup|verify|cleanup` each install the plugin into a clean Claude
Code and Codex in a throwaway sandbox; details and costs in `tests/README.md`. The
quick and basic tests need a built gitignored clone at `templates/solid_gemc`
(`bin/solid-gemc-run clone templates/solid_gemc && bin/solid-gemc-run build templates/solid_gemc`)
and find the `.sif` via `$SGC_SIF`, `templates/` (gitignored) or the real plugin
data dir.

- **Quick test: agents decide** — after a change that can affect install or runtime
  (`bin/`, `templates/` files other than text, the skill's commands, `tests/`) and
  before proposing a commit; skip text-only edits; batch edits into one run.
- **Basic test: agents suggest** it after changes to `skills/` or the orchestrator
  flow, with the reason, and run it only when the maintainer says so. When running
  it, write 1–3 probe questions aimed at what changed since the last basic test
  (`SGC_PROBES=<file>`, format in `tests/probes.md`); otherwise one random pool probe.
- **Full test: agents never run it** — they recommend it (before a release; after
  changes to install, image download, `init`/build, or the skill flow).
- Report the slow steps from `.test-cache/timing/` with the result. Read only a
  test's summary; triage failures with a fresh subagent on the kept sandbox
  (`SGC_KEEP=1` keeps it on success too).
- No manual checklists: automate an item from `tests/README.md` "Not covered yet"
  before adding a checklist back.

## Pre-publish checks

Before a tag, every item must be clean:

- `git grep -nE "jlab\.org|/home/$USER|~/clau[d]e" -- ':!reference/' | grep -v 'gemc\.jlab\.org'`
  returns nothing (non-negotiable 5).
- `grep -RIn "TODO\|FIXME\|XXX" .` reviewed; nothing critical left.
- `bin/solid-gemc-run info` reports the same .sif URL the README claims.
- `tests/quick-test.sh` passes.
- `tests/full-test.sh` passes after the push, before tagging (both subagent
  verdicts `OVERALL: PASS`, `verify` → `RESULT: PASS`).
- `LICENSE` (MIT) present; `README.md` shows the working flow (install → first
  run → where results land). No pasted run output in the README.
- Version bumped per semver in both `.claude-plugin/plugin.json` and
  `.codex-plugin/plugin.json`.

## Style

- English only in code, commands, and prose.
- Lead with the conclusion, then the reasoning.
- Default to no comments in code; only add when the *why* is non-obvious.
- Keep command and skill bodies tight. If a section grows past ~40 lines, it is
  probably two things — split it.
- Don't add backwards-compatibility shims, "removed X" placeholders, or
  speculative features. The repo has no users yet; design clean.
