---
layout: default
title: solid_gemc_claude
---

## See it in action

Two browser-readable reports produced end-to-end by the plugin — same orchestrator, same `bin/solid-gemc-run`, two very different physics goals.

- **[Cherenkov radiator + spherical mirror](report_cherenkov_mirror.html)** &nbsp; 1 GeV e⁻ pencil beam into a 1 m³ CO₂ box; tilted spherical mirror focuses Cherenkov light onto an off-axis sensor. Three-volume detector authored from a plain-English spec.
- **[DDVCS muon / pion PID template at 5 GeV](report_ddvcs_pid.html)** &nbsp; canonical SoLID J/ψ → μ⁺μ⁻ DDVCS geometry (CLEO magnet, LH2 target, forward-angle "moved_full" muon detector); per-layer Edep templates give the J/ψ trigger a quantitative μ/π separation handle.
{:.demo-list}

## Install

In Claude Code:

```text
/plugin marketplace add zhaozhiwen/solid_gemc_claude
/plugin install solid-gemc-claude@solid-gemc-claude
```

In Codex CLI:

```text
codex plugin marketplace add zhaozhiwen/solid_gemc_claude
codex plugin add solid-gemc-claude@solid-gemc-claude
```

apptainer can't run inside Codex's sandbox: if a run fails with `operation not permitted`, set `/permissions` to **Ask for approval** so Codex asks before running the container. If Codex says its own sandbox failed to start, read-only commands will ask too — that's the host's `bubblewrap` (test with `bwrap --ro-bind / / true`), not the plugin; runs still work.

To upgrade later, see [Updating](#updating). [Apptainer](https://apptainer.org) ≥ 1.4 must already be on the host; the plugin pulls its pinned `.sif` on first use via `wget`.

## Quickstart

There are no slash commands. The `solid-gemc` orchestrator skill auto-loads on any SoLID-flavored request (Claude Code or Codex CLI), gap-checks a seven-field spec (project name, physics goal, SoLID config, beam, GCard, output, analysis), shows a plan, and runs it on approval — driving everything through `bin/solid-gemc-run` (bootstrap the workspace, pick + edit a GCard, run `solid_gemc`, convert EVIO → ROOT, record provenance, plot).

**1. Set up a workspace — once, right after installing (5–15 min).** Start your agent in an empty folder; it becomes your workspace (the ~1 GB `solid_gemc` build and all run outputs go there). Then ask it to initialize:

```sh
mkdir ~/solid_ws && cd ~/solid_ws
claude            # or: codex
```

```text
Initialize the solid_gemc workspace
```

The agent says what setup will do, then downloads the ~1.7 GB container image (first time only; every workspace shares it), clones `solid_gemc` and builds it, reporting each step. On Codex, if it says the container was blocked, type `/permissions`, choose **Ask for approval**, then `continue`.

**2. Run a study** in the same folder. A good first request is "Run the heavy-gas Cherenkov study on He-3, 100 events"; the agent shows a plan and waits for your approval. (Skip step 1 and your first study request offers to run the setup first.) Results land in `study/<project>/runs/<id>/` and `study/<project>/report.html`; the workspace's own `README.md` explains the rest. A bigger request, once that works:

```text
Learn the examples at solid_gemc repo "solid_gemc/analysis/hgc_study/" and "solid_gemc/geometry/hgc_moved/",
Do the heavy gas Cherenkov simulation on SIDIS He3 moved configuration with 1000 events of 5 GeV pi- at 10 degree theta angle and full phi angle,
then plot number of photoelectron yield in various illustrative ways,
verify the sim result with physics analytic calculation,
finally show me the results in an html file
```

Setup (`bin/solid-gemc-run init`) runs once per workspace: pull the `.sif`, clone `solid_gemc`, run both scons builds, scaffold the workspace. After it, two upstream worked examples live in your workspace, both self-contained:

| Example | What it teaches |
|---|---|
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards, batch run scripts, ROOT analysis macros |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators, the factory text files they emit, and the GCard wiring |

Init writes `bin/solid-gemc-run` into your workspace — a launcher that runs the newest installed plugin wrapper, from the agent or a plain terminal (a terminal uses an already-downloaded image; it never downloads one). `bin/solid-gemc-run run <project>/<gcard> <source-dir>` is one whole run (gemc, `evio2root` with the GCard's detector banks, `config.json`, plots); `bin/solid-gemc-run analyze <project>/runs/<id>` re-plots the post-converted `out.root` with ROOT in the container (SVG + `plots.pdf` + per-branch stats; `--python` for host uproot PNGs). `bin/solid-gemc-run shell` drops you into a tcsh prompt with the env exported, to follow upstream's scripts directly.

## Using your workspace

Commands below run from the workspace root (`../../bin/solid-gemc-run` from inside a
project). `bin/solid-gemc-run help` lists every command for the version you have
installed.

### Running by hand

```sh
bin/solid-gemc-run gcard <preset> study/<name> --events 1000   # copy a canonical GCard into study/<name>/
bin/solid-gemc-run run study/<name>/<preset>.gcard <source-dir> # gemc → out.root → plots
bin/solid-gemc-run analyze study/<name>/runs/<id>                # re-plot a run
```

`gcard` prints the `<source-dir>` to use: the upstream folder the GCard came
from, because gemc finds detectors relative to the folder it runs in. Edit
`study/<name>/<preset>.gcard` between the two steps to change beam, target or
physics. `--no-optical` turns off optical-photon recording (faster, smaller
output).

Plots are SVG plus a combined `plots.pdf` (the container's ROOT can't write PNG).
For PNGs from host Python: `bin/solid-gemc-run analyze --python <run>`.

Other useful commands:

| Command | Does |
|---|---|
| `bin/solid-gemc-run root <macro.C>` | Run your own ROOT macro in the container; no ROOT install needed. With arguments, quote the call once for your shell: `bin/solid-gemc-run root 'm.C("out.root")'`. |
| `bin/solid-gemc-run shell` | Interactive shell (tcsh) in the container, e.g. to follow upstream's `run.sh`. |
| `bin/solid-gemc-run validate-gcard <file>` | Check a GCard for XML errors. |
| `bin/solid-gemc-run info` | Plugin version in use, container image and where it is cached, solid_gemc repo, gemc and apptainer versions. |
| `bin/solid-gemc-run help` | All commands. |

From inside a study folder use `../../bin/solid-gemc-run`. The command works in a
plain terminal too, once an agent session has downloaded the container image.

### Your own detector

Copy the pattern of `solid_gemc/geometry/hgc_moved/` into your project folder:
Perl generators (`<sub>_geometry.pl`, `_materials.pl`, `_hit.pl`, …) plus a
`config_<sub>.dat`, which produce the `.txt` files gemc reads. Regenerate them
from `study/<name>/` with `../../bin/solid-gemc-run exec "./<sub>.pl config_<sub>.dat"`.

Then run it with your project folder as gemc's run folder —
`bin/solid-gemc-run run study/<name>/<gcard> study/<name>` from the workspace root, or
`../../bin/solid-gemc-run run <gcard> .` from inside it — point
upstream detectors in the GCard at the clone (`name="../../solid_gemc/geometry/…"`),
and give your detector a new name so it can't be confused with an upstream one.

### Changing solid_gemc itself

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

### Sharing a report

`report.html` shows plots from `runs/` by relative path, so it only renders
inside this folder. To send it elsewhere, make a self-contained copy:

```sh
ROOT=$(bin/solid-gemc-run paths | awk '/^root:/{print $2}')
python3 "$ROOT/templates/embed_html.py" study/<name>/report.html   # writes report_portable.html
```

### When something fails

- **GCard error** → `bin/solid-gemc-run validate-gcard study/<name>/<gcard>`.
- **Run failed** → read `study/<name>/runs/<id>/log.txt`; usually a volume, material or
  field setting.
- **"Failed to open geometry file"** → gemc ran from the wrong folder; see "Your own detector" above.
- **Missing `solid_gemc/source/2.9/solid_gemc`** → re-run `bin/solid-gemc-run init`.
- **Image missing** (`info` shows `[not pulled]`, or `unresolved` in a plain
  terminal) → ask your agent to run `bin/solid-gemc-run pull`; a plain terminal
  never downloads it.

## Updating

Update the plugin, then start a new agent session:

- Claude Code, in a session: `/plugin` → **Marketplaces** → `solid-gemc-claude` →
  **Update marketplace** (refreshes it and updates the plugin). In a terminal:
  `claude plugin marketplace update solid-gemc-claude`, then
  `claude plugin update solid-gemc-claude@solid-gemc-claude`. The new version loads in
  your next session (or after `/reload-plugins`). Automatic updates are off by default
  for this marketplace; turn them on in the same menu with **Enable auto-update**.
- Codex CLI: `codex plugin marketplace upgrade` — it refreshes the marketplace and
  updates the installed plugin (the old version is removed).

Existing workspaces need nothing: their `bin/solid-gemc-run` always runs the newest
installed plugin, and the files `init` copied hold only rules that rarely change.
`bin/solid-gemc-run info` shows the version in use. Re-run `init` only when a
release note says so; it never touches your projects or runs.

## What it does

- **NL-driven simulation as a first-class step.** The orchestrator turns a plain-English study spec into a validated GCard + run command. Edit the GCard or re-describe to iterate.
- **Single runtime seam.** All `gemc`, `xmllint`, ROOT, and `evio2root` calls go through `bin/solid-gemc-run`. The container tag is pinned in one place. No host-side ROOT required.
- **solid_gemc clone for reading.** Init clones JeffersonLab/solid_gemc, which takes changes only as fork → pull request. To keep or submit edits, point the clone at your fork (see "Changing solid_gemc itself" below).
- **EVIO + post-convert to ROOT.** `gemc` 2.9 writes EVIO natively; the wrapper post-converts to ROOT inside the same container and analysis runs on the container's ROOT (host uproot optional). Both files end up in `runs/<id>/`.

## Requirements

- [Apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git` on the host. (No host-side `tcsh` needed — the wrapper invokes `tcsh` *inside* the container.)
- Python 3 on the host; Python 3.9+ with `uproot numpy matplotlib` only for the optional `analyze --python`.
- ~1.7 GB in your home dir for the cached JLabCE 2.5 image, plus ~1 GB per workspace for the cloned + built `solid_gemc` tree. The image lives in the agent tool's persistent plugin data dir (`~/.claude/plugins/data/solid-gemc-claude-solid-gemc-claude/` or `~/.codex/plugins/data/solid-gemc-claude-solid-gemc-claude/`), so it survives plugin updates and is shared across workspaces; uninstalling the plugin may delete it.
- Claude Code (plugin support) **or** OpenAI Codex CLI (Agent Skills).

## Testing

See [`tests/README.md`](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/tests/README.md).

## Links

- [License (MIT)](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/LICENSE)
- [solid_gemc upstream](https://github.com/JeffersonLab/solid_gemc)

## Acknowledgments

- **solid_gemc** — the SoLID experiment's GEMC-based simulation. See [github.com/JeffersonLab/solid_gemc](https://github.com/JeffersonLab/solid_gemc).
- **GEMC** — the geometry-and-tracking framework underneath. See [gemc.jlab.org](https://gemc.jlab.org).
- **JLabCE 2.5 container** — built and maintained at Jefferson Lab; see [github.com/JeffersonLab/solid_release](https://github.com/JeffersonLab/solid_release).
