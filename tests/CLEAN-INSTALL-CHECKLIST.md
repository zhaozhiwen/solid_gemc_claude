# Clean-install checklist

Pre-release smoke test that exercises the parts of the plugin
`tests/clean-smoke.sh` *can't* reach: Claude Code's slash-command
dispatch, the `SessionStart` hook, the deepwiki MCP approval prompt,
the orchestrator skill's NL-trigger + `AskUserQuestion` flow, and
namespace lookup.

**Run this before tagging any release.** ~15 minutes once the
container is cached + `solid_gemc` is built (otherwise add the
multi-GB `.sif` pull + ~5–10 min for two scons builds).

## Prerequisites

- A host with `apptainer`, `wget`, `git`, `tcsh`, `python3` on PATH.
- Claude Code with the plugin marketplace feature enabled.
- ~5 GB of free disk for the cached `.sif` if a fresh pull is needed,
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

## Phase 2 — `SessionStart` side effects

Open Claude Code in **any** directory.

Pass:
- Claude Code prompts once to approve the `deepwiki` MCP server.
  Approve it.
- The `SessionStart` hook reports
  `[solid_gemc_claude] installing Python deps into …/venv (one-time, ~30s)…`
  and then `Python deps ready.`
- `~/.claude/plugins/data/solid-gemc-claude-solid-gemc-claude/venv/bin/python -c "import uproot, numpy, matplotlib, pdg"`
  succeeds.
- In Claude Code, `mcp__deepwiki__ask_question` is an available tool.

## Phase 3 — `/solid-gemc-claude:solid-gemc-init`

```bash
mkdir /tmp/sgc_clean_smoke && cd /tmp/sgc_clean_smoke
```

In Claude Code:

```text
> /solid-gemc-claude:solid-gemc-init
```

Pass:
- Tool checks succeed for `apptainer`, `git`, `wget`, `tcsh`.
- Workspace skeleton appears: `CLAUDE.md`, `.gitignore`, `log.md`,
  `result.md`, `gcards/`, `runs/`, `analysis/` (with `.gitkeep`
  placeholders).
- `.sif` lands at
  `~/.claude/plugins/data/solid-gemc-claude-solid-gemc-claude/cache/sif/jeffersonlab_jlabce_tag2.5_digest:sha256:9b9a9...sif`.
- `solid_gemc/` is cloned into the workspace; `git rev-parse HEAD`
  there is reported in the command's final summary.
- Two scons builds complete (first run: several minutes); the binary
  `solid_gemc/source/2.9/solid_gemc` is executable.
- The command's closing summary recommends the upstream HGC study as
  the first thing to try.

## Phase 4 — `/solid-gemc-claude:solid-gemc-config`

```text
> /solid-gemc-claude:solid-gemc-config cherenkov
```

Pass:
- `gcards/cherenkov.gcard` is created.
- `gcards/cherenkov.gcard.source` sidecar contains
  `solid_gemc/analysis/hgc_study`.
- The live `<gcard>` block contains
  `<option name="OUTPUT" value="evio,out.evio"/>`,
  `<option name="N" value="100"/>`, and
  `<option name="USE_GUI" value="0"/>`.
- The comment-block examples at the file's tail are untouched.
- `validate-gcard` reports "well-formed".

## Phase 5 — `/solid-gemc-claude:solid-gemc-run`

Edit the GCard to use a small event count for the smoke (`N=10`),
then:

```text
> /solid-gemc-claude:solid-gemc-run --gcard gcards/cherenkov.gcard
```

Pass:
- A new `runs/<UTC-id>/` directory appears.
- It contains all five expected files:
  - `gcard.gcard` (frozen)
  - `out.evio` (non-empty; from solid_gemc)
  - `out.root` (non-empty; from evio2root)
  - `log.txt` (multi-KB; shows both gemc and evio2root output)
  - `config.json` (records `sif_name`, `solid_gemc_sha`,
    `gemc_exit_code: 0`, `evio2root_exit: 0`, `exit_code: 0`,
    `source_dir: solid_gemc/analysis/hgc_study`)
- A new entry is prepended to `log.md` with the verbatim request, the
  plan, the decision, and the outcome.

## Phase 6 — `/solid-gemc-claude:solid-gemc-analyze`

```text
> /solid-gemc-claude:solid-gemc-analyze runs/<UTC-id>
```

Pass:
- The command lists at least one TTree from `out.root` with its
  branches and entry count.
- At least 1 PNG histogram lands in `runs/<UTC-id>/`, named
  `hist_<tree>_<branch>.png`.
- The closing report points the user at `analysis/` for custom
  scripts.

## Phase 7 — Orchestrator skill auto-load

Restart Claude Code in a fresh directory:

```bash
mkdir /tmp/sgc_orch_smoke && cd /tmp/sgc_orch_smoke
```

Then in Claude Code, type a SoLID-flavored NL request that doesn't
name a slash command:

```text
> Set up a PVDIS LD2 study at 11 GeV, 100 events, default analysis.
```

Pass:
- Claude auto-loads `skills/solid-gemc` (verifiable by asking it which
  skill it just activated, or by checking the loaded-skills indicator).
- The skill captures the six-field spec from the NL request; asks
  for any missing fields via `AskUserQuestion`.
- A compact plan is presented for approval.
- On approving, the skill drives init (skipped since already done in
  phase 3, or fires if this is a fresh host) → config → run → analyze
  with post-condition checks at each step.
- `log.md` and `result.md` get appropriate updates.

Negative test: in a fresh workspace, type something purely Geant4-y:

```text
> Build a Geant4 simulation of a lead block with 1 GeV electrons.
```

Pass:
- `solid-gemc-claude`'s skill does **not** load (no SoLID vocabulary
  in the request). If `geant4_claude` is also installed, its `geant4`
  skill should load instead. This is the description-match arbitration
  test.

## Phase 8 — Idempotency

Re-run `/solid-gemc-claude:solid-gemc-init` in the same workspace:

Pass:
- The command refuses to overwrite without `--force`.
- The `.sif` is not re-downloaded.
- `solid-gemc-run build` is a no-op (scons reports no work) or a
  fast incremental rebuild.

## Phase 9 — Pre-publish leakage scan

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
