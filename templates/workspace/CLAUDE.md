# CLAUDE.md — project rules

Rules for Claude when working **inside one project** under the
solid_gemc workspace. The workspace-wide rules (non-negotiables,
wrapper-only seam, run-dir immutability, default analysis stack)
live at `../CLAUDE.md` — read both.

This template is what each new project starts from. Rename the
parent directory of this file to your study name (e.g.
`pvdis_ld2_study`, `sidis_he3_hgc`, `jpsi_lh2`,
`cherenkov_radius_scan`). One project per directory; many
projects coexist in the workspace.

## Project layout

Files live directly under the project root — no subdir split.

| Path | Role |
|------|------|
| `CLAUDE.md`    | this file — project rules |
| `log.md`       | chronological work log for this project (prepend new entries at top) |
| `result.md`    | per-run findings + plot paths |
| `report.html`  | rich-text + plots summary, openable directly in a browser (`file://…/<project>/report.html`). Updated alongside `result.md` when a noteworthy run lands. |
| `<preset>.gcard` | workspace-edited GCard(s). The orchestrator skill copies from `solid_gemc/script/` or `solid_gemc/analysis/*/` and applies batch overrides (`USE_GUI=0`, `OUTPUT=evio,out.evio`, `N=<n>`) on the live `<gcard>` block. |
| `runs/<id>/`   | per-run output. The skill writes `gcard.gcard` (frozen), `out.evio`, `out.root`, `log.txt`, `config.json`. **Gitignored** at the workspace level. |
| `*.py`, `*.C`, `*.pl`, … | your analysis scripts (uproot Python, ROOT macros) or custom detector authoring (Perl generators + factory text files), mixed at the project root |

The flat layout is by design — a single SoLID study typically
weaves geometry tweaks, GCard edits, run outputs, and analysis
scripts together; splitting them across subdirs adds friction
without value. If a project grows large enough that the flat dir
is unwieldy, add subdirs ad-hoc (it's your project).

For canonical worked examples that show this style end-to-end,
both upstream dirs cloned by init are useful:
`solid_gemc/analysis/hgc_study/` (config + run + analyze
pipeline) and `solid_gemc/geometry/hgc_moved/` (custom detector
authoring with Perl generators).

## Custom detector authoring (when canonical detectors don't fit)

When the canonical SoLID detectors don't cover your need, you
author a custom detector inside this project dir. The upstream
convention (from `solid_gemc/geometry/hgc_moved/`) is **Perl
generators producing factory text files** that gemc loads via
`<detector name="..." factory="TEXT" ...>`. Full pipeline:

- `<sub>_geometry.pl` — master Perl generator (geometry).
- `_materials.pl`, `_hit.pl`, `_mirror.pl`, `_virtualplane.pl` —
  the sibling generators.
- `<sub>__geometry_Original.txt`, `__materials_Original.txt`,
  `__hit_Original.txt`, `__mirrors_Original.txt`, `__bank.txt` —
  generated text files (what gemc actually reads).
- `config_<sub>.dat` — parameter file the generators consume.

The plugin has **no** surface for this — follow
upstream's `hgc_moved/readme.md` directly. See also
`${CLAUDE_PLUGIN_ROOT}/reference/gemc_simulation_general_note.md`
(mirror of the SoLID wiki) for field-by-field semantics of the
text formats.

## Config + run + analyze (the simulation loop)

GCards, run outputs, and analysis scripts live mixed in this
project dir. Convention from `solid_gemc/analysis/hgc_study/`:

- GCards at the project root (`<config>.gcard`,
  `<config>_batch.gcard`, …).
- Run scripts (`run.sh`, `getplot`, `run_all`) when batching over
  parameter scans.
- ROOT analysis (`analysis.C`, `compare_*.C`, …). Host-side ROOT
  optional — use `bin/solid-gemc-run root <macro.C>` to execute
  inside the container without installing ROOT on the host.
- Per-run outputs in `runs/<id>/` subdirs (gitignored). The
  orchestrator skill writes `gcard.gcard`, `out.evio`,
  `out.root`, `log.txt`, `config.json` per run.

For host-side default plots from `runs/<id>/out.root`, run
`bin/solid-gemc-run analyze <run>` — it bypasses container ROOT via
uproot.

## Project handoff documents

- **`log.md`** — chronological. Prepend a new dated section for
  every effort (one user request → one entry). Capture the
  request verbatim, the plan, the decision, the outcome. See the
  template inside the file.
- **`result.md`** — per noteworthy run. Key numbers + plot paths
  + a link back to `runs/<id>/`. See the template inside the
  file.
- **`report.html`** — the human-facing version of `result.md`: rich
  text, embedded plots (relative paths into `runs/<id>/`), tables
  for setup + run index. Self-contained (no external CSS/JS);
  open with `file://…/<project>/report.html`. Keep it and
  `result.md` in sync — `result.md` is the source for facts,
  `report.html` is the presentation layer.
- **`../log.md`** (workspace level) — cross-project index. Add a
  one-line pointer here when a new project starts or a milestone
  lands. Detail belongs in the project log.

## Working with this project

The `solid-gemc` orchestrator skill auto-loads on SoLID-flavored
NL requests ("run a PVDIS LD2 study at 11 GeV", "simulate HGC
photoelectron yield on He-3"). It captures the seven-field spec
(project name + the six physics fields), presents a plan, gates
on your approval, then drives the simulation loop and writes
outputs under `runs/<id>/`.

For a manual flow, drop into the container shell directly:

```bash
bin/solid-gemc-run shell
# then inside the container:
cd <project>            # for any project work
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
