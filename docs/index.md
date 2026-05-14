---
title: Home
layout: default
nav_order: 1
---

# solid-gemc-claude

A Claude Code plugin for running [solid_gemc](https://github.com/JeffersonLab/solid_gemc)
— the SoLID experiment's GEMC-based simulation — through a small set of
slash commands. solid_gemc, GEMC, Geant4, and ROOT all live in a pinned
[JLabCE 2.5](https://github.com/JeffersonLab/solid_release) apptainer
image; analysis runs on the host with
[`uproot`](https://github.com/scikit-hep/uproot5).

> **Status: v0.0.3.** Two slash commands shipped (`init`, `analyze`); an
> orchestrator skill drives the simulation loop in between.

[View on GitHub](https://github.com/zhaozhiwen/solid_gemc_claude){: .btn .btn-primary }
[Report an issue](https://github.com/zhaozhiwen/solid_gemc_claude/issues){: .btn }

---

## Requirements

- [apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git` on the host. (No host-side `tcsh` needed — the wrapper
  invokes `tcsh` *inside* the container.)
- Python 3.9+ with `uproot numpy matplotlib` (only for the analyze step).
- ~1.7 GB of disk for the cached JLabCE 2.5 image, plus ~1 GB for the
  cloned + built `solid_gemc` tree per workspace.
- Claude Code with plugin support.

The plugin downloads the JLabCE 2.5 `.sif` on first use; URL is pinned
in [`bin/solid-gemc-run`](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/bin/solid-gemc-run).

## Install

```text
/plugin marketplace add zhaozhiwen/solid_gemc_claude
/plugin install solid-gemc-claude@solid-gemc-claude
```

## Slash commands

| Command | Purpose |
|---|---|
| `/solid-gemc-claude:init` | Pull `.sif`, clone `solid_gemc`, run both scons builds, scaffold workspace. One-shot bootstrap. |
| `/solid-gemc-claude:analyze runs/<id>` | uproot-based default plots from `out.root` (the post-converted file). |

The workflow **between** init and analyze (pick a GCard, run
`solid_gemc`, convert EVIO → ROOT, record provenance) is driven by the
`solid-gemc` orchestrator skill — auto-loads on SoLID-flavored natural
language ("run a PVDIS LD2 study at 11 GeV") and gap-checks against a
six-field spec before executing. Users who want upstream's pattern
directly can `bin/solid-gemc-run shell` and follow
`solid_gemc/analysis/hgc_study/run.sh`.

## First-run flow (after `/solid-gemc-claude:init`)

There is no shipped "example" command. Two upstream worked examples
live in your workspace after init, both fully self-contained:

| Example | What it teaches |
|---|---|
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards, batch run scripts (`load.sh` / `run.sh`), ROOT analysis (`analysis.C`, `compare_*.C`) |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators (`solid_SIDIS_hgc_*.pl`), resulting factory text files referenced by `<detector name="..." factory="TEXT" ...>`, plus a `readme.md` |

`bin/solid-gemc-run shell` drops you into a tcsh prompt with the env
exported (`SoLID_GEMC`, `GEMC`, `PATH`, `LD_LIBRARY_PATH`) so you can
follow upstream's scripts directly. For HGC: `cd solid_gemc/analysis/hgc_study`,
then `./run.sh`.

## Known limitations (v0.0.3)

- The `.sif` is hosted at a personal Duke webhome
  (`http://webhome.phy.duke.edu/~zz81/simg/`). No SLA, may move. Mirror
  locally with `wget` if you need durability.
- No upstream-pin for `solid_gemc` — `/solid-gemc-claude:init` clones HEAD
  of master. The resolved commit SHA is recorded per-run in
  `runs/<id>/config.json`.
- ROOT analysis runs inside the container via `bin/solid-gemc-run root`.
  Upstream's HGC study assumes host-side ROOT; we recommend the
  in-container path for portability.

## License

[MIT](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/LICENSE) — © 2026 Zhiwen Zhao.
