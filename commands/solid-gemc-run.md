---
description: Run a configured solid_gemc GCard inside the container; capture EVIO + post-converted ROOT outputs and provenance under runs/<id>/.
allowed-tools: Bash, Read, Write, Glob
---

# /solid-gemc-claude:solid-gemc-run

## Purpose

Execute `solid_gemc <gcard>` inside the pinned JLabCE 2.5 container,
with a per-run provenance record. The gemc 2.9 binary writes **EVIO**
(its native format; the build has no ROOT writer); this command then
runs `evio2root` to produce a `out.root` for the analysis path.
Outputs land in a fresh `runs/<id>/` directory:

- `gcard.gcard` — frozen copy of the input GCard.
- `out.evio` — raw solid_gemc output.
- `out.root` — converted by `evio2root` (default: `-INPUTF=out.evio`,
  all banks); read by `solid-gemc-analyze` with uproot.
- `log.txt` — captured stdout/stderr (solid_gemc + evio2root combined).
- `config.json` — provenance record.

`runs/<id>/` is treated as immutable after the run.

**Cwd discipline.** gemc 2.9 resolves `<detector name="...">`
relative to the **process cwd**, not relative to the GCard file's
location. To make canonical GCards' `../geometry/...` paths work,
this command `cd`s into the canonical's source directory (recorded
by `solid-gemc-config` in the sidecar `gcard.source` file), then
invokes `solid_gemc` with an **absolute** path to the workspace
GCard and an **absolute** `-OUTPUT=evio,...` override.

## Inputs

- `--gcard <path>` — required. Path to a configured GCard from
  `/solid-gemc-claude:solid-gemc-config` (`gcards/<preset>.gcard`).
  Must have a sidecar `<gcard>.source` next to it.
- Optional `--id <custom>` — override the auto-generated run id.
  Default is `YYYYMMDD-HHMMSS-<6char>` (UTC).

## Steps

1. **Validate inputs.**
   ```bash
   GCARD=<the user-supplied --gcard path>
   [[ -f "$GCARD" ]] \
     || { echo "[run] GCard not found: $GCARD"; exit 1; }
   [[ -f "${GCARD}.source" ]] \
     || { echo "[run] sidecar missing: ${GCARD}.source — did this come from /solid-gemc-claude:solid-gemc-config?"; exit 1; }
   SOURCE_DIR=$(cat "${GCARD}.source")
   [[ -d "$SOURCE_DIR" ]] \
     || { echo "[run] source dir does not exist: $SOURCE_DIR"; exit 1; }
   ```

2. **Generate the run id and stage `runs/<id>/`.**
   ```bash
   RUN_ID=$(date -u +%Y%m%d-%H%M%S)-$(head -c 12 /dev/urandom | base32 | tr 'A-Z' 'a-z' | head -c 6)
   RUN_DIR="runs/${RUN_ID}"
   mkdir -p "$RUN_DIR"
   cp "$GCARD" "$RUN_DIR/gcard.gcard"

   # Absolute paths — we'll cd elsewhere for the gemc step, so all paths
   # the wrapper / gemc binary see must be resolvable from any cwd.
   WORKSPACE_ABS=$(readlink -f .)
   RUN_DIR_ABS="${WORKSPACE_ABS}/${RUN_DIR}"
   GCARD_ABS="${WORKSPACE_ABS}/${RUN_DIR}/gcard.gcard"
   ```

3. **Run solid_gemc** from inside the canonical source directory.
   Three discipline notes for the bash:
   (a) the cd is inside `( … )`, so the parent shell's cwd is
   unchanged; (b) `tee` writes to the **absolute** `${RUN_DIR_ABS}/log.txt`
   so the log lands in the workspace's `runs/<id>/`, not the cd'd
   source dir; (c) `SoLID_GEMC` is exported absolute so the wrapper's
   env block doesn't re-derive it from `$PWD` (which has changed).
   Pipe-exit-code capture is portable across bash and zsh via a
   tempfile (the harness shell may be either).
   ```bash
   START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
   START_EPOCH=$(date +%s)
   GEMC_EC_FILE=$(mktemp)
   ( cd "$SOURCE_DIR" && \
     SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
     SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
       "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" exec \
         "solid_gemc '${GCARD_ABS}' -OUTPUT='evio,${RUN_DIR_ABS}/out.evio'"; \
     echo $? > "${GEMC_EC_FILE}" ) 2>&1 | tee "${RUN_DIR_ABS}/log.txt"
   GEMC_EXIT=$(cat "${GEMC_EC_FILE}"); rm -f "${GEMC_EC_FILE}"
   ```

4. **Post-convert EVIO → ROOT.** Skip and abort with a clear note if
   the gemc step failed; otherwise run `evio2root` from `runs/<id>/`
   (it writes `<basename>.root` next to the input by default). Same
   tempfile discipline for the exit code.
   ```bash
   EVIO2ROOT_EXIT=0
   if [[ "$GEMC_EXIT" = "0" && -f "${RUN_DIR_ABS}/out.evio" ]]; then
     EVIO_EC_FILE=$(mktemp)
     ( cd "$RUN_DIR_ABS" && \
       SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
       SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
         "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" exec \
           "evio2root -INPUTF=out.evio"; \
       echo $? > "${EVIO_EC_FILE}" ) 2>&1 | tee -a "${RUN_DIR_ABS}/log.txt"
     EVIO2ROOT_EXIT=$(cat "${EVIO_EC_FILE}"); rm -f "${EVIO_EC_FILE}"
   fi
   if [[ "$GEMC_EXIT" != "0" ]]; then
     EXIT_CODE="$GEMC_EXIT"
   else
     EXIT_CODE="$EVIO2ROOT_EXIT"
   fi
   END_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
   END_EPOCH=$(date +%s)
   ```

5. **Write the provenance `config.json`.** Capture everything a
   future reader needs to reproduce or interpret the run:
   ```bash
   SIF_NAME=$(grep '^SIF_NAME=' "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" | head -1 | cut -d'"' -f2)
   SOLID_GEMC_SHA=$(cd solid_gemc && git rev-parse HEAD 2>/dev/null || echo unknown)
   GEMC_VERSION_PINNED=$(grep '^GEMC_VERSION=' "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" | head -1 | cut -d'"' -f2)
   N_EVENTS=$(grep -oE '<option name="N" value="[^"]+"' "$RUN_DIR/gcard.gcard" | head -1 | sed 's/.*value="//; s/"$//')

   python3 - "$RUN_DIR/config.json" <<PY
   import json, sys
   d = {
     "run_id":           "${RUN_ID}",
     "gcard_source":     "${GCARD}",
     "gcard_frozen":     "${RUN_DIR}/gcard.gcard",
     "source_dir":       "${SOURCE_DIR}",
     "n_events":         "${N_EVENTS}",
     "sif_name":         "${SIF_NAME}",
     "solid_gemc_repo":  "https://github.com/JeffersonLab/solid_gemc",
     "solid_gemc_sha":   "${SOLID_GEMC_SHA}",
     "gemc_version":     "${GEMC_VERSION_PINNED}",
     "start_utc":        "${START_ISO}",
     "end_utc":          "${END_ISO}",
     "wall_seconds":     ${END_EPOCH} - ${START_EPOCH},
     "gemc_exit_code":   ${GEMC_EXIT},
     "evio2root_exit":   ${EVIO2ROOT_EXIT},
     "exit_code":        ${EXIT_CODE},
     "command":          "solid_gemc <gcard> -OUTPUT=evio,<run>/out.evio; evio2root -INPUTF=out.evio",
     "cwd_gemc":         "${SOURCE_DIR}",
     "cwd_evio2root":    "${RUN_DIR}",
   }
   import pathlib
   pathlib.Path(sys.argv[1]).write_text(json.dumps(d, indent=2) + "\n")
   PY
   ```

6. **Report.**
   - Run id, run dir.
   - Exit status (succeeded / failed at solid_gemc step).
   - On success: path to `runs/<id>/out.root`, suggested next:
     `/solid-gemc-claude:solid-gemc-analyze runs/<id>`.
   - On failure: last 30 lines of `runs/<id>/log.txt` and the
     `config.json` location for diagnosis.

7. **Prepend a `log.md` entry.** The workspace `log.md` is the
   handoff document; append (at the top, after the header) a new
   dated section summarizing the run — request quoted verbatim, the
   six-field plan that produced it, the user's decision, and the
   one-line outcome (run id + exit status). See the in-file template.

## Outputs

- `runs/<id>/`:
  - `gcard.gcard` — frozen copy of the GCard that produced this run.
  - `out.evio` — solid_gemc's native output (gemc 2.9 doesn't write ROOT).
  - `out.root` — produced by `evio2root` from `out.evio` (uproot-readable).
  - `log.txt` — captured stdout/stderr (gemc + evio2root, in order).
  - `config.json` — provenance: run id, source_dir (the cwd used for
    the gemc step), .sif name, solid_gemc commit SHA, GEMC_VERSION,
    n_events, wall time, gemc_exit_code, evio2root_exit, overall exit_code.
- A prepended entry in `log.md`.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `GCard not found` / `sidecar missing` | Path typo, or GCard wasn't produced by `/solid-gemc-claude:solid-gemc-config`. | Run `solid-gemc-config <preset>` to get a sidecar-paired GCard, or write a `.source` file yourself (one line: relative path to a dir under `solid_gemc/`). |
| solid_gemc exits non-zero immediately | Bad GCard, missing detector files, malformed option, or wrong cwd (the source_dir doesn't have the geometry siblings the GCard's `<detector name="...">` lines reference). | Inspect last lines of `log.txt`; the wrapper's `validate-gcard` covers XML well-formedness only; check that the sidecar `.source` points at the dir that holds the canonical's siblings. |
| `Output type <root> NOT FOUND` | Someone set `-OUTPUT=root,...` against this build. gemc 2.9 in JLabCE 2.5 only supports `evio` and `txt` — let `config` apply its EVIO default. | Re-run config without `--output root,...`. |
| `error while loading shared libraries` inside the container | Mismatch between the pinned .sif and the built solid_gemc tree. | Re-run `/solid-gemc-claude:solid-gemc-init`. |
| `out.evio` exists but `out.root` doesn't | `evio2root` failed (look at `log.txt` after the EVIO closing line). | Re-run `evio2root` manually: `cd runs/<id> && bin/solid-gemc-run exec 'evio2root -INPUTF=out.evio'`. |

## Notes

- The run directory is **immutable** after the run. New analysis goes
  in `analysis/`, not in `runs/<id>/`.
- The `config.json` is **append-only / frozen** — never hand-edit.
- For batch over many GCards (e.g., scanning a parameter), call this
  command repeatedly with different `--gcard` paths; each call gets
  its own run id.
