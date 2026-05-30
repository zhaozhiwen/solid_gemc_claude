#!/usr/bin/env python3
"""Schema-aware default plots for a solid_gemc run's out.root.

Called by `bin/solid-gemc-run analyze`; runs under the plugin's analysis venv
(uproot / numpy / matplotlib). Not a Claude/Codex artifact — plain Python, so
the same code serves every platform.

Usage: solid-gemc-analyze.py <out.root> <run-dir> [max-plots]

Three output classes are handled:
  - TTrees:     one PNG per numeric branch (up to max-plots).
  - TH1/2/3F:   enumerated, not re-plotted (already plottable downstream).
  - neither:    reported as empty / non-standard.
"""
import sys
import pathlib

import uproot
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: solid-gemc-analyze.py <out.root> <run-dir> [max-plots]", file=sys.stderr)
        return 2
    root_path, run_dir = sys.argv[1], sys.argv[2]
    max_plots = int(sys.argv[3]) if len(sys.argv) > 3 else 12

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
                plt.xlabel(bname)
                plt.ylabel("count")
                plt.title(f"{short} / {bname}")
                safe = bname.replace("/", "_").replace(" ", "_")
                out = pathlib.Path(run_dir) / f"hist_{short}_{safe}.png"
                plt.savefig(out, dpi=110, bbox_inches="tight")
                plt.close()
                plotted += 1
                print(f"[analyze]     plotted {bname} -> {out.name}")
            if plotted >= max_plots:
                print(f"[analyze]   plot cap ({max_plots}) reached; pass a larger N for more.")
                break

    if hists:
        print(f"[analyze] file also contains {len(hists)} pre-built histograms (TH1/2/3F).")
        for k, cls in list(hists.items())[:10]:
            print(f"[analyze]     {cls}  {k.split(';')[0]}")
        if len(hists) > 10:
            print(f"[analyze]     ... and {len(hists) - 10} more.")
        print("[analyze]   (post-processed file; write a script in the project dir to plot these.)")

    if not trees and not hists:
        print("[analyze] no TTree or histogram objects found. Empty or non-standard file?")
    elif not trees:
        print("[analyze] no TTrees — file looks post-processed. Default plots skipped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
