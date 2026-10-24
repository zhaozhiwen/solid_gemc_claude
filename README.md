# solid-gemc-claude

A plugin for running [solid_gemc](https://github.com/JeffersonLab/solid_gemc)
(the SoLID experiment's GEMC-based simulation) from **Claude Code** or
**OpenAI Codex CLI**. solid_gemc, GEMC, Geant4, and ROOT all live in a pinned
[JLabCE 2.5](https://github.com/JeffersonLab/solid_release) apptainer image;
analysis runs on that ROOT inside the container (host-side
[`uproot`](https://github.com/scikit-hep/uproot5) is an option).

> The name keeps its `-claude` suffix for historical/repo-stability reasons;
> the plugin is not Claude-specific. The whole workflow runs through one
> platform-neutral wrapper (`bin/solid-gemc-run`), with thin per-harness
> adapters on top.

**Docs site:** [zhaozhiwen.github.io/solid_gemc_claude](https://zhaozhiwen.github.io/solid_gemc_claude/) (install + quickstart + two demo run reports).

> **Status: v0.0.7.** Dual-platform (Claude Code + Codex CLI). The
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

The repo is one source of truth for both harnesses — shared
`bin/solid-gemc-run` + `skills/solid-gemc/`, with `.claude-plugin/` and
`.codex-plugin/` manifests side by side (plus the per-harness marketplace
descriptors `.claude-plugin/marketplace.json` and
`.agents/plugins/marketplace.json`) and `CLAUDE.md` / `AGENTS.md` (same
content) at the root. Analysis needs no host install: `analyze` runs ROOT in
the container. The optional Python venv installs lazily on the first
`analyze --python` (idempotent; `bin/solid-gemc-run setup-python` pre-installs it).

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

Codex reads `AGENTS.md` — the canonical project-rules file.
`CLAUDE.md` is a symlink to it and Claude Code reads it.
`codex plugin add` drops the symlink but keeps the real `AGENTS.md`.

apptainer can't run inside Codex's sandbox, so Codex must be able to ask before
running `solid-gemc-run` outside it. If it doesn't ask (the run fails with
`operation not permitted`), set `/permissions` to **Ask for approval** in the session.

If Codex reports that its own sandbox failed to start, even read-only commands will
ask for approval. That comes from the host's `bubblewrap`, not the plugin — check with
`bwrap --ro-bind / / true` as a normal user; some mount layouts (e.g. a stacked
`/proc/sys/fs/binfmt_misc` mount) make bubblewrap 0.6 fail there. Runs still work.

## Try this after install

You can ask your agent harness to

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

You can ask your agent harness to init solid-gemc-claude,
which will run `bin/solid-gemc-run init` to pull .sif, clone solid_gemc, run both scons builds, scaffold workspace as a one-shot bootstrap. Or it will run at the first time you use it.

Two upstream worked examples live in your workspace after init, both fully self-contained:

| Example | What it teaches |
|---|---|
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards (`cherenkov.gcard`, `solid_SIDIS_He3_hgc.gcard`, …), batch run scripts (`load.sh` / `run.sh`), ROOT analysis (`analysis.C` and the `compare_*.C` scripts) |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators (`solid_SIDIS_hgc_*.pl`), the resulting factory text files (`*__geometry_Original.txt` etc.) referenced by `<detector name="..." factory="TEXT" ...>`, plus a `readme.md` |

Init also writes `bin/solid-gemc-run` into your workspace: a small launcher that runs the newest installed plugin wrapper, so the commands below work from the workspace root (`../bin/solid-gemc-run` from a project subdir), in the agent or a plain terminal. A plain terminal uses an image an agent session already downloaded; it never downloads one itself.

`bin/solid-gemc-run gcard <preset> <project> --events N` copies a GCard into a project with the batch options set (optical photons on; `--no-optical` to turn off), and `bin/solid-gemc-run run <project>/<gcard> <source-dir>` is one whole run: gemc, `evio2root` with the GCard's detector banks, `config.json` and default plots. `bin/solid-gemc-run analyze runs/<id>` would produce default plots from out.root (the post-converted file) with ROOT in the container: `hist_*.svg`, `plots.pdf` and a stats line per branch. `analyze --python` makes uproot PNGs instead.

`bin/solid-gemc-run shell` drops you into a tcsh prompt with the env
exported (`SoLID_GEMC`, `GEMC`, `PATH`, `LD_LIBRARY_PATH`) so you can
follow upstream's scripts directly. For HGC: `cd solid_gemc/analysis/hgc_study`,
then `./run.sh`. For detector authoring: edit the `.pl` in
`solid_gemc/geometry/hgc_moved/`, regenerate, run gemc against your new
detector.

**The `solid_gemc/` clone is for reading and running.** Init clones
[JeffersonLab/solid_gemc](https://github.com/JeffersonLab/solid_gemc),
which accepts changes only as fork → pull request, so you can't push to
it. To keep or submit changes, fork it on GitHub and point the clone at
your fork, keeping JeffersonLab as `upstream`:

```sh
git -C solid_gemc remote rename origin upstream
git -C solid_gemc remote add origin https://github.com/<you>/solid_gemc.git
```

Then push branches to `origin`, open pull requests against JeffersonLab, and
sync with `git -C solid_gemc pull upstream master`. Init reuses an existing
clone, so it never overwrites your work.

## Testing (maintainers)

Three automated tests, all against a **clean Claude Code and Codex** set up in a
throwaway sandbox, so your own sessions and `~/.claude`, `~/.codex` are never touched:

- `tests/quick-test.sh` — ~1 min, no model calls. Installs the working tree into both
  tools and runs the installed plugin end to end (init → gemc → evio2root → analyze),
  with the image and a prebuilt `templates/solid_gemc` linked in.
- `tests/basic-test.sh setup` / `verify` / `cleanup` — ~10–15 min. Real Claude Code
  and Codex sessions driven by a subagent playing the user, with the quick test's
  shortcuts. Run after changes to the skill.
- `tests/full-test.sh setup` / `verify` / `cleanup` — a real first session in each tool:
  installed from the published marketplace, real image download and build, default
  permissions, and a subagent playing the user. Run before a release.

Design and details: [`tests/README.md`](tests/README.md).

## Known limitations (v0.0.7)

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
