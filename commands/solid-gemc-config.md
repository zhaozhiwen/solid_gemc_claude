---
description: Copy a canonical SoLID GCard from solid_gemc/{script,analysis/*}/ into gcards/, with batch + EVIO output overrides applied.
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# /solid-gemc-claude:solid-gemc-config

## Purpose

Pick a canonical SoLID configuration preset (PVDIS_LD2, SIDIS_He3,
J/psi, HGC cherenkov, ...) from the cloned solid_gemc tree (under
`solid_gemc/script/` or `solid_gemc/analysis/*/`) and copy it into the
workspace's `gcards/`, with three overrides applied so the GCard is
ready to run headless. Also drops a sidecar
`gcards/<preset>.gcard.source` recording the original directory —
`solid-gemc-run` reads that to set the right cwd (cwd-relative
geometry loading is how gemc 2.9 resolves `<detector name="...">`).

Overrides applied:

- `USE_GUI=0` — canonical sets it to 1 for interactive; we need batch.
- `<option name="OUTPUT" value="evio,out.evio"/>` — gemc 2.9 only
  supports `evio` and `txt` natively (no ROOT). The relative
  `out.evio` lands wherever `solid-gemc-run` chooses for its absolute
  OUTPUT cmdline override at run time. The plugin's run step
  post-converts via `evio2root` to produce `out.root` for uproot.
- `<option name="N" value="100"/>` — small default event count for
  the first run.

The user can edit `gcards/<slug>.gcard` further (beam energy, physics
list, target, etc.) before running.

## Inputs

- `<preset>` — preset name. Matches against
  `solid_gemc/script/solid_<preset>.gcard` (with `solid_` prefix and
  `.gcard` suffix auto-completed). Pass `--list` (or no argument) to
  see what's available.
- Optional: `--n N` (default `100`), `--output FILENAME` (default
  `out.root`), `--gui` (keep `USE_GUI=1` for interactive debug),
  `--force` (overwrite an existing `gcards/<slug>.gcard`).

## Steps

1. **Verify workspace.** Both `gcards/` and `solid_gemc/script/` must
   exist (the latter is populated by `/solid-gemc-claude:solid-gemc-init`).
   ```bash
   { [[ -d gcards ]] && [[ -d solid_gemc/script ]]; } \
     || { echo "[config] missing gcards/ or solid_gemc/script/; run /solid-gemc-claude:solid-gemc-init first"; exit 1; }
   ```

2. **List mode.** If no `<preset>` (or `--list` passed): enumerate
   presets and stop:
   ```bash
   echo "Available presets in solid_gemc/script/:"
   ls solid_gemc/script/*.gcard 2>/dev/null \
     | xargs -n1 basename \
     | sed 's/^solid_//; s/\.gcard$//' \
     | sort
   ```

3. **Resolve preset to file.** Search `solid_gemc/script/` first, then
   any `solid_gemc/analysis/*/` directory (catches hgc_study and
   future analysis-tree GCards):
   ```bash
   PRESET=<the user-supplied preset>
   SRC=""
   for candidate in \
       "solid_gemc/script/solid_${PRESET}.gcard" \
       "solid_gemc/script/${PRESET}.gcard" \
       "solid_gemc/script/${PRESET}" \
       solid_gemc/analysis/*/"${PRESET}.gcard" \
       solid_gemc/analysis/*/"solid_${PRESET}.gcard"; do
     [[ -f "$candidate" ]] && { SRC="$candidate"; break; }
   done
   [[ -n "$SRC" ]] \
     || { echo "[config] no GCard matching '${PRESET}'; use --list to see options"; exit 1; }
   DEST="gcards/$(basename "$SRC")"
   SOURCE_DIR=$(dirname "$SRC")   # e.g. solid_gemc/script  or  solid_gemc/analysis/hgc_study
   ```

4. **Collision check.**
   ```bash
   [[ -e "$DEST" && -z "${FORCE:-}" ]] \
     && { echo "[config] $DEST exists; pass --force to overwrite"; exit 1; }
   ```

5. **Copy and apply overrides.** Copy the canonical, then run a small
   Python helper that operates **only on the live `<gcard>…</gcard>`
   block** — the comment-block examples (the `<!--  comment out … -->`
   region many canonicals carry) are left untouched. The helper:
   strips any existing live `OUTPUT` / `N` (and `USE_GUI` unless
   `--gui`), then appends our overrides at the bottom of the live
   block. `name="USE_GUI"  value=...` (double-space in some
   canonicals) is handled by a robust `[^>]*` pattern, not sed.
   ```bash
   cp "$SRC" "$DEST"
   GUI_KEEP=${GUI:-0}
   python3 - "$DEST" "${N_EVENTS:-100}" "${OUTPUT_NAME:-out.evio}" "$GUI_KEEP" <<'PY'
   import re, sys, pathlib
   path, n_events, output_name, gui_keep = sys.argv[1:5]
   strip_keys = ['OUTPUT', 'N'] + ([] if gui_keep == '1' else ['USE_GUI'])
   text = pathlib.Path(path).read_text()
   m = re.search(r'(<gcard>)(.*?)(</gcard>)', text, re.DOTALL)
   if not m:
       sys.exit(f"[config] no <gcard>...</gcard> block in {path}")
   head, body, tail = m.groups()
   body = re.sub(
       r'^[ \t]*<option name="(' + '|'.join(strip_keys) + r')"[^>]*/>[ \t]*\n',
       '', body, flags=re.MULTILINE)
   adds = [
       f'<option name="OUTPUT" value="evio,{output_name}"/>',
       f'<option name="N" value="{n_events}"/>',
   ]
   if gui_keep != '1':
       adds.append('<option name="USE_GUI" value="0"/>')
   addition = '\n' + '\n'.join(adds) + '\n'
   new_body = body.rstrip() + addition
   pathlib.Path(path).write_text(text[:m.start(2)] + new_body + text[m.end(2):])
   PY

   # Sidecar recording the source dir — solid-gemc-run cd's here to make
   # cwd-relative detector loading resolve. Path is repo-relative.
   printf '%s\n' "$SOURCE_DIR" > "${DEST}.source"
   ```

6. **Validate** the result is well-formed XML inside the container:
   ```bash
   SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
     "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" validate-gcard "$DEST"
   ```

7. **Report.** Print, in order: file written, copied from, overrides
   applied (USE_GUI, OUTPUT, N values), and the suggested next step:
   ```text
   /solid-gemc-claude:solid-gemc-run --gcard <DEST>
   ```
   Mention briefly that the user can edit `<DEST>` (e.g. `BEAM_P`,
   `PHYSICS`, etc.) before running.

## Outputs

- `gcards/<preset>.gcard` — prepared, batch-ready, EVIO-output GCard.
- `gcards/<preset>.gcard.source` — sidecar; one line, the
  `solid_gemc/<sub>` directory whose cwd is needed at run time so
  `<detector name="...">` paths resolve.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `missing gcards/ or solid_gemc/script/` | Workspace not initialized. | Run `/solid-gemc-claude:solid-gemc-init`. |
| `no GCard matching '<preset>'` | Typo or unavailable preset. | Re-run with `--list`. |
| `<DEST> exists` | Already configured. | `--force` to overwrite, or pick a different name. |
| `validate-gcard` reports a parse error | The canonical GCard has a syntax bug (rare) or the Python helper corrupted it (more likely). | Inspect `<DEST>` vs. `<SRC>`; recopy and skip the helper edits by passing `--gui --n 100 --output out.root` and editing by hand. |

## Notes

- Idempotent without `--force` only if the destination doesn't exist.
- Doesn't touch the upstream `solid_gemc/script/<preset>.gcard` —
  the workspace-side `gcards/<preset>.gcard` is the editable copy.
- The Python edit step uses Python's regex on the live `<gcard>`
  block only, so the `<!-- comment out ... -->` example block in many
  canonical GCards stays intact (you can still copy example overrides
  from there into the live block by hand).
