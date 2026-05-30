# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo state

v0.0.4 surface: dual-platform (Claude Code + Codex CLI). There are **no
slash commands** — the whole workflow runs through the `solid-gemc`
orchestrator skill (auto-loads on SoLID-flavored natural language) driving
`bin/solid-gemc-run` (`init` / `analyze` / `setup-python` subcommands). The
earlier `init`/`analyze` slash commands were removed in Phase 21 (BUILD_LOG)
because they were a Claude-only surface that the skill + wrapper already
covered on both platforms.

`PLAN.md` is the **original plan** (generic GEMC plugin); scope has
since shifted to solid_gemc specifically. The post-pivot design spec is
at `~/.claude/plans/cuddly-exploring-crescent.md`; the chronological
build log (locked decisions, bugs/fixes, what's been done) lives in
`BUILD_LOG.md` (gitignored maintainer log).

**Read order for a code-writing task:** `BUILD_LOG.md` first (current
state and locked decisions), then this file (rules + contracts), then
`PLAN.md` only if you need the historical context behind a structural
choice. `PLAN.md` lines about "drop the build subcommand", "pin a
ghcr.io/gemc tag", "NL → GCard" surfaces are all superseded.

## Template repo (read-only reference)

`~/claude/geant4_claude/` is the structural template. The port is mostly
disciplined copy-and-adapt, not invention. Key files to read before mirroring:

- `~/claude/geant4_claude/CLAUDE.md` — maintainer rulebook; the non-negotiables
  below are inherited from it.
- `~/claude/geant4_claude/bin/g4run` (commit `33d460d`) — the runtime wrapper
  this repo's `bin/solid-gemc-run` is adapted from. Key deltas: pull
  uses `wget` (not `apptainer pull docker://`); the `build` subcommand
  is **kept and extended** (two scons compiles inside container);
  in-container shell is tcsh (not bash); `validate-gdml` → `validate-gcard`.
- `~/claude/geant4_claude/skills/geant4/SKILL.md` — orchestrator shape for
  `skills/solid-gemc/SKILL.md`.
- `~/claude/geant4_claude/templates/workspace/` — workspace skeleton; adapt to
  GEMC layout (`detectors/` + `gcards/` instead of `src/` + `geometries/` +
  `macros/` + `build/`).
- `~/claude/geant4_claude/tests/{clean-smoke.sh,clean-install-test.sh,CLEAN-INSTALL-CHECKLIST.md}`
  — three-layer test rig.
- `requirements.txt` — Python analysis deps. NOTE: unlike `geant4_claude`, this
  plugin has **no `hooks/` SessionStart hook** (removed for dual-platform
  simplicity). The venv installs lazily on first `analyze` via
  `bin/solid-gemc-run setup-python`; don't re-add a session hook.

Share **patterns**, not code. Each plugin owns its own copy of every file.
Pattern improvements propagate by deliberate sync, not by linking.

## Non-negotiables (inherited from `geant4_claude`)

1. **Single runtime seam.** All `gemc`, `xmllint`, ROOT/uproot invocations go
   through `bin/solid-gemc-run`. Commands and skills never call `apptainer exec`
   (or `singularity`/`docker`) directly.
2. **Pinned image, one source of truth.** The container tag lives only in
   `bin/solid-gemc-run`. Anywhere else that displays it reads from that script. Do
   not hardcode the tag in commands, skills, README, or CI.
3. **No host-side ROOT requirement.** Default analysis path is Python
   (`uproot` + `numpy` + `matplotlib`). Anything needing ROOT runs inside the
   container via `bin/solid-gemc-run root`.
4. **Fresh-clone reproducibility.** Every command must work after `git clone`
   on a machine with apptainer + Python. No reliance on cached state in the
   maintainer's `$HOME` or absolute `/home/$USER` paths.
5. **No leakage.** No JLab-internal hostnames, no absolute home paths, no API
   tokens, no personal email in committed files. The one allowed exception is
   `gemc.jlab.org` as a documentation reference URL — call this out in any new
   doc that uses it.
6. **Idempotent operations.** Running anything twice must not corrupt state.
   `bin/solid-gemc-run init` re-detects existing files and refuses to overwrite
   without `--force`.
7. **Cache resolution, tiered.** `$SOLID_GEMC_CLAUDE_CACHE` →
   `$CLAUDE_PLUGIN_DATA/cache` → `${PLUGIN_ROOT}/cache` (Codex plugin install) →
   `${XDG_CACHE_HOME:-~/.cache}/solid-gemc-claude` (bare shell). Tiers 2 and 3
   co-locate the `.sif` with the plugin install so each harness manages its own
   copy. The Codex tier fires when the wrapper runs from a `~/.codex/plugins/`
   install (detected via `PLUGIN_ROOT`, since Codex exposes no `CLAUDE_PLUGIN_DATA`
   equivalent); the XDG tier is the last resort for a bare git clone — added for
   dual-platform support (see `DUAL_PLATFORM_PLAN.md`). When `CLAUDE_PLUGIN_DATA`
   **is** set we stay strictly inside it (no `$HOME` fallback), so the plugin's
   own `.sif` is never shadowed by a phantom re-download. Venv resolution
   mirrors this: `$CLAUDE_PLUGIN_DATA/venv` → `${PLUGIN_ROOT}/venv` (Codex) →
   `${XDG_DATA_HOME:-~/.local/share}/solid-gemc-claude/venv`.

## Naming

| Surface | Form |
|---|---|
| Plugin name (Claude Code + Codex spec) | `solid-gemc-claude` — kebab-case, mandatory |
| Claude manifest | `.claude-plugin/plugin.json` |
| Codex manifest | `.codex-plugin/plugin.json` (mirror; same `name`/`version`) |
| Claude marketplace | `.claude-plugin/marketplace.json` |
| Codex marketplace | `.agents/plugins/marketplace.json` (local-source descriptor; **coexists** with the `.codex-plugin/` manifest — Codex uses this for marketplace discovery and still reads `.codex-plugin/plugin.json` as the manifest) |
| GitHub repo | `solid_gemc_claude` — underscore, mirrors `geant4_claude` |
| Run IDs | `YYYYMMDD-HHMMSS-<6char>` (UTC) |
| Skill dirs | `skills/solid-gemc-<topic>/` (plus the one orchestrator `skills/solid-gemc/`) |

There is **no `commands/` slash-command surface** — removed in Phase 21. Entry
points are the orchestrator skill (natural language) and `bin/solid-gemc-run`.

The name keeps its `-claude` suffix even though the plugin now also targets
Codex CLI — renaming the published repo / marketplace / docs site was judged
not worth the churn (see `DUAL_PLATFORM_PLAN.md`). Treat "claude" in the name as
historical, not a platform restriction.

The orchestrator-vs-reference skill split: only `skills/solid-gemc/SKILL.md` is a
workflow-bearing skill (the full-flow orchestrator). All other skills are
reference material — units, physics list choice, uproot recipes, etc. Don't
add a second workflow skill without a reason comparable to the
auto-load-on-natural-language one.

## Seven-field spec (orchestrator contract)

The `skills/solid-gemc/SKILL.md` orchestrator gap-checks user requests against:

| Field | Example |
|---|---|
| Project name | `pvdis_ld2_aPV` (the `<name>/` subdir under the workspace root) |
| Physics goal | "PVDIS A_PV asymmetry as a function of Q²" |
| SoLID config | "PVDIS, LD2 target, full magnet config" |
| Beam | "11 GeV e- on LD2, 10000 events" |
| GCard | `solid_PVDIS_LD2_moved_full.gcard` (canonical) + parameter overrides |
| Output | "`runs/<id>/out.root`" |
| Analysis | "asymmetry binned in Q²" |

Missing fields → ask via `AskUserQuestion`; present plan; user gate; execute
with stop-on-failure post-condition checks.

## Resolved decisions (phase 0 outcome)

- **Container.** JLabCE 2.5 at
  `http://webhome.phy.duke.edu/~zz81/simg/jeffersonlab_jlabce_tag2.5_digest:sha256:9b9a9ec8c793...sif`.
  Pulled via `wget`, pinned in `bin/solid-gemc-run`. The `geant4_claude`
  image (`ghcr.io/gemc/g4install`) does not contain `gemc`; the JLabCE
  image has Geant4 + the deps to build GEMC and solid_gemc on top.
- **`solid_` directory prefix.** Confirmed correct. Local dir, repo
  name, and both plugin manifests use the
  `solid_gemc_claude` / `solid-gemc-claude` form.
- **Output format.** gemc 2.9 in JLabCE 2.5 writes **EVIO natively
  only** (`-help-output` reports `Supported output: evio, txt`).
  `solid-gemc-run` post-converts the EVIO to ROOT via `evio2root`
  inside the same container, so the analysis path is still uproot.
  Both `out.evio` and `out.root` end up in `runs/<id>/`. HIPO
  deferred past v0.0.4.
- **solid_gemc pin.** Clone HEAD of master; record commit SHA per run
  in `runs/<id>/config.json`. No upstream pin at v0.0.4.
- **GCard surface.** The orchestrator skill copies a canonical GCard
  from `$SoLID_GEMC/script/` (or `…/analysis/*/`) into `gcards/` and
  injects `USE_GUI=0` / `OUTPUT=evio,out.evio` / `N=<n>` on the live
  `<gcard>` block. NL→GCard deferred past v0.0.4.

## v0.0.4 known limitations

- **.sif hosted at Duke webhome.** Personal hosting (no SLA), flagged
  in `README.md` "Known limitations". Revisit before paper citation.
- **No upstream pin for solid_gemc.** Two fresh inits months apart can
  diverge. Recorded per-run.
- **First-run flow points at upstream.** No shipped example command;
  after init, the recommended first run is the upstream HGC study at
  `solid_gemc/analysis/hgc_study/` (which the init clone places in the
  workspace).

## Common commands

```bash
# No slash commands. The orchestrator skill at skills/solid-gemc/SKILL.md
# auto-loads on SoLID-flavored natural-language requests, gap-checks the
# seven-field spec, presents a plan, gates on approval, then drives the run
# through bin/solid-gemc-run. The wrapper is the one seam for everything:

bin/solid-gemc-run init [--force]             # workspace skeleton + pull .sif + clone + 2× scons build
bin/solid-gemc-run analyze <run|id|root> [N]  # host-side uproot plots from out.root (post-converted via evio2root)
bin/solid-gemc-run setup-python               # idempotently install the analysis venv (else lazy on first analyze)
bin/solid-gemc-run pull                       # wget the .sif into cache
bin/solid-gemc-run clone [dest]               # git clone solid_gemc (default: ./solid_gemc)
bin/solid-gemc-run build [dest]               # two scons builds inside container: mod/gemc/2.9 → source/2.9
bin/solid-gemc-run info                       # .sif URL, cache, solid_gemc repo, GEMC_VERSION
bin/solid-gemc-run paths                      # resolved root/cache/data/venv/templates/reference paths
bin/solid-gemc-run shell                      # interactive tcsh in container with env applied
bin/solid-gemc-run exec <cmd...>              # run cmd inside container with env applied
bin/solid-gemc-run root <args...>             # ROOT (-l -b -q) inside container
bin/solid-gemc-run env                        # print the tcsh setenv block
bin/solid-gemc-run validate-gcard <file>      # xmllint a GCard inside container
tests/clean-smoke.sh                          # end-to-end smoke (workspace + image + clone/build + gemc + evio2root + analyze)
```

After `bin/solid-gemc-run init`, the upstream
HGC study at `solid_gemc/analysis/hgc_study/` (cloned into the
workspace by init) is the recommended first run — drive it through the
orchestrator skill in plain language ("run the heavy-gas Cherenkov
study on He-3"), or follow upstream's `run.sh` via
`bin/solid-gemc-run shell`.

## Pre-publish checks

Before the v0.0.4 tag, every item must be clean:

- `grep -RIn "/home/$USER\|jefflab" .` returns nothing in tracked files (with
  `$USER` expanded). `jlab.org` is allowed only as the `gemc.jlab.org`
  documentation reference.
- `grep -RIn "TODO\|FIXME\|XXX" .` reviewed; nothing critical left.
- `bin/solid-gemc-run info` reports the same .sif URL the README claims.
- `tests/clean-smoke.sh` passes on a fresh clone.
- `LICENSE` (MIT) present; `README.md` shows the working smoke flow with real
  output.
- Version in `.claude-plugin/plugin.json` bumped per semver.

## Style

- English only in code, commands, and prose.
- Lead with the conclusion, then the reasoning.
- Default to no comments in code; only add when the *why* is non-obvious.
- Keep command and skill bodies tight. If a section grows past ~40 lines, it
  is probably two things — split it.
- Don't add backwards-compatibility shims, "removed X" placeholders, or
  speculative features. The repo has no users yet; design clean.
