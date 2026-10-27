# AGENTS.md — solid_gemc workspace

Rules for the agent (Claude Code or Codex) in this solid_gemc simulation
workspace, made by the `solid-gemc-claude` plugin. This file holds only rules,
which rarely change; add a rule here, not in `CLAUDE.md` (that is just the import
`@AGENTS.md`, so both tools read this file). How to do things lives where it
updates with the plugin:

- **Simulation requests** — the `solid-gemc` skill (spec → plan → approval → run →
  analyze); let it drive.
- **Commands and options** — `bin/solid-gemc-run help` (the launcher `init` wrote;
  it always runs the newest installed plugin; `info` shows which version). From a
  study folder use `../../bin/solid-gemc-run`. A plain terminal can use it only
  after an agent session downloaded the image.
- **Physics and gemc knowledge, at every stage** — planning, GCard edits,
  interpreting results, physics questions, failures: the plugin's `reference/` dir
  (`bin/solid-gemc-run paths`, `reference:` line). Look things up there rather than
  answering from memory: start at its `README.md` index, grep for the term, read
  only that section (the files are long), cite it. `README.md` here is the user's
  guide.

## Layout

| Path | Role |
|---|---|
| `study/<name>/` | One folder per study (e.g. `pvdis_ld2`), files flat inside: GCards, macros, detector files. |
| `study/<name>/log.md`, `result.md`, `report.html` | The project's handoff documents (rule 6). |
| `study/<name>/runs/<id>/` | One run: frozen GCard, `out.evio`, `out.root`, `log.txt`, `config.json`, plots. Gitignored. |
| `solid_gemc/` | JeffersonLab clone, built by `init` (`script/` holds the canonical GCards). Gitignored. |
| `bin/solid-gemc-run` | The launcher. |

## Rules

1. **Everything through the wrapper.** Never call `apptainer`, `solid_gemc`,
   `scons` or `root` directly; use `bin/solid-gemc-run`. The in-container shell is
   tcsh.
2. **Run directories are immutable.** New analysis is a new script in `study/<name>/`,
   never an edit inside `runs/<id>/`.
3. **`runs/<id>/config.json` is the provenance record.** Read it to know what
   produced the data; never hand-edit it.
4. **Analysis runs on the container's ROOT** by default; it cannot write PNG, so
   save `.svg` / `.pdf`. Host Python is optional, only when the user asks.
5. **Never commit** `solid_gemc/`, `venv/`, `runs/`, `*.root`, `*.evio`, `*.hipo`.
6. **Keep the handoff documents current**, for skill-driven and manual work alike:
   every request gets an entry at the top of `study/<name>/log.md` (format in that file);
   a noteworthy result goes into `study/<name>/result.md` (the source of facts) and
   `study/<name>/report.html` is refreshed from it. To share a report outside the
   workspace, make a self-contained copy with `templates/embed_html.py` from the
   plugin root (`bin/solid-gemc-run paths`, `root:` line).
7. **gemc finds detectors relative to the folder it runs in**, not the GCard's
   folder. A canonical GCard runs from the upstream folder it came from; a GCard
   with detectors in `study/<name>/` runs with that folder as the run folder, points
   upstream detectors at `../../solid_gemc/geometry/…`, and gives its own detectors
   new names (an upstream name would silently load upstream files). "Failed to open
   geometry file" means the wrong run folder.
8. **`solid_gemc/` belongs to JeffersonLab** (changes only by fork + pull request).
   Before editing anything there the user wants to keep, warn them; once they have
   forked it: `git -C solid_gemc remote rename origin upstream`, then
   `git -C solid_gemc remote add origin https://github.com/<user>/solid_gemc.git`;
   update with `git -C solid_gemc pull upstream master`. Never
   `rm -rf solid_gemc` — `init` reuses the clone and it may hold their work.
   Changes one study needs belong in `study/<name>/`.
