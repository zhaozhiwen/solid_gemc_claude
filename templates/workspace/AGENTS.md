# CLAUDE.md — project rules

Rules for the agent (Claude Code or Codex) inside one study folder
(`study/<name>/`) of a solid_gemc workspace. The workspace rules in
`../../AGENTS.md` (same as `../../CLAUDE.md`) apply too — read them. From this
folder the launcher is `../../bin/solid-gemc-run`.

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

## Working here

- Commands: `../../bin/solid-gemc-run help` (always the installed plugin's version).
- A GCard whose detectors live in this folder runs with this folder as gemc's run
  folder — detector `name=` paths are relative to the run folder. Point upstream
  detectors at `../../solid_gemc/geometry/…`, and give your own detectors new names so
  an upstream copy can't load instead.
- Custom detectors follow upstream `../../solid_gemc/geometry/hgc_moved/` (Perl
  generators → text files gemc reads).
- Plots from the container's ROOT are `.svg` / `.pdf` (it cannot write PNG).
