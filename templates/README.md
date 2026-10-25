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
| `study/<name>/` | One study (project) per folder, e.g. `study/pvdis_ld2/`. Created by the agent when you start a study. |
| `study/<name>/log.md` | Every request you made, the plan, your decision, and the outcome — newest first. |
| `study/<name>/result.md` | Key numbers and plot paths from runs worth keeping. |
| `study/<name>/report.html` | A readable summary of the study; open it in a browser. |
| `study/<name>/runs/<id>/` | One folder per run (`<id>` = UTC time + random suffix): the frozen `gcard.gcard`, `out.evio`, `out.root`, `log.txt`, `config.json`, and plots. Never edited after the run. |
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

## More

- How to run things by hand, your own detector, changing solid_gemc, sharing a
  report, troubleshooting, updating:
  <https://zhaozhiwen.github.io/solid_gemc_claude/#using-your-workspace>
- Every command for the installed version: `bin/solid-gemc-run help`; the version
  in use: `bin/solid-gemc-run info`.
