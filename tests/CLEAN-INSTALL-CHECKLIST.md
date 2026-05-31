# Clean-install checklist

Pre-release smoke test that exercises the parts of the plugin
`tests/clean-smoke.sh` *can't* reach: the orchestrator skill's
NL-trigger + `AskUserQuestion` flow inside Claude Code, the approval
gate, and the plugin's marketplace install.

**Run this before tagging any release.** ~15 minutes once the
container is cached + `solid_gemc` is built (otherwise add the
~1.7 GB `.sif` pull + ~5–10 min for two scons builds).

## Prerequisites

- A host with `apptainer`, `wget`, `git`, `python3` on PATH.
  (`tcsh` runs *inside* the container, not on the host.)
- Claude Code with the plugin marketplace feature enabled.
- ~1.7 GB of free disk for the cached `.sif` if a fresh pull is needed,
  plus ~1 GB for a fresh `solid_gemc` clone.
- Either:
  - **(preferred)** the plugin not installed yet on this host — phases
    0–1 cover install from scratch, or
  - the plugin installed previously — phase 0 wipes per-user state to
    simulate a clean install on the same host.

## Phase 0 — Reset state

```bash
# In Claude Code, if the plugin is currently installed:
> /plugin uninstall solid-gemc-claude

# Wipe per-user runtime data:
rm -rf ~/.claude/plugins/data/solid-gemc-claude-solid-gemc-claude
rm -rf ~/.claude/plugins/cache/solid-gemc-claude

# Confirm plugin not registered:
grep -q solid-gemc-claude ~/.claude/plugins/installed_plugins.json \
  && echo "NOT clean" || echo "clean"
```

Pass: `clean`.

## Phase 1 — Install

In Claude Code:

```text
> /plugin marketplace add zhaozhiwen/solid_gemc_claude
> /plugin install solid-gemc-claude@solid-gemc-claude
```

Pass:
- Both commands report success.
- `~/.claude/plugins/cache/solid-gemc-claude/solid-gemc-claude/<version>/.claude-plugin/plugin.json`
  exists; `grep version` matches the tag being released.
- `installed_plugins.json` lists `solid-gemc-claude@solid-gemc-claude`.

## Phase 2 — No hidden session side effects

Open Claude Code in **any** directory.

Pass:
- **No** Python-deps install fires at session start (the plugin ships no
  `SessionStart` hook — the venv installs lazily on the first `analyze`;
  verified in Phase 5).
- No MCP approval prompt fires (the plugin ships no `.mcp.json`).

## Phase 3 — Workspace bootstrap (`bin/solid-gemc-run init`)

```bash
mkdir /tmp/sgc_clean_smoke && cd /tmp/sgc_clean_smoke
```

There are no slash commands — bootstrap via the skill (just describe a run;
it calls `init` in step 3a) or run the wrapper directly. To test init in
isolation, ask Claude to run it:

```text
> Run bin/solid-gemc-run init here.
```

Pass:
- Tool checks succeed for `apptainer`, `git`, `wget`.
- Workspace-common files appear: `CLAUDE.md`, `AGENTS.md`, `.gitignore`,
  `log.md`, `result.md`, `report.html` (no `gcards/`, `runs/`,
  `analysis/` at the workspace root — those live inside each project
  subdir).
- `.sif` lands at `<workspace-root>/cache/sif/jeffersonlab_jlabce_tag2.5_digest:sha256:9b9a9...sif`
  (anchored to the workspace, so it survives plugin updates; confirm via the
  `cache:` line of `bin/solid-gemc-run info`).
- `solid_gemc/` is cloned into the workspace; `git rev-parse HEAD`
  there is reported in the command's final summary.
- Two scons builds complete (first run: several minutes); the binary
  `solid_gemc/source/2.9/solid_gemc` is executable.
- `init` finishes by printing `bin/solid-gemc-run info` (pinned image /
  cache / repo / GEMC version) plus the cloned commit and built binary path.

## Phase 4 — Orchestrator skill drives a simulation

Type a SoLID-flavored NL request:

```text
> Run the heavy-gas Cherenkov study from solid_gemc/analysis/hgc_study, He-3, 10 events, default analysis.
```

Pass:
- Claude auto-loads `skills/solid-gemc` (verifiable by asking it
  which skill it just activated, or by checking the loaded-skills
  indicator).
- The skill captures the **seven-field** spec from the NL request
  (project name + the six physics fields); asks for any missing
  fields via `AskUserQuestion` — in particular, suggests a default
  project name like `hgc_he3_study` and confirms.
- A compact plan is presented for approval.
- On approving, the skill drives:
  - Project seed: `<project>/` appears under the workspace root,
    seeded from `templates/workspace/.` — contains its own
    `CLAUDE.md`, `log.md`, `result.md`, `report.html` (flat — no
    enforced subdirs).
  - GCard copy: `<project>/cherenkov.gcard` appears, with
    live `<gcard>` block containing
    `<option name="OUTPUT" value="evio,out.evio"/>`,
    `<option name="N" value="10"/>`,
    `<option name="USE_GUI" value="0"/>`. The canonical's
    `<!-- comment out … -->` example block is left intact.
  - Run: a new `<project>/runs/<UTC-id>/` directory
    appears containing `gcard.gcard` (frozen), `out.evio`
    (non-empty; from solid_gemc), `out.root` (non-empty; from
    evio2root), `log.txt` (multi-KB; both gemc and evio2root
    output), and `config.json` (records `project`, `sif_name`,
    `solid_gemc_sha`, `gemc_exit_code: 0`, `evio2root_exit: 0`,
    `exit_code: 0`,
    `source_dir: solid_gemc/analysis/hgc_study`).
- A new entry is prepended to `<project>/log.md` with the verbatim
  request, the plan, the decision, and the outcome.
- A one-line entry is appended/prepended to the workspace-level
  `log.md` (cross-project index).

Negative test: in a fresh workspace, type something purely Geant4-y:

```text
> Build a Geant4 simulation of a lead block with 1 GeV electrons.
```

Pass:
- `solid-gemc-claude`'s skill does **not** load (no SoLID vocabulary
  in the request). If `geant4_claude` is also installed, its
  `geant4` skill should load instead. This is the description-match
  arbitration test.

## Phase 5 — Analyze (`bin/solid-gemc-run analyze`)

```text
> Run bin/solid-gemc-run analyze <project>/runs/<UTC-id>
```

Pass:
- On the **first** analyze, the venv installs once
  (`installing Python deps … one-time` → `Python deps ready.`), then the
  command proceeds (this is the lazy install that replaced the old hook).
- The command lists at least one TTree from `out.root` with its
  branches and entry count.
- At least 1 PNG histogram lands in
  `<project>/runs/<UTC-id>/`, named
  `hist_<tree>_<branch>.png` (the wrapper lists them on stdout).

## Phase 6 — Idempotency

Re-run `bin/solid-gemc-run init` in the same workspace:

Pass:
- The command refuses to overwrite without `--force`.
- The `.sif` is not re-downloaded.
- `solid-gemc-run build` is a no-op (scons reports no work) or a
  fast incremental rebuild.

## Phase 7 — Pre-publish leakage scan

On the maintainer's host, with `$USER` expanded:

```bash
grep -RIn "/home/$USER" ~/claude/solid_gemc_claude \
  | grep -Ev '(BUILD_LOG\.md|PLAN\.md|tests/clean-smoke\.sh|\.git/)'
```

Pass: returns nothing.

Also run the automated smoke:

```bash
SGC_REUSE_SIF=<abs path to cached .sif> \
SGC_REUSE_SOLID_GEMC=<abs path to built solid_gemc> \
  tests/clean-smoke.sh
```

Pass: `ALL GREEN — clean smoke passes`.

## When any phase fails

That's a bug in the plugin (not a user error). File against the
relevant phase number; include the run id / cache path / config.json
contents in the report.
