---
description: Scaffold a solid_gemc workspace, pull the JLabCE 2.5 container, clone and build solid_gemc.
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# /solid-gemc-claude:solid-gemc-init

## Purpose

Set up a fresh solid_gemc simulation workspace in the user's current
working directory. First run is **slow** — multi-GB `.sif` download,
git clone of `JeffersonLab/solid_gemc`, and two `scons` builds inside
the container. Subsequent runs are idempotent: already-done steps are
skipped.

After init: empty `gcards/`, `runs/`, `analysis/` plus a built
`solid_gemc/` tree containing the canonical GCards at
`solid_gemc/script/` and the binary at `solid_gemc/source/2.9/solid_gemc`.

The recommended first thing to run is the **upstream HGC study** at
`solid_gemc/analysis/hgc_study/` — see step 6.

## Inputs

Optional argument: `--force` (overwrite existing template files; does
**not** re-clone or re-build `solid_gemc/`).

## Steps

1. **Confirm environment.** Required host tools: `apptainer`, `git`,
   `wget`, `tcsh`. Stop if anything is missing — tell the user what to
   install. Do not proceed.
   ```bash
   for tool in apptainer git wget tcsh; do
     command -v "$tool" >/dev/null \
       || { echo "[solid-gemc-init] missing host tool: $tool"; exit 1; }
   done
   apptainer --version
   ```

2. **Detect collisions.** List existing entries in `cwd` that the
   template would touch:
   ```bash
   ls -A 2>/dev/null \
     | grep -E '^(CLAUDE\.md|\.gitignore|gcards|runs|analysis|log\.md|result\.md)$' \
     || true
   ```
   - **Non-empty and no `--force`:** stop, show the user what's there,
     ask whether to re-run with `--force`.
   - **`--force` passed:** proceed; the template overwrites
     `CLAUDE.md`, `.gitignore`, `log.md`, `result.md`, and the empty
     dir placeholders. `solid_gemc/` and `runs/<id>/` contents are
     left alone.
   - **Empty:** proceed.

3. **Copy the workspace template** into `.`:
   ```bash
   cp -r "${CLAUDE_PLUGIN_ROOT}/templates/workspace/." .
   ```
   The template ships:
   - `CLAUDE.md` — workspace rules for future Claude sessions.
   - `.gitignore` — excludes `runs/<id>/`, `*.root`, `*.hipo`,
     `*.evio`, `solid_gemc/`, `__pycache__/`.
   - `log.md` — chronological work-log template (prepend an entry per
     simulation effort; see the file for the six-field-spec section).
   - `result.md` — per-run findings (update after a noteworthy
     `solid-gemc-analyze`).
   - `gcards/.gitkeep`, `runs/.gitkeep`, `analysis/.gitkeep` — empty
     dirs with conventional names the rest of the plugin's commands
     expect.

4. **Pull the runtime image** through the wrapper. This is the only
   sanctioned way to invoke the solid_gemc runtime:
   ```bash
   SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
     "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" pull
   ```
   First-run downloads the JLabCE 2.5 `.sif` (~5 GB) from
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
   - `build` runs both `scons OPT=1 -j4` invocations
     (`solid_gemc/mod/gemc/2.9/` first, then `solid_gemc/source/2.9/`).
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
   - workspace files written under `cwd`,
   - .sif cached at `${CLAUDE_PLUGIN_DATA}/cache/sif/`,
   - `solid_gemc` commit cloned + binary built,
   - **what to try first** — recommend the upstream HGC study:
     ```text
     bin/solid-gemc-run shell
     # then inside the container:
     cd solid_gemc/analysis/hgc_study
     # follow the README — it ships canonical GCards, run.sh, and analysis.C
     ```
     Mention the plugin's own loop as the alternative:
     `/solid-gemc-claude:solid-gemc-config <preset>` →
     edit `gcards/<preset>.gcard` →
     `/solid-gemc-claude:solid-gemc-run --gcard gcards/<preset>.gcard` →
     `/solid-gemc-claude:solid-gemc-analyze runs/<id>`.

## Outputs

- Workspace under `cwd`: `CLAUDE.md`, `.gitignore`, `log.md`,
  `result.md`, plus `gcards/`, `runs/`, `analysis/` with `.gitkeep`
  placeholders.
- Cached `.sif` at
  `${CLAUDE_PLUGIN_DATA}/cache/sif/jeffersonlab_jlabce_tag2.5_...sif`.
- Cloned + built `solid_gemc/` tree (gitignored). The `solid_gemc`
  binary at `solid_gemc/source/2.9/solid_gemc`.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `missing host tool: apptainer / git / wget / tcsh` | Required host tool not installed. | Install it; rerun. |
| `wget` fails on the .sif URL | Network or Duke webhome unreachable. | Retry. Workaround: mirror the `.sif` locally with `wget`, drop it at `${CLAUDE_PLUGIN_DATA}/cache/sif/<pinned-name>.sif`, rerun. |
| `git clone` fails | Network or GitHub unreachable. | Retry. |
| `scons` fails at `mod/gemc/2.9` or `source/2.9` | Upstream solid_gemc broken on HEAD of master, or the layout changed and `GEMC_VERSION` in `bin/solid-gemc-run` is stale. | First try `cd solid_gemc && git log --oneline -10` to spot a recent breaking commit; pin with `git checkout <earlier-SHA>` and re-run `bin/solid-gemc-run build`. If `mod/gemc/<v>` no longer exists, bump `GEMC_VERSION` in `bin/solid-gemc-run`. |
| Existing files refuse to be touched | Workspace already initialized. | Re-run with `--force` (only after confirming with the user). |

## Notes

- Idempotent. Re-running in a populated workspace without `--force` is
  a no-op; with `--force`, only template files are overwritten.
  `solid_gemc/` and `runs/` contents are preserved.
- The `.sif` URL, solid_gemc upstream, and `GEMC_VERSION=2.9` are
  pinned in `bin/solid-gemc-run`. Do not hardcode them here.
- First-run total time: ~10–20 min (image pull + clone + two scons).
  Subsequent: seconds.
