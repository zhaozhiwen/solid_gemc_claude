# CLAUDE.md — solid_gemc workspace

Rules for the agent (Claude Code or Codex) in this solid_gemc simulation
workspace, made by the `solid-gemc-claude` plugin. `README.md` is the user's
guide to the same workspace (absent if the user already had a README here).

The **`solid-gemc` skill** drives simulation requests (spec → plan → approval →
run → analyze); let it. Everything runs through `bin/solid-gemc-run`, a launcher
`init` wrote that calls the newest installed plugin wrapper. Paths here are
relative to the workspace root; from a project subdir use `../bin/solid-gemc-run`.
A plain terminal can use it only after an agent session downloaded the image.

## Layout

| Path | Role |
|---|---|
| `<name>/` | One project per study (e.g. `pvdis_ld2`), files flat inside: GCards, macros, detector generators. |
| `<name>/log.md`, `result.md`, `report.html` | The project's handoff documents (non-negotiable 6). |
| `<name>/runs/<id>/` | One run: `gcard.gcard`, `out.evio`, `out.root`, `log.txt`, `config.json`, plots. Gitignored. |
| `solid_gemc/` | JeffersonLab clone, built by `init`: `script/` (canonical GCards), `analysis/`, `geometry/`, `source/2.9/solid_gemc`. Gitignored. |
| `bin/solid-gemc-run` | The launcher (rewritten by each `init`). |

## Non-negotiables

1. **Everything through the wrapper.** Never call `apptainer`, `solid_gemc`,
   `scons` or `root` directly; use `bin/solid-gemc-run` (`exec`, `shell`, `root`).
   The in-container shell is tcsh.
2. **Run directories are immutable.** New analysis is a new script in `<name>/`,
   never an edit inside `runs/<id>/`.
3. **`runs/<id>/config.json` is the provenance record** (GCard, image, solid_gemc
   commit + origin URL, gemc version, events, exit codes, wall time, run folder).
   Read it to know what produced the data; never hand-edit it.
4. **Analysis defaults to container ROOT** on `runs/<id>/out.root` (converted from
   `out.evio` by `evio2root`). `bin/solid-gemc-run analyze <run>` for default plots;
   custom work is a `.C` macro in `<name>/` run with `bin/solid-gemc-run root
   <macro.C>`. That ROOT cannot write PNG: save `.svg` / `.pdf`. Host Python is
   optional: `analyze --python`, or `venv/bin/python` after `setup-python`.
5. **Never commit** `solid_gemc/`, `venv/`, `runs/`, `*.root`, `*.evio`, `*.hipo`.
6. **Keep the handoff documents current**, for skill-driven and manual work alike.
   Prepend to `<name>/log.md` a dated entry with the user's request (verbatim),
   the plan (seven fields: project, physics goal, SoLID config, beam, GCard,
   output, analysis), the user's decision, and the outcome (run id, status, one
   line). After a noteworthy result, update `<name>/result.md` (numbers + plot
   paths; the source of facts) and refresh `<name>/report.html` from it. To share
   a report outside the workspace, make a self-contained copy
   (`<name>/report_portable.html`):
   `python3 "$(bin/solid-gemc-run paths | awk '/^root:/{print $2}')/templates/embed_html.py" <name>/report.html`.

## Running by hand

`bin/solid-gemc-run gcard <preset> <name> --events <n>` copies a canonical GCard
into `<name>/` with batch settings and prints the source dir;
`bin/solid-gemc-run run <name>/<preset>.gcard <source-dir>` runs gemc, converts,
writes `config.json` and plots. **gemc resolves `<detector name=…>` relative to
the folder it runs in**, not the GCard — so `<source-dir>` is the upstream folder
the GCard came from. GCard options: `gemc_simulation_general_note.md` in the
plugin's reference dir (`bin/solid-gemc-run paths`, `reference:` line).

## Custom detectors

Follow upstream `solid_gemc/geometry/hgc_moved/` (and README "Your own detector", if present).
Then: GCard in `<name>/`, run it with `<name>` as the source dir, point upstream
detectors at `../solid_gemc/geometry/…`, and give the detector a new name — an
upstream name would silently load upstream files. "Failed to open geometry file"
means gemc ran from the wrong folder.

## Changing solid_gemc

The clone's `origin` is JeffersonLab, which takes changes only by fork + PR.
Before editing anything in `solid_gemc/` the user wants to keep, warn them; once
they have forked it on GitHub, switch the clone, keeping JeffersonLab as
`upstream`: `git -C solid_gemc remote rename origin upstream`, then
`git -C solid_gemc remote add origin https://github.com/<user>/solid_gemc.git`;
work on a branch and update with `git -C solid_gemc pull upstream master`. Never
`rm -rf solid_gemc`: `init` reuses the clone, and it may hold the user's work.
Study-only changes belong in `<name>/`.

## When something fails

- GCard parse error → `bin/solid-gemc-run validate-gcard <file>`.
- Run failed → `runs/<id>/log.txt` (usually a volume, material or field setting).
- No `solid_gemc/source/2.9/solid_gemc` → `bin/solid-gemc-run init`.
- Image missing (`info` not `[present]`) → `bin/solid-gemc-run pull` from an agent
  session; a plain terminal never downloads it.
