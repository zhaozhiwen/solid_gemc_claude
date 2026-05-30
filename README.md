# solid-gemc-claude

A plugin for running [solid_gemc](https://github.com/JeffersonLab/solid_gemc)
(the SoLID experiment's GEMC-based simulation) from **Claude Code** or
**OpenAI Codex CLI**. solid_gemc, GEMC, Geant4, and ROOT all live in a pinned
[JLabCE 2.5](https://github.com/JeffersonLab/solid_release) apptainer image;
analysis runs on the host with [`uproot`](https://github.com/scikit-hep/uproot5).

> The name keeps its `-claude` suffix for historical/repo-stability reasons;
> the plugin is not Claude-specific. The whole workflow runs through one
> platform-neutral wrapper (`bin/solid-gemc-run`), with thin per-harness
> adapters on top.

**Docs site:** [zhaozhiwen.github.io/solid_gemc_claude](https://zhaozhiwen.github.io/solid_gemc_claude/) (install + quickstart + two demo run reports).

> **Status: v0.0.4.** Dual-platform (Claude Code + Codex CLI). The
> orchestrator skill drives the full simulation loop through the wrapper. See
> [`docs/DESIGN.md`](docs/DESIGN.md) for design intent and the cross-platform
> architecture.

## Requirements

- [apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git` on the host. (No host-side `tcsh` needed — the
  wrapper invokes `tcsh` *inside* the container.)
- Python 3.9+ with `uproot numpy matplotlib` (only for the analyze step).
- ~1.7 GB of disk for the cached JLabCE 2.5 image, plus ~1 GB for
  the cloned + built solid_gemc tree per workspace.
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
content) at the root. The analysis venv installs lazily on the first `analyze`
on every platform (idempotent; run `bin/solid-gemc-run setup-python` to
pre-install).

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

## Try this after install

You can ask your agent harness to

```text
Follow the examples at solid_gemc repo "solid_gemc/analysis/hgc_study/" and "solid_gemc/geometry/hgc_moved/" to run the heavy gas Cherenkov study on SIDIS He3 at 5 GeV pi- with the moved configuration, 1000 events, then plot number of photoelectron yield in various illustrative ways and show me the result in the html file
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

`bin/solid-gemc-run analyze runs/<id>` would produce uproot-based default plots from out.root (the post-converted file).

`bin/solid-gemc-run shell` drops you into a tcsh prompt with the env
exported (`SoLID_GEMC`, `GEMC`, `PATH`, `LD_LIBRARY_PATH`) so you can
follow upstream's scripts directly. For HGC: `cd solid_gemc/analysis/hgc_study`,
then `./run.sh`. For detector authoring: edit the `.pl` in
`solid_gemc/geometry/hgc_moved/`, regenerate, run gemc against your new
detector.

## Known limitations (v0.0.4)

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
