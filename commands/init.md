---
description: Scaffold a solid_gemc workspace, pull the JLabCE 2.5 container, clone and build solid_gemc.
allowed-tools: Bash, Read, Glob, AskUserQuestion
---

# /solid-gemc-claude:init

## Purpose

Bootstrap a fresh solid_gemc workspace in the current directory: scaffold the
workspace-common files, pull the ~1.7 GB JLabCE 2.5 `.sif` (Duke webhome),
`git clone` `JeffersonLab/solid_gemc`, and run the two `scons` builds inside
the container. First run is slow (~10–20 min); reruns are idempotent.

The deterministic work lives in `bin/solid-gemc-run init` (the single
implementation, shared with the Codex/standalone path). This command is the
Claude Code surface: it adds the interactive collision gate, then delegates.

## Inputs

Optional `--force` — overwrite existing workspace-common files. Does **not**
re-clone, rebuild, or touch `solid_gemc/` or any project subdir.

## Steps

1. **Detect collisions** with the workspace-common files:
   ```bash
   ls -A 2>/dev/null \
     | grep -E '^(CLAUDE\.md|AGENTS\.md|\.gitignore|log\.md|result\.md|report\.html)$' \
     || true
   ```
   - If matches exist and `--force` was **not** passed: stop, show the user
     what's there, and use `AskUserQuestion` to confirm re-running with
     `--force`. Do not overwrite without an explicit choice.
   - Otherwise proceed.

2. **Run the bootstrap.** Cache resolves automatically from `CLAUDE_PLUGIN_DATA`:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" init        # add --force if confirmed
   ```
   This scaffolds `CLAUDE.md` + `AGENTS.md` + `.gitignore` + `log.md` +
   `result.md` + `report.html`, then runs `pull` → `clone` → `build`.

3. **Report status**, then tell the user how to start the first project:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" info
   echo "solid_gemc commit: $(cd solid_gemc && git rev-parse HEAD)"
   echo "binary:            $(readlink -f solid_gemc/source/2.9/solid_gemc 2>/dev/null || echo NOT BUILT)"
   ```
   Two ways into a first project:
   - **Path A — orchestrator skill:** just describe the run in plain language
     ("run the heavy-gas Cherenkov study on He-3"); the skill seeds a project
     subdir from `templates/workspace/`, then drives gcard prep → run → analyze.
   - **Path B — upstream flow:** `bin/solid-gemc-run shell`, then inside,
     `cd solid_gemc/analysis/hgc_study` (GCards + run.sh + analysis.C).
   Detector-authoring reference: `solid_gemc/geometry/hgc_moved/` (see its
   `readme.md`). The plugin ships no detector-authoring command — follow upstream.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `missing host tool: apptainer / git / wget` | Host tool not installed. | Install it; rerun. |
| `wget` fails on the `.sif` URL | Duke webhome unreachable. | Retry, or mirror the `.sif` into the cache dir (`bin/solid-gemc-run paths`) and rerun. |
| `scons` fails at `mod/gemc/2.9` or `source/2.9` | Upstream broken on HEAD, or layout changed and `GEMC_VERSION` is stale. | `cd solid_gemc && git log --oneline -10`; pin an earlier SHA and rerun `build`, or bump `GEMC_VERSION` in `bin/solid-gemc-run`. |

## Notes

- Idempotent. Re-run without `--force` skips existing files; with `--force`,
  only the workspace-common files are overwritten. `solid_gemc/` and project
  subdirs are preserved.
- The `.sif` URL, solid_gemc upstream, and `GEMC_VERSION=2.9` are pinned in
  `bin/solid-gemc-run`. Never hardcode them here.
- The per-project template is `templates/workspace/`; copied per project by the
  skill (or `cp -r "${CLAUDE_PLUGIN_ROOT}/templates/workspace/." my_study/`).
