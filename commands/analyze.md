---
description: Inspect runs/<id>/out.root with uproot and generate default plots (1D histograms for numeric branches).
allowed-tools: Bash, Read, Write, Glob
---

# /solid-gemc-claude:analyze

## Purpose

Open the ROOT file produced by an earlier simulation run (driven by
the `solid-gemc` orchestrator skill, by upstream's
`hgc_study/run.sh`, or by a hand-written invocation of
`bin/solid-gemc-run exec "solid_gemc ..."`), report the schema
(TTrees, branches, entry counts), and emit a set of default plots
into the same `runs/<id>/` directory. Schema-aware: no canned "this
is what solid_gemc outputs" assumption — whatever branches actually
exist get histogrammed (numeric ones) or summarized (non-numeric).

For custom analysis (asymmetries, kinematic cuts, multi-run
comparisons), the user writes a Python script in `analysis/` and reads
the same ROOT file. This command is the first-pass orientation, not
the final analysis.

## Inputs

- `<run-dir>` — a `runs/<id>/` directory. Accepts the full path,
  the id alone, or a path to `out.root` directly.
- Optional: `--root <name>` (default `out.root`), `--max-plots N`
  (default `12`, cap on auto-histograms to avoid plot-flood).

## Steps

1. **Resolve the ROOT file.** Accept three input forms:
   ```bash
   ARG=<the user-supplied run-dir>
   if   [[ -f "$ARG" ]];                       then ROOT="$ARG"; RUN_DIR="$(dirname "$ARG")"
   elif [[ -d "$ARG" ]];                       then ROOT="$ARG/out.root"; RUN_DIR="$ARG"
   elif [[ -d "runs/$ARG" ]];                  then ROOT="runs/$ARG/out.root"; RUN_DIR="runs/$ARG"
   else
     echo "[analyze] no run found for '$ARG'; check 'ls runs/'"; exit 1
   fi
   [[ -f "$ROOT" ]] \
     || { echo "[analyze] no ROOT file at $ROOT (did the run succeed? see $RUN_DIR/log.txt)"; exit 1; }
   ```

2. **Activate the plugin venv** (where `uproot` / `numpy` /
   `matplotlib` live, installed by the SessionStart hook):
   ```bash
   VENV_PY="${CLAUDE_PLUGIN_DATA}/venv/bin/python"
   [[ -x "$VENV_PY" ]] \
     || { echo "[analyze] plugin venv missing at $VENV_PY; re-enter a Claude Code session to fire SessionStart hook"; exit 1; }
   ```

3. **Inspect schema + plot.** Run a single Python program against
   the file. Three output classes are handled:
   - **TTrees**: print a one-line summary per tree, then write one
     PNG per numeric branch (up to `--max-plots`). This is the
     "raw gemc ROOT output" case (`<option name="OUTPUT" value="root,..."/>`).
   - **Histograms** (`TH1F`/`TH2F`/`TH3F`): enumerate them so the user
     knows the file is post-processed. Don't re-plot — they're
     already plottable in ROOT or the user's analysis script.
   - **Neither**: report empty / unrecognized.
   ```bash
   "$VENV_PY" - "$ROOT" "$RUN_DIR" "${MAX_PLOTS:-12}" <<'PY'
   import sys, pathlib
   import uproot, numpy as np
   import matplotlib
   matplotlib.use("Agg")
   import matplotlib.pyplot as plt

   root_path, run_dir, max_plots = sys.argv[1], sys.argv[2], int(sys.argv[3])
   f = uproot.open(root_path)
   print(f"[analyze] file: {root_path}")

   cn = f.classnames()
   trees = {k: f[k] for k, v in cn.items() if v.startswith("TTree")}
   hists = {k: v for k, v in cn.items() if v.startswith("TH")}

   plotted = 0
   if trees:
       for tname, tree in trees.items():
           short = tname.split(";")[0]
           print(f"[analyze]   tree {short}: {tree.num_entries} entries, {len(tree.keys())} branches")
           if tree.num_entries == 0:
               continue
           for bname in tree.keys():
               if plotted >= max_plots:
                   break
               try:
                   arr = tree[bname].array(library="np")
               except Exception as e:
                   print(f"[analyze]     skip {bname} ({type(e).__name__})")
                   continue
               # Flatten jagged arrays (gemc hit-level branches are usually jagged).
               try:
                   flat = np.concatenate(arr).astype(float)
               except (TypeError, ValueError):
                   try:
                       flat = np.asarray(arr, dtype=float)
                   except Exception:
                       continue
               if flat.size == 0 or not np.isfinite(flat).any():
                   continue
               plt.figure()
               plt.hist(flat[np.isfinite(flat)], bins=80)
               plt.xlabel(bname); plt.ylabel("count")
               plt.title(f"{short} / {bname}")
               safe = bname.replace("/", "_").replace(" ", "_")
               out = pathlib.Path(run_dir) / f"hist_{short}_{safe}.png"
               plt.savefig(out, dpi=110, bbox_inches="tight")
               plt.close()
               plotted += 1
               print(f"[analyze]     plotted {bname} -> {out.name}")
           if plotted >= max_plots:
               print(f"[analyze]   plot cap ({max_plots}) reached; pass --max-plots N for more.")
               break

   if hists:
       print(f"[analyze] file also contains {len(hists)} pre-built histograms (TH1/2/3F).")
       for k, cls in list(hists.items())[:10]:
           print(f"[analyze]     {cls}  {k.split(';')[0]}")
       if len(hists) > 10:
           print(f"[analyze]     ... and {len(hists) - 10} more.")
       print("[analyze]   (post-processed file; write a script in analysis/ to plot these.)")

   if not trees and not hists:
       print("[analyze] no TTree or histogram objects found. Empty or non-standard file?")
   elif not trees:
       print("[analyze] no TTrees — file looks post-processed. Default plots skipped.")
   PY
   ```

4. **Report.** List the generated PNGs in the run dir, suggest the
   next move:
   ```bash
   ls -1 "$RUN_DIR"/*.png 2>/dev/null
   echo
   echo "Next:"
   echo "  - Inspect the plots."
   echo "  - For custom analysis, write analysis/${RUN_DIR##runs/}.py and read $ROOT with uproot."
   echo "  - Update result.md with the key numbers + plot paths,"
   echo "    then refresh report.html so the rendered summary stays in sync."
   ```

## Outputs

- One PNG per plotted branch in `runs/<id>/`, named
  `hist_<tree>_<branch>.png`.
- Stdout summary: tree names, entry counts, branches, what got
  plotted, what got skipped.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `no ROOT file at <path>` | Run didn't produce output, or the GCard's `OUTPUT` option pointed elsewhere. | Check `runs/<id>/log.txt` for solid_gemc errors; check `runs/<id>/gcard.gcard` for the `<option name="OUTPUT" .../>` value. |
| `plugin venv missing` | SessionStart hook hasn't run yet (fresh install). | Exit and re-enter the Claude Code session so the hook installs `uproot`/`numpy`/`matplotlib`. |
| `no numeric branches plotted` | ROOT file has only object branches (`TLorentzVector`, etc.) or empty trees. | Write a custom Python in `analysis/` that decodes those branches; gemc's output layout varies by detector. |

## Notes

- This command is **diagnostic**, not the final analysis. Real
  physics analysis (asymmetries, fits, cuts) belongs in
  `analysis/<id>.py` — a script under the user's control, versioned.
- The schema summary is the most valuable part of the output for
  unfamiliar GCards — it tells you which trees solid_gemc populated
  and how many entries each got.
- Output PNGs live in `runs/<id>/`, alongside `out.root` / `log.txt`
  / `config.json`. This keeps a run self-contained.
