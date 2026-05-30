---
description: Inspect runs/<id>/out.root with uproot and generate default plots (1D histograms for numeric branches).
allowed-tools: Bash, Read, Glob
---

# /solid-gemc-claude:analyze

## Purpose

First-pass orientation on the ROOT file produced by a simulation run: report
the schema (TTrees, branches, entry counts) and emit default plots into the
same `runs/<id>/` directory. Schema-aware — whatever numeric branches actually
exist get histogrammed; pre-built histograms are enumerated, not re-plotted.

The inspection + plotting lives in `bin/solid-gemc-run analyze` (which calls
`bin/solid-gemc-analyze.py` under the analysis venv — the single
implementation, shared with the Codex/standalone path). This command is the
Claude Code surface.

## Inputs

- `<run-dir>` — a `runs/<id>/` directory, the bare id, or a path to `out.root`.
- Optional second arg: max number of auto-histograms (default `12`).

## Steps

1. **Run the analysis.** The analysis venv installs automatically on first use
   (idempotent; run `bin/solid-gemc-run setup-python` to pre-install):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" analyze "<run-dir>"   # optional: trailing max-plots
   ```
   It prints the per-tree schema summary and the PNGs written, and lists the
   generated plots in the run dir.

2. **Report + suggest the next move.** Surface the schema summary (most useful
   for unfamiliar GCards), then:
   - For custom analysis (asymmetries, cuts, fits), write a Python script in the
     project dir and read the same `out.root` with uproot.
   - Update `result.md` with the key numbers + plot paths, then refresh
     `report.html` so the rendered summary stays in sync.

## Outputs

- One PNG per plotted branch in `runs/<id>/`, named `hist_<tree>_<branch>.png`.
- Stdout: tree names, entry counts, branches, what got plotted/skipped.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `no ROOT file at <path>` | Run produced no output, or `OUTPUT` pointed elsewhere. | Check `runs/<id>/log.txt`; check the GCard's `<option name="OUTPUT" .../>`. |
| `no numeric branches plotted` | File has only object branches or empty trees. | Write a custom script that decodes those branches; gemc's layout varies by detector. |

## Notes

- **Diagnostic, not the final analysis.** Real physics analysis belongs in a
  versioned script at the project root, flat alongside the run dirs.
- Output PNGs live in `runs/<id>/` alongside `out.root` / `log.txt` /
  `config.json`, keeping a run self-contained.
