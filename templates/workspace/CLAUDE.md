# CLAUDE.md — project rules

Rules for Claude when working **inside one project** under the
solid_gemc workspace. The workspace-wide rules (non-negotiables,
wrapper-only seam, run-dir immutability, default analysis stack)
live at `../CLAUDE.md` — read both.

This template is what each new project starts from. Rename the
parent directory of this file to your study name (e.g.
`pvdis_ld2_study`, `sidis_he3_hgc`, `jpsi_lh2`,
`cherenkov_radius_scan`). One project per directory; many projects
coexist in the workspace.

## Project layout

| Path | Role | Mimics upstream |
|------|------|------|
| `CLAUDE.md`  | this file — project rules | n/a |
| `log.md`     | chronological work log for this project (prepend new entries at top) | n/a |
| `result.md`  | per-run findings + plot paths | n/a |
| `geometry/`  | custom detector authoring (Perl generators + factory text files) | `solid_gemc/geometry/hgc_moved/` |
| `analysis/`  | GCards, run outputs, ROOT/uproot analysis scripts | `solid_gemc/analysis/hgc_study/` |

Both upstream examples (`hgc_moved/` and `hgc_study/`) are cloned
into the workspace by `/solid-gemc-claude:solid-gemc-init`. Open
them side-by-side with this project to see the canonical pattern
in full.

## `geometry/` — custom detector authoring

When the canonical SoLID detectors don't cover your need, you
author a custom detector here. The upstream convention (from
`solid_gemc/geometry/hgc_moved/`) is **Perl generators producing
factory text files** that gemc loads via
`<detector name="..." factory="TEXT" ...>`. Full pipeline:

- `<sub>_geometry.pl` — master Perl generator (geometry).
- `_materials.pl`, `_hit.pl`, `_mirror.pl`, `_virtualplane.pl` —
  the sibling generators.
- `<sub>__geometry_Original.txt`, `__materials_Original.txt`,
  `__hit_Original.txt`, `__mirrors_Original.txt`, `__bank.txt` —
  generated text files (what gemc actually reads).
- `config_<sub>.dat` — parameter file the generators consume.

The plugin does **not** ship a slash command for this — follow
upstream's `hgc_moved/readme.md` directly. See also
`${CLAUDE_PLUGIN_ROOT}/reference/gemc_simulation_general_note.md`
(mirror of the SoLID wiki) for field-by-field semantics of the
text formats.

## `analysis/` — config + run + analyze

GCards, run outputs, and analysis scripts. Convention from
`solid_gemc/analysis/hgc_study/`:

- GCards in the same directory (`<config>.gcard`,
  `<config>_batch.gcard`, …).
- Run scripts (`run.sh`, `getplot`, `run_all`) when batching over
  parameter scans.
- ROOT analysis (`analysis.C`, `compare_*.C`, …). Host-side ROOT
  optional — use `bin/solid-gemc-run root <macro.C>` to execute
  inside the container without installing ROOT on the host.
- Per-run outputs in `analysis/runs/<id>/` subdirs (gitignored).
  The orchestrator skill writes `gcard.gcard`, `out.evio`,
  `out.root`, `log.txt`, `config.json` per run.

For host-side default plots from `analysis/runs/<id>/out.root`,
use `/solid-gemc-claude:solid-gemc-analyze` — it bypasses
container ROOT via uproot.

## Project handoff documents

- **`log.md`** — chronological. Prepend a new dated section for
  every effort (one user request → one entry). Capture the
  request verbatim, the plan, the decision, the outcome. See the
  template inside the file.
- **`result.md`** — per noteworthy run. Key numbers + plot paths
  + a link back to `analysis/runs/<id>/`. See the template inside
  the file.
- **`../log.md`** (workspace level) — cross-project index. Add a
  one-line pointer here when a new project starts or a milestone
  lands. Detail belongs in the project log.

## Working with this project

The `solid-gemc` orchestrator skill auto-loads on SoLID-flavored
NL requests ("run a PVDIS LD2 study at 11 GeV", "simulate HGC
photoelectron yield on He-3"). It captures the six-field spec
(physics goal / SoLID config / beam / GCard / output / analysis),
presents a plan, gates on your approval, then drives the
simulation loop and writes outputs under `analysis/runs/<id>/`.

For a manual flow, drop into the container shell directly:

```bash
bin/solid-gemc-run shell
# then inside the container:
cd <project>/analysis            # for a study
cd <project>/geometry            # for detector authoring
```

The wrapper binds your workspace at its host path inside the
container, so paths are the same in and out.

## Reference

- Workspace-wide rules: `../CLAUDE.md`.
- Upstream worked examples (cloned by init):
  `../solid_gemc/analysis/hgc_study/` (config + run + analyze) and
  `../solid_gemc/geometry/hgc_moved/` (custom detector authoring).
- gemc / solid_gemc source digests and physics references:
  `${CLAUDE_PLUGIN_ROOT}/reference/` inside the plugin install.
