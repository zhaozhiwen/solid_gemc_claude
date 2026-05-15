---
description: Scaffold a solid_gemc workspace, pull the JLabCE 2.5 container, clone and build solid_gemc.
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# /solid-gemc-claude:init

## Purpose

Set up a fresh solid_gemc simulation workspace in the user's current
working directory. First run is **slow** — ~1.7 GB `.sif` download
(JLabCE 2.5 from the Duke webhome), `git clone` of
`JeffersonLab/solid_gemc`, and two `scons` builds inside the
container. Subsequent runs are idempotent: already-done steps are
skipped.

After init the workspace has the four common files (`CLAUDE.md`,
`.gitignore`, `log.md`, `result.md`) plus a built `solid_gemc/`
tree containing the canonical GCards at `solid_gemc/script/` and
the binary at `solid_gemc/source/2.9/solid_gemc`. **No project
subdir is created** — each project is a separate `<name>/`
directory that the user (or the orchestrator skill) materializes
from `templates/workspace/` on demand.

The recommended first thing to run is the **upstream HGC study** at
`solid_gemc/analysis/hgc_study/` — see step 6.

## Inputs

Optional argument: `--force` (overwrite existing workspace-common
files; does **not** re-clone, re-build, or touch any existing
project subdirs).

## Steps

1. **Confirm environment.** Required host tools: `apptainer`, `git`,
   `wget`. (`tcsh` runs *inside* the container — it doesn't need to
   be on the host.) Stop if anything is missing — tell the user what
   to install. Do not proceed.
   ```bash
   for tool in apptainer git wget; do
     command -v "$tool" >/dev/null \
       || { echo "[init] missing host tool: $tool"; exit 1; }
   done
   apptainer --version
   ```

2. **Detect collisions.** List existing entries in `cwd` that the
   workspace-common files would touch:
   ```bash
   ls -A 2>/dev/null \
     | grep -E '^(CLAUDE\.md|\.gitignore|log\.md|result\.md|report\.html)$' \
     || true
   ```
   - **Non-empty and no `--force`:** stop, show the user what's there,
     ask whether to re-run with `--force`.
   - **`--force` passed:** proceed; overwrites `CLAUDE.md`,
     `.gitignore`, `log.md`, `result.md`, `report.html`. `solid_gemc/`
     and any existing project subdirs are left alone.
   - **Empty:** proceed.

3. **Copy the workspace-common files** into `.`. These are the five
   files that apply across all projects in this workspace; they live
   at the top of the plugin's `templates/` directory (the
   `templates/workspace/` subdir is the per-project template, copied
   later by the skill or the user, not by init):
   ```bash
   cp "${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md"    ./CLAUDE.md
   cp "${CLAUDE_PLUGIN_ROOT}/templates/.gitignore"   ./.gitignore
   cp "${CLAUDE_PLUGIN_ROOT}/templates/log.md"       ./log.md
   cp "${CLAUDE_PLUGIN_ROOT}/templates/result.md"    ./result.md
   cp "${CLAUDE_PLUGIN_ROOT}/templates/report.html"  ./report.html
   ```
   The five files:
   - `CLAUDE.md` — workspace-wide rules for future Claude sessions
     (non-negotiables, single-runtime-seam discipline, layout
     description).
   - `.gitignore` — excludes per-project `*/runs/*/`, the
     built `solid_gemc/`, `*.root`, `*.hipo`, `*.evio`,
     `__pycache__/`.
   - `log.md` — workspace-level chronological index (lightweight;
     per-run detail lives in each project's `log.md`).
   - `result.md` — workspace-level results index (lightweight;
     headline numbers and pointers to project `result.md`).
   - `report.html` — workspace-level browser-readable summary
     (project cards + cross-project findings). Self-contained HTML;
     open with `file://…/report.html`.

4. **Pull the runtime image** through the wrapper. This is the only
   sanctioned way to invoke the solid_gemc runtime:
   ```bash
   SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
     "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" pull
   ```
   First-run downloads the JLabCE 2.5 `.sif` (~1.7 GB) from
   `webhome.phy.duke.edu/~zz81/simg/` into
   `${CLAUDE_PLUGIN_DATA}/cache/sif/`. Reruns no-op if the file is
   already present.

5. **Clone and build solid_gemc** in the workspace:
   ```bash
   SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
     "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" clone

   SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
     "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" build
   ```
   - `clone` no-ops if `solid_gemc/.git` already exists.
   - `build` runs two `scons` invocations:
     `solid_gemc/mod/gemc/2.9/` with **`scons OPT=1 LIBRARY=shared -j4`**
     (the `LIBRARY=shared` flag is required — `mod/gemc/2.9/SConstruct`
     gates `libgemc.so` behind it; without it scons builds only the
     per-module `.a` archives and `source/2.9` then fails to link),
     then `solid_gemc/source/2.9/` with `scons OPT=1 -j4`.
     First-run is several minutes; later runs only rebuild changed
     sources.

6. **Report status.** Show the pinned image / cache / repo / version,
   then summarize:
   ```bash
   SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
     "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" info

   echo
   echo "solid_gemc commit: $(cd solid_gemc && git rev-parse HEAD)"
   echo "binary:            $(readlink -f solid_gemc/source/2.9/solid_gemc 2>/dev/null || echo NOT BUILT)"
   ```
   Then tell the user, in this order:
   - workspace-common files written under `cwd`,
   - .sif cached at `${CLAUDE_PLUGIN_DATA}/cache/sif/`,
   - `solid_gemc` commit cloned + binary built,
   - **how to start the first project.** Each project lives in its
     own subdirectory under the workspace. Two ways in:
     ```text
     # Path A — let the orchestrator skill drive it:
     # just describe what you want, e.g. "run the heavy-gas Cherenkov study on He-3".
     # The skill seeds a fresh project subdir from the per-project template,
     # then drives gcard prep → solid_gemc + evio2root → analyze.

     # Path B — follow upstream's flow directly:
     bin/solid-gemc-run shell
     # then inside the container:
     cd solid_gemc/analysis/hgc_study     # GCards + run.sh + analysis.C

     # Path C — start an empty project manually:
     cp -r "${CLAUDE_PLUGIN_ROOT}/templates/workspace/." my_study/
     # then edit my_study/CLAUDE.md; GCards, analysis scripts, and any
     # custom-detector files live flat in my_study/ (no analysis/ or
     # geometry/ subdir — the per-project template is flat)
     ```
     Mention the detector-authoring example as a parallel reference:
     `solid_gemc/geometry/hgc_moved/` (Perl generators + factory
     text files; see its `readme.md`). The plugin does not ship a
     detector-authoring slash command — follow upstream's pattern.

## Outputs

- Workspace under `cwd`: the five workspace-common files
  (`CLAUDE.md`, `.gitignore`, `log.md`, `result.md`, `report.html`).
  No project subdir is auto-created.
- Cached `.sif` at
  `${CLAUDE_PLUGIN_DATA}/cache/sif/jeffersonlab_jlabce_tag2.5_...sif`.
- Cloned + built `solid_gemc/` tree (gitignored). The `solid_gemc`
  binary at `solid_gemc/source/2.9/solid_gemc`.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `missing host tool: apptainer / git / wget` | Required host tool not installed. | Install it; rerun. |
| `wget` fails on the .sif URL | Network or Duke webhome unreachable. | Retry. Workaround: mirror the `.sif` locally with `wget`, drop it at `${CLAUDE_PLUGIN_DATA}/cache/sif/<pinned-name>.sif`, rerun. |
| `git clone` fails | Network or GitHub unreachable. | Retry. |
| `scons` fails at `mod/gemc/2.9` or `source/2.9` | Upstream solid_gemc broken on HEAD of master, or the layout changed and `GEMC_VERSION` in `bin/solid-gemc-run` is stale. | First try `cd solid_gemc && git log --oneline -10` to spot a recent breaking commit; pin with `git checkout <earlier-SHA>` and re-run `bin/solid-gemc-run build`. If `mod/gemc/<v>` no longer exists, bump `GEMC_VERSION` in `bin/solid-gemc-run`. |
| Existing files refuse to be touched | Workspace already initialized. | Re-run with `--force` (only after confirming with the user). |

## Notes

- Idempotent. Re-running in a populated workspace without `--force`
  is a no-op; with `--force`, only the five workspace-common files
  are overwritten. `solid_gemc/` and any project subdirs are
  preserved.
- The `.sif` URL, solid_gemc upstream, and `GEMC_VERSION=2.9` are
  pinned in `bin/solid-gemc-run`. Do not hardcode them here.
- The per-project template is at
  `${CLAUDE_PLUGIN_ROOT}/templates/workspace/` and is copied per
  project by the skill (or by the user via Path C above).
- First-run total time: ~10–20 min (image pull + clone + two scons).
  Subsequent: seconds.
