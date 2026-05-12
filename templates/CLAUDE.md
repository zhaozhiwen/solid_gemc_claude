# CLAUDE.md — solid_gemc workspace

Rules for Claude when working in this solid_gemc simulation workspace.
The `solid-gemc-claude` plugin scaffolded these directories.

`/solid-gemc-claude:solid-gemc-init` (which created this workspace) also
cloned and built solid_gemc into `./solid_gemc/` — that's where SoLID
geometry, the canonical GCards (`solid_gemc/script/`), and the built
binary (`solid_gemc/source/2.9/solid_gemc`) live.

The plugin ships **two slash commands** —
`/solid-gemc-claude:solid-gemc-init` (already done) and
`/solid-gemc-claude:solid-gemc-analyze` (host-side uproot plots after a
run). Everything in between (picking a GCard, running gemc, converting
EVIO → ROOT) is driven by the **`solid-gemc` orchestrator skill** which
auto-loads on SoLID-flavored natural-language requests, or by
`bin/solid-gemc-run` directly for users following upstream's
`hgc_study/run.sh` pattern.

## Workspace layout

Each SoLID study (or detector-authoring effort) lives in its own
**project subdirectory** at the workspace root, mirroring how
upstream organizes `solid_gemc/analysis/hgc_study/` and
`solid_gemc/geometry/hgc_moved/` as separate self-contained dirs.

| Path | Role |
|------|------|
| `<name>/`     | One project. Rename `<name>` to your study (e.g. `pvdis_ld2`, `sidis_he3_hgc`, `jpsi_lh2`). One subdir per study; multiple studies coexist in one workspace. |
| `<name>/README.md`  | Project overview. See the template that ships with init. |
| `<name>/log.md`     | Chronological work log for this project. Prepend new entries at top. |
| `<name>/result.md`  | Per-run findings, with paths to `<name>/analysis/runs/<id>/`. |
| `<name>/geometry/`  | Custom detector authoring (Perl generators + factory text files). Mimics `solid_gemc/geometry/hgc_moved/`. |
| `<name>/analysis/`  | GCards, run outputs, ROOT/uproot analysis scripts. Mimics `solid_gemc/analysis/hgc_study/`. The orchestrator skill writes `<name>/analysis/runs/<id>/{gcard.gcard, out.evio, out.root, log.txt, config.json}` per run. |
| `solid_gemc/`       | Cloned + built upstream tree (init artifact). **Gitignored.** Refresh via re-running init. |

## Non-negotiables

1. **All solid_gemc / scons / ROOT calls go through the plugin's wrapper.**
   Never invoke `apptainer`, `solid_gemc`, `scons`, or `root` directly.
   Use `bin/solid-gemc-run` (or the skill / slash commands that wrap it).
   In-container shell is tcsh.
2. **Run directories are immutable.** Once a run finishes, treat
   `<name>/analysis/runs/<id>/` as read-only. New analysis = new
   script in `<name>/analysis/`, not edits in the run directory.
3. **`<name>/analysis/runs/<id>/config.json` is the provenance record.**
   It records the GCard, the .sif name, the solid_gemc commit SHA,
   GEMC_VERSION, n_events, the gemc + evio2root exit codes, wall
   time, and which source dir was used as cwd for the gemc step.
   Read it to know what produced the data. Never hand-edit it.
4. **Default analysis stack: `uproot` + `numpy` + `matplotlib`** on
   the host (out of the container), against
   `<name>/analysis/runs/<id>/out.root`. The ROOT file is
   post-converted from gemc's native `out.evio` by `evio2root`
   inside the container — both files live in the run dir. Anything
   that needs the actual ROOT executable runs inside the container
   via `bin/solid-gemc-run root <macro>`.
5. **Don't commit `solid_gemc/`.** It's an upstream-managed working
   tree that init rebuilds. Same for `<name>/analysis/runs/`,
   `*.root`, `*.hipo`, `__pycache__/`.
6. **Maintain `<name>/log.md` and `<name>/result.md`.** Every
   simulation effort — orchestrator-driven or manual — leaves a
   record in the relevant project's `log.md`. Prepend a new dated
   section capturing four things: the user's **original request**
   (verbatim), the **plan** Claude drew up (six-field spec —
   physics goal, SoLID config, beam, GCard, output, analysis), the
   user's **decision** (approved / edited / plan-only), and the
   **outcome** (run id, status, one-line summary). After a
   `/solid-gemc-claude:solid-gemc-analyze` that produced a
   noteworthy result, add or update a section in `<name>/result.md`
   with key numbers + plot paths. Both files are load-bearing
   handoff documents.

## Typical loop (skill-driven)

The plugin's `solid-gemc` skill auto-loads when you describe a
SoLID-flavored simulation in plain language (PVDIS, SIDIS, J/psi,
He-3, HGC, LGC, GEM, EC, ...). It gap-checks your request against
the six-field spec, presents a plan, and on approval drives:

1. Copy a canonical GCard from `solid_gemc/script/` or
   `solid_gemc/analysis/*/` into `<name>/analysis/<preset>.gcard`,
   applying batch overrides (`USE_GUI=0`, `OUTPUT=evio,out.evio`,
   `N=<n>`) inside the live `<gcard>` block.
2. Run `solid_gemc <gcard>` inside the container from the upstream
   source dir (cwd-relative geometry lookup — gemc 2.9 resolves
   `<detector name="...">` from the process cwd, not the GCard's
   path). Writes `<name>/analysis/runs/<id>/out.evio`.
3. Post-convert `out.evio` → `out.root` via `evio2root` in the
   same container, from the run directory. Capture combined log +
   provenance.
4. Hand off to `/solid-gemc-claude:solid-gemc-analyze
   <name>/analysis/runs/<id>`.

For variations: edit `<name>/analysis/<preset>.gcard` between steps
1 and 2 (beam energy, physics list, target). GCard option
reference: `https://gemc.jlab.org` (mirror in
`reference/gemc_simulation_general_note.md` inside the plugin).

## First run after init — try the upstream HGC study

The recommended first thing to run is the **upstream HGC study** at
`solid_gemc/analysis/hgc_study/` — a fully self-contained example
shipped with solid_gemc. It is the canonical worked example for the
**config + run + analyze** pipeline: GCards
(`cherenkov.gcard`, `cherenkov_batch.gcard`,
`solid_SIDIS_He3_hgc.gcard`, etc.), batch run scripts
(`load.sh` / `run.sh`), and ROOT analysis (`analysis.C`,
`analysis_tree_solid_hgc.C`, the `compare_*.C` comparison
scripts). Two ways in:

- **Skill-driven (recommended):** ask in plain language —
  "run the heavy-gas Cherenkov study on He-3, 100 events" — and the
  `solid-gemc` skill drives the loop end-to-end. It will create a
  fresh project subdir (or use a named one you provide) and write
  outputs there.
- **Upstream-direct:** `bin/solid-gemc-run shell`, then
  `cd solid_gemc/analysis/hgc_study` and follow upstream's
  `./run.sh`. The wrapper binds your workspace to its host path
  inside the container and sets PWD there, so paths are the same in
  and out. Use `bin/solid-gemc-run root analysis.C` for the ROOT
  analysis scripts without a host ROOT install.

## Reference example for custom detectors

If you need to author your own detector (factory text files that
gemc loads via `<detector name="..." factory="TEXT" ...>`), the
canonical worked example is upstream `solid_gemc/geometry/hgc_moved/`.
Mirror its pattern under `<name>/geometry/`:

- `<sub>_geometry.pl`, `_materials.pl`, `_hit.pl`, `_mirror.pl`,
  `_virtualplane.pl` — Perl generators (the editable source-of-
  truth in solid_gemc's convention).
- `<sub>__geometry_Original.txt`, `__materials_Original.txt`,
  `__hit_Original.txt`, `__mirrors_Original.txt`, `__bank.txt` —
  generated text files (what gemc actually reads at runtime).
- `config_<sub>.dat` — parameter file the Perl generators consume.

The plugin's v0.0.2 surface doesn't include a custom-detector
authoring slash command — for that work, follow upstream conventions
in `solid_gemc/geometry/hgc_moved/` directly (edit the `.pl`,
regenerate the `.txt`, reference from your GCard with
`<detector name="..." factory="TEXT" ...>`).

## When something fails

- GCard parse error → `bin/solid-gemc-run validate-gcard <name>/analysis/<gcard>`.
- `solid_gemc` crashes at runtime → `<name>/analysis/runs/<id>/log.txt`;
  usually the failing volume, material, or magnet field config.
- Missing binary at `solid_gemc/source/2.9/solid_gemc` → re-run
  `/solid-gemc-claude:solid-gemc-init` or `bin/solid-gemc-run build`.
- Image missing → `bin/solid-gemc-run info` shows `[not pulled]`; run
  `bin/solid-gemc-run pull`.
