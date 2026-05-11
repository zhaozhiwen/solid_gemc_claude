# solid-gemc-claude

A Claude Code plugin for running [solid_gemc](https://github.com/JeffersonLab/solid_gemc)
(the SoLID experiment's GEMC-based simulation) through a small set of slash
commands. solid_gemc, GEMC, Geant4, and ROOT all live in a pinned
[JLabCE 2.5](https://github.com/JeffersonLab/solid_release) apptainer image;
analysis runs on the host with [`uproot`](https://github.com/scikit-hep/uproot5).

> **Status: v0.0.1, pre-release.** Plugin scaffolding only. Slash commands
> not yet shipped. See `PLAN.md` and `CLAUDE.md` for design intent.

## Requirements

- [apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git`, `tcsh` on the host.
- Python 3.9+ with `uproot numpy matplotlib` (only for the analyze step).
- ~5 GB of disk for the cached JLabCE 2.5 image.
- Claude Code with plugin support.

The plugin downloads
[`jeffersonlab_jlabce_tag2.5_digest:sha256:9b9a9ec8c793...sif`](http://webhome.phy.duke.edu/~zz81/simg/jeffersonlab_jlabce_tag2.5_digest:sha256:9b9a9ec8c793035d5bfe6651150b54ac298f5ad17dca490a8039c530d0302008_20220413_s3.9.5.sif)
on first use; URL is pinned in [`bin/solid-gemc-run`](bin/solid-gemc-run).

## Install (once published)

```text
/plugin marketplace add zhaozhiwen/solid_gemc_claude
/plugin install solid-gemc-claude@solid-gemc-claude
```

## Planned slash commands

| Command | Purpose |
|---|---|
| `/solid-gemc-claude:solid-gemc-init` | Pull .sif, clone solid_gemc, run both scons builds, scaffold workspace. |
| `/solid-gemc-claude:solid-gemc-config <preset>` | Copy a canonical GCard from `$SoLID_GEMC/script/` into `gcards/`. |
| `/solid-gemc-claude:solid-gemc-run --gcard <path>` | Run `solid_gemc <gcard>` inside container (writes `out.evio`), then auto-convert to `out.root` via `evio2root`. Provenance captured. |
| `/solid-gemc-claude:solid-gemc-analyze runs/<id>` | uproot-based default plots from `out.root` (the post-converted file). |

## First-run flow (after `solid-gemc-init`)

There is no shipped "example" command. The recommended first run is the
upstream HGC study, which already lives in your workspace after init:

```text
solid_gemc/analysis/hgc_study/
```

Follow `solid_gemc/analysis/hgc_study/README` upstream; the plugin's
`bin/solid-gemc-run shell` drops you into a tcsh prompt with the right
env exported for the `run.sh` script there.

## Known limitations (v0.0.1)

- The .sif is hosted at a personal Duke webhome
  (`http://webhome.phy.duke.edu/~zz81/simg/`). No SLA, may move. Mirror
  locally with `wget` if you need durability.
- No upstream-pin for solid_gemc — `solid-gemc-init` clones HEAD of master.
  The resolved commit SHA is recorded per-run in `runs/<id>/config.json`.
- ROOT analysis runs inside the container via `bin/solid-gemc-run root`.
  Upstream's HGC study assumes host-side ROOT; we recommend the
  in-container path for portability.

## License

[MIT](LICENSE) — © 2026 Zhiwen Zhao.
