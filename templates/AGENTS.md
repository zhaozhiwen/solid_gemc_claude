# CLAUDE.md — solid_gemc workspace

Rules for the agent (Claude Code or Codex) working in this solid_gemc
simulation workspace. The `solid-gemc-claude` plugin scaffolded it.

`bin/solid-gemc-run init` (which created this workspace) also
cloned and built solid_gemc into `./solid_gemc/` — that's where SoLID
geometry, the canonical GCards (`solid_gemc/script/`), and the built
binary (`solid_gemc/source/2.9/solid_gemc`) live.

There are **no slash commands**. The whole workflow — bootstrap
(`init`), picking + editing a GCard, running gemc, converting EVIO →
ROOT, and plotting (`analyze`) — runs through `bin/solid-gemc-run`,
driven by the **`solid-gemc` orchestrator skill** which auto-loads on
SoLID-flavored natural-language requests (Claude Code or Codex CLI). You
can also call `bin/solid-gemc-run` directly (e.g. following upstream's
`hgc_study/run.sh` pattern).

**The wrapper.** `bin/solid-gemc-run` in this workspace is a small
launcher that `init` wrote; on every call it runs the newest installed
plugin wrapper, so it keeps working across plugin updates. Paths in this
file are relative to the workspace root — from inside a project subdir,
use `../bin/solid-gemc-run`. It also works from a plain terminal, but
only after an agent session has downloaded the container image (a
terminal never downloads it).

## Workspace layout

Each SoLID study (or detector-authoring effort) lives in its own
**project subdirectory** at the workspace root, mirroring how
upstream organizes `solid_gemc/analysis/hgc_study/` and
`solid_gemc/geometry/hgc_moved/` as separate self-contained dirs.

| Path | Role |
|------|------|
| `<name>/`           | One project. Rename `<name>` to your study (e.g. `pvdis_ld2`, `sidis_he3_hgc`, `jpsi_lh2`). One subdir per study; multiple studies coexist in one workspace. Files inside (GCards, run outputs, analysis scripts, Perl detector generators) live flat — no enforced subdir split, mirroring the layout style of upstream `solid_gemc/analysis/hgc_study/`. |
| `<name>/CLAUDE.md`  | Per-project rules (loaded as Claude context when the session's cwd is inside the project). |
| `<name>/log.md`     | Chronological work log for this project. Prepend new entries at top. |
| `<name>/result.md`  | Per-run findings, with paths to `<name>/runs/<id>/`. |
| `<name>/report.html` | Browser-readable summary (rich text + plots referenced relatively from `runs/<id>/`). Opens via `file://` inside the workspace tree; for off-host sharing run the embed script (see non-negotiable #6). |
| `<name>/runs/<id>/` | Per-run output dirs. The orchestrator skill writes `gcard.gcard`, `out.evio`, `out.root`, `log.txt`, `config.json` per run. **Gitignored.** |
| `solid_gemc/`       | Cloned + built upstream tree (init artifact). **Gitignored.** Re-running init rebuilds it but keeps the existing clone; to update, `git -C solid_gemc pull` then re-run init. A clone of JeffersonLab's repo, for reading and running — see "Changing solid_gemc itself". |
| `bin/solid-gemc-run` | Launcher for the plugin wrapper (init artifact, rewritten by each init). |

## Non-negotiables

1. **All solid_gemc / scons / ROOT calls go through the plugin's wrapper.**
   Never invoke `apptainer`, `solid_gemc`, `scons`, or `root` directly.
   Use `bin/solid-gemc-run` (or the orchestrator skill that wraps it).
   In-container shell is tcsh.
2. **Run directories are immutable.** Once a run finishes, treat
   `<name>/runs/<id>/` as read-only. New analysis = new
   script in `<name>/`, not edits in the run directory.
3. **`<name>/runs/<id>/config.json` is the provenance record.**
   It records the GCard, the .sif name, the solid_gemc commit SHA and
   the clone's `origin` URL (JeffersonLab, or your fork),
   GEMC_VERSION, n_events, the gemc + evio2root exit codes, wall
   time, and which source dir was used as cwd for the gemc step.
   Read it to know what produced the data. Never hand-edit it.
4. **Default analysis stack: ROOT inside the container**, against
   `<name>/runs/<id>/out.root`. The ROOT file is post-converted from
   gemc's native `out.evio` by `evio2root` inside the container —
   both files live in the run dir. `bin/solid-gemc-run analyze`
   gives default plots; custom analysis is a `.C` macro in `<name>/`
   run with `bin/solid-gemc-run root <macro.C>`. The container's ROOT
   is batch-only and cannot write PNGs: save plots as `.svg` / `.pdf`.
   Host Python (`uproot` + `numpy` + `matplotlib`) is optional:
   `bin/solid-gemc-run analyze --python` (PNGs) or a script run with
   `venv/bin/python` after `bin/solid-gemc-run setup-python`.
5. **Don't commit `solid_gemc/`.** It's an upstream-managed working
   tree that init rebuilds. Same for `venv/` (the optional Python venv),
   `<name>/runs/`, `*.root`, `*.hipo`, `__pycache__/`. (The ~1.7 GB
   `.sif` lives outside the workspace, in the agent tool's plugin
   data dir.)
6. **Maintain `<name>/log.md`, `<name>/result.md`, and
   `<name>/report.html`.** Every simulation effort — orchestrator-
   driven or manual — leaves a record in the relevant project's
   `log.md`. Prepend a new dated section capturing four things: the
   user's **original request** (verbatim), the **plan** the agent drew
   up (seven-field spec — project name, physics goal, SoLID config,
   beam, GCard, output, analysis), the user's **decision** (approved /
   edited / plan-only), and the **outcome** (run id, status, one-line
   summary). After an `analyze` run that produced a
   noteworthy result, add or update a section in `<name>/result.md`
   with key numbers + plot paths, and refresh `<name>/report.html`
   so the rendered summary (overview, configuration table, headline
   figures, run index) stays in sync. `result.md` is the source for
   facts; `report.html` is the presentation layer. All three are
   load-bearing handoff documents.

   When a `report.html` needs to leave the workspace tree (committed
   to a public `docs/` folder, emailed, attached to a ticket), first
   run the plugin's portability script. Find the plugin root with
   `bin/solid-gemc-run paths` (the `root:` line):

   ```sh
   ROOT=$(bin/solid-gemc-run paths | awk '/^root:/{print $2}')
   python3 "$ROOT/templates/embed_html.py" <name>/report.html
   ```

   It rewrites each `<img src="runs/<id>/*.svg">` (or `.png`) as an inline
   base64 data URI and writes a sibling `<name>/report_portable.html`.
   Ship the `_portable.html`; the plain `report.html` keeps relative
   paths and only renders correctly from inside the workspace tree.

## Typical loop (skill-driven)

The plugin's `solid-gemc` skill auto-loads when you describe a
SoLID-flavored simulation in plain language (PVDIS, SIDIS, J/psi,
He-3, HGC, LGC, GEM, EC, ...). It gap-checks your request against
the seven-field spec, presents a plan, and on approval drives:

1. Copy a canonical GCard from `solid_gemc/script/` or
   `solid_gemc/analysis/*/` into `<name>/<preset>.gcard`,
   applying batch overrides (`USE_GUI=0`, `OUTPUT=evio,out.evio`,
   `N=<n>`) inside the live `<gcard>` block.
2. Run `solid_gemc <gcard>` inside the container from the upstream
   source dir (cwd-relative geometry lookup — gemc 2.9 resolves
   `<detector name="...">` from the process cwd, not the GCard's
   path). Writes `<name>/runs/<id>/out.evio`.
3. Post-convert `out.evio` → `out.root` via `evio2root` in the
   same container, from the run directory. Capture combined log +
   provenance.
4. Run `bin/solid-gemc-run analyze <name>/runs/<id>`.

For variations: edit `<name>/<preset>.gcard` between steps
1 and 2 (beam energy, physics list, target). GCard option
reference: `https://gemc.jlab.org` (mirror in
`gemc_simulation_general_note.md` under the plugin's `reference/` dir —
`bin/solid-gemc-run paths` prints its location on the `reference:` line).

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

## Changing solid_gemc itself

`init` clones `https://github.com/JeffersonLab/solid_gemc` as `origin`.
Upstream accepts changes only as **fork → modify → pull request** (its
`README.md`), so treat this clone as read-mostly: you can't push to it.
Before editing files in `solid_gemc/` that you want to keep or share,
warn the user and switch the clone to their fork, keeping JeffersonLab
as `upstream`:

```sh
# after forking JeffersonLab/solid_gemc on GitHub
git -C solid_gemc remote rename origin upstream
git -C solid_gemc remote add origin https://github.com/<you>/solid_gemc.git
git -C solid_gemc fetch origin
# work on a branch, push to the fork, open a PR against JeffersonLab:
git -C solid_gemc switch -c <topic>
git -C solid_gemc push -u origin <topic>
# stay in sync with JeffersonLab:
git -C solid_gemc pull upstream master
```

Never `rm -rf solid_gemc` once it holds your work — init reuses an
existing clone. Changes that only your study needs (a custom
detector, a modified GCard) belong in `<name>/`, not in the clone.
Each run's `config.json` records the clone's `origin` URL and commit
SHA; a commit that exists only on your fork is reproducible by others
only after you push it.

## Reference example for custom detectors

If you need to author your own detector (factory text files that
gemc loads via `<detector name="..." factory="TEXT" ...>`), the
canonical worked example is upstream `solid_gemc/geometry/hgc_moved/`.
Mirror its pattern directly under `<name>/` (files live mixed with
the rest of the project, no `geometry/` subdir):

- `<sub>_geometry.pl`, `_materials.pl`, `_hit.pl`, `_mirror.pl`,
  `_virtualplane.pl` — Perl generators (the editable source-of-
  truth in solid_gemc's convention).
- `<sub>__geometry_Original.txt`, `__materials_Original.txt`,
  `__hit_Original.txt`, `__mirrors_Original.txt`, `__bank.txt` —
  generated text files (what gemc actually reads at runtime).
- `config_<sub>.dat` — parameter file the Perl generators consume.

Regenerate the `.txt` files from `<name>/`:
`../bin/solid-gemc-run exec "./<sub>.pl config_<sub>.dat"`.

**Run gemc from `<name>/`.** A detector `name=` in a GCard is a path
relative to the folder gemc runs in, not to the GCard. The skill's
default run folder is the upstream folder the canonical GCard came
from, and from there your `<name>/` files are not found ("Failed to
open geometry file … Exiting."). So for a custom detector:

- put the GCard in `<name>/` and run it with cwd = `<name>/`;
- point upstream detectors at the clone, e.g.
  `name="../solid_gemc/geometry/hgc_moved/solid_SIDIS_hgc"`;
- give your detector a new name — a copy that keeps an upstream name
  would silently load the upstream files if run from the upstream folder.

The plugin has no custom-detector authoring surface beyond this; follow
upstream conventions in `solid_gemc/geometry/hgc_moved/`.

## When something fails

- GCard parse error → `bin/solid-gemc-run validate-gcard <name>/<gcard>`.
- `solid_gemc` crashes at runtime → `<name>/runs/<id>/log.txt`;
  usually the failing volume, material, or magnet field config.
- Missing binary at `solid_gemc/source/2.9/solid_gemc` → re-run
  `bin/solid-gemc-run init` or `bin/solid-gemc-run build`.
- Image missing → `bin/solid-gemc-run info` shows `[not pulled]` or an
  unresolved cache; run `bin/solid-gemc-run pull` from a Claude Code or
  Codex session (a plain terminal never downloads it).
