# solid-gemc-claude

A plugin for running [solid_gemc](https://github.com/JeffersonLab/solid_gemc)
(the SoLID experiment's GEMC-based simulation) from **Claude Code** or
**OpenAI Codex CLI**. solid_gemc, GEMC, Geant4, and ROOT all live in a pinned
[JLabCE 2.5](https://github.com/JeffersonLab/solid_release) apptainer image;
analysis runs on that ROOT inside the container (host-side
[`uproot`](https://github.com/scikit-hep/uproot5) is an option).

> The name keeps its `-claude` suffix for historical/repo-stability reasons;
> the plugin is not Claude-specific. The whole workflow runs through one
> platform-neutral wrapper (`bin/solid-gemc-run`) and one skill, identical on
> both tools.

**Docs site:** [zhaozhiwen.github.io/solid_gemc_claude](https://zhaozhiwen.github.io/solid_gemc_claude/) (overview, install, demo run reports).

> **Status: v0.0.12.** Dual-platform (Claude Code + Codex CLI). The
> orchestrator skill drives the full simulation loop through the wrapper. See
> [`docs/DESIGN.md`](docs/DESIGN.md) for design intent and the cross-platform
> architecture.

## Requirements

- [apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git` on the host. (No host-side `tcsh` needed — the
  wrapper invokes `tcsh` *inside* the container.)
- Python 3 on the host. Python 3.9+ with `uproot numpy matplotlib` only for the
  optional `analyze --python`.
- ~1.7 GB in your home dir for the cached JLabCE 2.5 image, plus ~1 GB
  per workspace for the cloned + built solid_gemc tree. The image lives
  in the agent tool's persistent plugin data dir
  (`~/.claude/plugins/data/solid-gemc-claude-solid-gemc-claude/` or
  `~/.codex/plugins/data/solid-gemc-claude-solid-gemc-claude/`), so it
  survives plugin updates and is shared across workspaces; uninstalling
  the plugin may delete it.
- Claude Code (plugin support) **or** OpenAI Codex CLI (Agent Skills).

The plugin downloads
[`jeffersonlab_jlabce_tag2.5_digest:sha256:9b9a9ec8c793...sif`](http://webhome.phy.duke.edu/~zz81/simg/jeffersonlab_jlabce_tag2.5_digest:sha256:9b9a9ec8c793035d5bfe6651150b54ac298f5ad17dca490a8039c530d0302008_20220413_s3.9.5.sif)
on first use; URL is pinned in [`bin/solid-gemc-run`](bin/solid-gemc-run).

## Install

One repo serves both tools. Analysis needs no host install: `analyze` runs ROOT
in the container. The optional Python venv installs on the first
`analyze --python` (`bin/solid-gemc-run setup-python` pre-installs it).

### Claude Code

```text
/plugin marketplace add zhaozhiwen/solid_gemc_claude
/plugin install solid-gemc-claude@solid-gemc-claude
```

### Codex CLI

```text
codex plugin marketplace add zhaozhiwen/solid_gemc_claude
codex plugin add solid-gemc-claude@solid-gemc-claude
```

apptainer can't run inside Codex's sandbox, so Codex must be able to ask before
running `solid-gemc-run` outside it. If it doesn't ask (the run fails with
`operation not permitted`), set `/permissions` to **Ask for approval** in the session.

If Codex reports that its own sandbox failed to start, even read-only commands will
ask for approval. That comes from the host's `bubblewrap`, not the plugin — check with
`bwrap --ro-bind / / true` as a normal user; some mount layouts (e.g. a stacked
`/proc/sys/fs/binfmt_misc` mount) make bubblewrap 0.6 fail there. Runs still work.

## First run

**1. Set up a workspace — once, right after installing (5–15 min).** Start your
agent in an empty folder; it becomes your workspace (the ~1 GB solid_gemc build and
all run outputs go there). Then ask it to initialize:

```sh
mkdir ~/solid_ws && cd ~/solid_ws
claude            # or: codex
```

```text
Initialize the solid_gemc workspace
```

The agent says what setup will do, then downloads the ~1.7 GB container image
(first time only; every workspace shares it), clones solid_gemc and builds it,
reporting each step. On Codex, if it says the container was blocked, type
`/permissions`, choose **Ask for approval**, then `continue`.

**2. Run a study** in the same folder, for example "Run the heavy-gas Cherenkov
study on He-3, 100 events". The agent shows a plan and waits for your approval.
(Skip step 1 and your first study request offers to run the setup first.)
Results land in `study/<project>/runs/<id>/` (`out.root`, `plots.pdf`, `config.json`)
and `study/<project>/report.html`. The workspace's own `README.md` explains the rest.

A bigger request, once that works:

```text
Learn the examples at solid_gemc repo "solid_gemc/analysis/hgc_study/" and "solid_gemc/geometry/hgc_moved/",
Do the heavy gas Cherenkov simulation on SIDIS He3 moved configuration with 1000 events of 5 GeV pi- at 10 degree theta angle and full phi angle,
then plot number of photoelectron yield in various illustrative ways,
verify the sim result with physics analytic calculation,
finally show me the results in an html file
```

## How you drive it

The `solid-gemc` orchestrator skill auto-loads on SoLID-flavored natural language,
gap-checks a seven-field spec, presents a plan, gates on your approval,
then drives the whole run through `bin/solid-gemc-run` (bootstrap
the workspace, pick + edit a GCard, run `solid_gemc`, convert EVIO → ROOT,
record provenance, plot). Works the same on Claude Code and Codex CLI.

Two upstream worked examples live in your workspace after init, both fully self-contained:

| Example | What it teaches |
|---|---|
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards (`cherenkov.gcard`, `solid_SIDIS_He3_hgc.gcard`, …), batch run scripts (`load.sh` / `run.sh`), ROOT analysis (`analysis.C` and the `compare_*.C` scripts) |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators (`solid_SIDIS_hgc_*.pl`), the resulting factory text files (`*__geometry_Original.txt` etc.) referenced by `<detector name="..." factory="TEXT" ...>`, plus a `readme.md` |

Init also writes `bin/solid-gemc-run` into your workspace: a small launcher that
runs the newest installed plugin wrapper, from the agent or a plain terminal. A plain
terminal uses an image an agent session already downloaded; it never downloads one.

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


## Testing (maintainers)

See [`tests/README.md`](tests/README.md).

## Known limitations (v0.0.12)

- The .sif is hosted at a personal Duke webhome
  (`http://webhome.phy.duke.edu/~zz81/simg/`). No SLA, may move. Mirror
  locally with `wget` if you need durability.
- No upstream-pin for solid_gemc — `bin/solid-gemc-run init` clones HEAD of master.
  The resolved commit SHA is recorded per-run in `runs/<id>/config.json`.
- ROOT analysis runs inside the container via `bin/solid-gemc-run root`.
  Upstream's HGC study assumes host-side ROOT; we recommend the
  in-container path for portability.

## License

[MIT](LICENSE) — © 2026 Zhiwen Zhao.
