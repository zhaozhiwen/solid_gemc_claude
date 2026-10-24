# solid_gemc workspace

This folder is a SoLID simulation workspace made by the `solid-gemc-claude`
plugin. You describe a study in plain language to your agent (Claude Code or
Codex); it plans the run, asks for your approval, then runs SoLID GEMC in a
container and plots the result. Everything is recorded in this folder.

`AGENTS.md` / `CLAUDE.md` are the rules your agent follows here; this README is
for you.

## What's here

| Path | What it is |
|---|---|
| `<name>/` | One study (project) per folder, e.g. `pvdis_ld2/`, `sidis_he3_hgc/`. Created by the agent when you start a study. |
| `<name>/log.md` | Every request you made, the plan, your decision, and the outcome — newest first. |
| `<name>/result.md` | Key numbers and plot paths from runs worth keeping. |
| `<name>/report.html` | A readable summary of the study; open it in a browser. |
| `<name>/runs/<id>/` | One folder per run (`<id>` = UTC time + random suffix): the frozen `gcard.gcard`, `out.evio`, `out.root`, `log.txt`, `config.json`, and plots. Never edited after the run. |
| `solid_gemc/` | The SoLID GEMC source, cloned from JeffersonLab and built by `init`. Geometry, canonical GCards (`solid_gemc/script/`) and worked examples (`solid_gemc/analysis/`) live here. |
| `bin/solid-gemc-run` | The command that runs everything (gemc, ROOT, conversion) inside the container. |
| `venv/` | Optional Python environment for `analyze --python`; appears on first use. |

`runs/`, `solid_gemc/`, `venv/` and data files (`*.root`, `*.evio`) are
gitignored, so you can put the workspace under git and commit only your GCards,
scripts and notes. The ~1.7 GB container image is not in this folder; it lives in
your agent tool's plugin data and is shared by all workspaces.

## Working with the agent

Ask for what you want, for example:

- "Run the heavy-gas Cherenkov study on He-3, 100 events" — a good first run
  (the upstream example in `solid_gemc/analysis/hgc_study/`).
- "Simulate PVDIS on LD2 with 11 GeV electrons, 10000 events, and plot Q²."

The agent asks for anything missing (project name, configuration, beam, number
of events, what to plot), shows you a plan, and does nothing until you approve
it. After the run it reports the run folder, the plots, and updates `log.md`.

## Doing it by hand

```sh
bin/solid-gemc-run gcard <preset> <name> --events 1000   # copy a canonical GCard into <name>/
bin/solid-gemc-run run <name>/<preset>.gcard <source-dir> # gemc → out.root → plots
bin/solid-gemc-run analyze <name>/runs/<id>                # re-plot a run
```

`gcard` prints the `<source-dir>` to use: the upstream folder the GCard came
from, because gemc finds detectors relative to the folder it runs in. Edit
`<name>/<preset>.gcard` between the two steps to change beam, target or
physics. `--no-optical` turns off optical-photon recording (faster, smaller
output).

Plots are SVG plus a combined `plots.pdf` (the container's ROOT can't write PNG).
For PNGs from host Python: `bin/solid-gemc-run analyze --python <run>`.

Other useful commands:

| Command | Does |
|---|---|
| `bin/solid-gemc-run root <macro.C>` | Run your own ROOT macro in the container; no ROOT install needed. |
| `bin/solid-gemc-run shell` | Interactive shell (tcsh) in the container, e.g. to follow upstream's `run.sh`. |
| `bin/solid-gemc-run validate-gcard <file>` | Check a GCard for XML errors. |
| `bin/solid-gemc-run info` | Container image and where it is cached, solid_gemc repo, gemc and apptainer versions. |
| `bin/solid-gemc-run help` | All commands. |

From inside a project folder use `../bin/solid-gemc-run`. The command works in a
plain terminal too, once an agent session has downloaded the container image.

## Your own detector

Copy the pattern of `solid_gemc/geometry/hgc_moved/` into your project folder:
Perl generators (`<sub>_geometry.pl`, `_materials.pl`, `_hit.pl`, …) plus a
`config_<sub>.dat`, which produce the `.txt` files gemc reads. Regenerate them
from `<name>/` with `../bin/solid-gemc-run exec "./<sub>.pl config_<sub>.dat"`.

Then run it with your project folder as gemc's run folder —
`bin/solid-gemc-run run <name>/<gcard> <name>` from the workspace root, or
`../bin/solid-gemc-run run <gcard> .` from inside it — point
upstream detectors in the GCard at the clone (`name="../solid_gemc/geometry/…"`),
and give your detector a new name so it can't be confused with an upstream one.

## Changing solid_gemc itself

`solid_gemc/` is a clone of JeffersonLab's repository, which accepts changes only
as a pull request from a fork. Before editing files there that you want to keep,
fork JeffersonLab/solid_gemc on GitHub and point the clone at your fork:

```sh
git -C solid_gemc remote rename origin upstream
git -C solid_gemc remote add origin https://github.com/<you>/solid_gemc.git
git -C solid_gemc switch -c <topic>      # work here, then push and open a PR
git -C solid_gemc pull upstream master   # stay in sync with JeffersonLab
bin/solid-gemc-run build solid_gemc      # rebuild after pulling or editing
```

Don't delete `solid_gemc/` once it holds your work. Each run's `config.json`
records the clone's URL and commit, so results stay traceable.

## Sharing a report

`report.html` shows plots from `runs/` by relative path, so it only renders
inside this folder. To send it elsewhere, make a self-contained copy:

```sh
ROOT=$(bin/solid-gemc-run paths | awk '/^root:/{print $2}')
python3 "$ROOT/templates/embed_html.py" <name>/report.html   # writes report_portable.html
```

## When something fails

- **GCard error** → `bin/solid-gemc-run validate-gcard <name>/<gcard>`.
- **Run failed** → read `<name>/runs/<id>/log.txt`; usually a volume, material or
  field setting.
- **"Failed to open geometry file"** → gemc ran from the wrong folder; see "Your own
  detector".
- **Missing `solid_gemc/source/2.9/solid_gemc`** → re-run `bin/solid-gemc-run init`.
- **Image missing** (`info` shows `[not pulled]`, or `unresolved` in a plain
  terminal) → ask your agent to run `bin/solid-gemc-run pull`; a plain terminal
  never downloads it.
