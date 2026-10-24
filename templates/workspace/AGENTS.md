# CLAUDE.md — project rules

Rules for the agent (Claude Code or Codex) inside one project of a solid_gemc
workspace. The workspace rules in `../AGENTS.md` (same as `../CLAUDE.md`) apply
too — read them. From this folder the launcher is `../bin/solid-gemc-run`.

## Layout

Files live flat in this folder; add subfolders only if the project outgrows that.

| Path | Role |
|---|---|
| `log.md` | Every request, plan, decision and outcome, newest first; format inside the file. |
| `result.md` | Noteworthy runs: key numbers + plot paths; the source of facts for `report.html`. |
| `report.html` | Browser summary of `result.md`, plots by relative path into `runs/<id>/`. |
| `<preset>.gcard` | GCards copied in by `bin/solid-gemc-run gcard`; edit freely. |
| `runs/<id>/` | One run, written by `run`; read-only once finished. |
| `*.C`, `*.py`, `*.pl`, `*.txt`, `*.dat` | Analysis macros and custom-detector files. |

## Running from here

- Run a GCard with this folder as the gemc run folder:
  `../bin/solid-gemc-run run <gcard> .` — needed whenever the GCard names
  detectors stored here (detector `name=` paths are relative to the run folder).
  Point upstream detectors at `../solid_gemc/geometry/…`, and give your own
  detector a new name so an upstream copy can't load instead.
- Re-plot: `../bin/solid-gemc-run analyze runs/<id>`; custom analysis:
  `../bin/solid-gemc-run root <macro.C>` (save `.svg`/`.pdf`, not PNG).
- Regenerate custom-detector text files:
  `../bin/solid-gemc-run exec "./<sub>.pl config_<sub>.dat"`. Pattern to follow:
  `../solid_gemc/geometry/hgc_moved/` (and `../README.md` "Your own detector", if present).
