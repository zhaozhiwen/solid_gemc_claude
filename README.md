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

**Docs site:** [zhaozhiwen.github.io/solid_gemc_claude](https://zhaozhiwen.github.io/solid_gemc_claude/) (install + quickstart + two demo run reports).

> **Status: v0.0.10.** Dual-platform (Claude Code + Codex CLI). The
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

Setup is `bin/solid-gemc-run init` (step 1 of "First run"): download the image,
clone solid_gemc, build it, and write the workspace files. A study request in a
folder that isn't set up asks you before running it.

Two upstream worked examples live in your workspace after init, both fully self-contained:

| Example | What it teaches |
|---|---|
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards (`cherenkov.gcard`, `solid_SIDIS_He3_hgc.gcard`, …), batch run scripts (`load.sh` / `run.sh`), ROOT analysis (`analysis.C` and the `compare_*.C` scripts) |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators (`solid_SIDIS_hgc_*.pl`), the resulting factory text files (`*__geometry_Original.txt` etc.) referenced by `<detector name="..." factory="TEXT" ...>`, plus a `readme.md` |

Init also writes `bin/solid-gemc-run` into your workspace: a small launcher that runs the newest installed plugin wrapper, so the commands below work from the workspace root (`../bin/solid-gemc-run` from a project subdir), in the agent or a plain terminal. A plain terminal uses an image an agent session already downloaded; it never downloads one itself.

- `bin/solid-gemc-run gcard <preset> study/<project> --events N` copies a GCard into a
  project with the batch options set (optical photons on; `--no-optical` turns
  them off).
- `bin/solid-gemc-run run study/<project>/<gcard> <source-dir>` is one whole run: gemc,
  `evio2root` with the GCard's detector banks, `config.json` and default plots.
- `bin/solid-gemc-run analyze study/<project>/runs/<id>` re-plots a run with ROOT in the
  container: `hist_*.svg`, `plots.pdf` and a stats line per branch
  (`--python` makes uproot PNGs instead).

`bin/solid-gemc-run shell` drops you into a tcsh prompt with the env
exported (`SoLID_GEMC`, `GEMC`, `PATH`, `LD_LIBRARY_PATH`) so you can
follow upstream's scripts directly. For HGC: `cd solid_gemc/analysis/hgc_study`,
then `./run.sh`. For detector authoring: edit the `.pl` in
`solid_gemc/geometry/hgc_moved/`, regenerate, run gemc against your new
detector.

**The `solid_gemc/` clone is for reading and running.** It comes from
[JeffersonLab/solid_gemc](https://github.com/JeffersonLab/solid_gemc), which
accepts changes only as fork → pull request. To keep or submit changes, point
the clone at your fork; the docs site has the commands
("Changing solid_gemc itself" under [Using your workspace](https://zhaozhiwen.github.io/solid_gemc_claude/#using-your-workspace)).
Init reuses an existing clone, so it never overwrites your work.

## Updating

Update the plugin in Claude Code or Codex and start a new session; existing
workspaces need nothing (their launcher runs the newest installed plugin). Commands:
[Updating](https://zhaozhiwen.github.io/solid_gemc_claude/#updating).

## Testing (maintainers)

See [`tests/README.md`](tests/README.md).

## Known limitations (v0.0.10)

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
