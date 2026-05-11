# CLAUDE.md — solid_gemc workspace

Rules for Claude when working in this solid_gemc simulation workspace.
The `solid-gemc-claude` plugin scaffolded these directories. The
plugin's slash commands (`/solid-gemc-claude:solid-gemc-config`,
`/solid-gemc-claude:solid-gemc-run`,
`/solid-gemc-claude:solid-gemc-analyze`) operate on the layout below.

`/solid-gemc-claude:solid-gemc-init` (which created this workspace) also
cloned and built solid_gemc into `./solid_gemc/` — that's where SoLID
geometry, the canonical GCards (`solid_gemc/script/`), and the built
binary (`solid_gemc/source/2.9/solid_gemc`) live.

## Layout

| Path | Role |
|------|------|
| `gcards/`     | GCard XML files (versioned). Copy from `solid_gemc/script/` via `/solid-gemc-claude:solid-gemc-config`. |
| `runs/`       | One sub-directory per `/solid-gemc-claude:solid-gemc-run`. **Gitignored** (only the `.gitkeep` placeholder is kept). |
| `analysis/`   | Python scripts that read `runs/<id>/out.root`. Versioned. |
| `solid_gemc/` | Cloned + built upstream tree. **Gitignored.** Don't commit. Refresh via re-running init. |
| `log.md`      | Chronological work log — prepend at the top after each session. |
| `result.md`   | Per-run findings, with paths to `runs/<id>/` and `analysis/`. |

## Non-negotiables

1. **All solid_gemc / scons / ROOT calls go through the plugin's wrapper.**
   Never invoke `apptainer`, `solid_gemc`, `scons`, or `root` directly.
   Use `bin/solid-gemc-run` (or the slash commands that wrap it).
   In-container shell is tcsh.
2. **Run directories are immutable.** Once a run finishes, treat
   `runs/<id>/` as read-only. New analysis = new script in `analysis/`,
   not edits in the run directory.
3. **`runs/<id>/config.json` is the provenance record.** It records the
   GCard, the .sif name, the solid_gemc commit SHA, GEMC_VERSION,
   n_events, the gemc + evio2root exit codes, wall time, and which
   source dir was used as cwd for the gemc step. Read it to know
   what produced the data. Never hand-edit it.
4. **Default analysis stack: `uproot` + `numpy` + `matplotlib`** on
   the host (out of the container), against `runs/<id>/out.root`.
   The ROOT file is post-converted from gemc's native `out.evio` by
   `evio2root` inside the container — both files live in `runs/<id>/`.
   Anything that needs the actual ROOT executable runs inside the
   container via `bin/solid-gemc-run root <macro>`.
5. **Don't commit `solid_gemc/`.** It's an upstream-managed working
   tree that init rebuilds. Same for `runs/`, `*.root`, `*.hipo`,
   `__pycache__/`.
6. **Maintain `log.md` and `result.md`.** Every simulation effort —
   orchestrator-driven or manual — leaves a record. Prepend a new
   dated section to `log.md` capturing four things: the user's
   **original request** (verbatim), the **plan** Claude drew up
   (six-field spec — physics goal, SoLID config, beam, GCard, output,
   analysis), the user's **decision** (approved / edited / plan-only),
   and the **outcome** (run id, status, one-line summary). After a
   `/solid-gemc-claude:solid-gemc-analyze` that produced a noteworthy
   result, add or update a section in `result.md` with key numbers +
   plot paths. Both files are load-bearing handoff documents.

## Typical loop

1. `/solid-gemc-claude:solid-gemc-config <preset>` — copy a canonical
   GCard from `solid_gemc/script/` into `gcards/`. Presets follow the
   `solid_<EXP>_<TARGET>_<...>` pattern (e.g. `PVDIS_LD2_moved_full`,
   `SIDIS_He3_full_moved`, `J_psi_LH2`).
2. Edit `gcards/<preset>.gcard` for beam energy, `n_events`, output
   path. GCard field reference: `https://gemc.jlab.org`.
3. `/solid-gemc-claude:solid-gemc-run --gcard gcards/<preset>.gcard` —
   runs `solid_gemc <gcard>` inside the container (writes
   `runs/<id>/out.evio`, the only output gemc 2.9 supports natively),
   then auto-runs `evio2root` to produce `runs/<id>/out.root` for
   the analysis path. Full set: `runs/<id>/{gcard.gcard, out.evio,
   out.root, log.txt, config.json}`.
4. `/solid-gemc-claude:solid-gemc-analyze runs/<id>` — auto-detects
   ROOT branches and plots; or write a custom script in `analysis/`.

## First run after init — try the upstream HGC study

The recommended first thing to run is the **upstream HGC study** at
`solid_gemc/analysis/hgc_study/` — a fully self-contained example
shipped with solid_gemc. It is the canonical worked example for the
**config + run + analyze** pipeline: GCards
(`cherenkov.gcard`, `cherenkov_batch.gcard`, `solid_SIDIS_He3_hgc.gcard`,
etc.), batch run scripts (`load.sh` / `run.sh`), and ROOT analysis
(`analysis.C`, `analysis_tree_solid_hgc.C`, the `compare_*.C`
comparison scripts). Two ways in:

- Drop into a container shell: `bin/solid-gemc-run shell`, then
  `cd solid_gemc/analysis/hgc_study` and follow upstream's flow.
  (The wrapper binds your workspace to its host path inside the
  container and sets PWD there, so the path is the same in and out.)
- Or pick one of its GCards: `cp solid_gemc/analysis/hgc_study/solid_SIDIS_He3_hgc.gcard gcards/`
  then `/solid-gemc-claude:solid-gemc-run --gcard gcards/solid_SIDIS_He3_hgc.gcard`.

## Reference example for custom detectors

If you ever need to author your own detector (factory text files
that gemc loads via `<detector name="..." factory="TEXT" ...>`),
the canonical worked example is upstream
`solid_gemc/geometry/hgc_moved/`. It has a `readme.md` plus the
full set:

- `solid_SIDIS_hgc_geometry.pl`, `_materials.pl`, `_hit.pl`,
  `_mirror.pl`, `_virtualplane.pl` — Perl generators (the editable
  source-of-truth in solid_gemc's convention).
- `solid_SIDIS_hgc__geometry_Original.txt`, `__materials_Original.txt`,
  `__hit_Original.txt`, `__mirrors_Original.txt`, `__bank.txt` —
  generated text files (what gemc actually reads at runtime).
- `config_solid_SIDIS_hgc.dat` — parameter file the Perl generators
  consume.

The plugin's v0.0.1 surface doesn't include a custom-detector
authoring slash command — for that work, follow upstream conventions
in `geometry/hgc_moved/` directly (edit the `.pl`, regenerate the
`.txt`, reference from your GCard with `<detector name="..." factory="TEXT" ...>`).

## When something fails

- GCard parse error → `bin/solid-gemc-run validate-gcard gcards/<name>.gcard`.
- `solid_gemc` crashes at runtime → `runs/<id>/log.txt`; usually the
  failing volume, material, or magnet field config.
- Missing binary at `solid_gemc/source/2.9/solid_gemc` → re-run
  `/solid-gemc-claude:solid-gemc-init` or
  `bin/solid-gemc-run build`.
- Image missing → `bin/solid-gemc-run info` shows `[not pulled]`; run
  `bin/solid-gemc-run pull`.
