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

`/plugin update` handles upgrades. [Apptainer](https://apptainer.org) ≥ 1.4 must already be on the host; the plugin pulls its pinned `.sif` on first use via `wget`.

## Quickstart

Two slash commands ship: `/solid-gemc-claude:init` (one-shot bootstrap — pull the `.sif`, clone `solid_gemc`, run both scons builds, scaffold a workspace) and `/solid-gemc-claude:analyze runs/<id>` (uproot plots from the post-converted ROOT file).

The simulation loop in between is driven by the `solid-gemc` orchestrator skill — it auto-loads on any SoLID-flavored request. Tell Claude what you want:

```text
> Run the heavy-gas Cherenkov study on SIDIS He-3 at 11 GeV e-,
  default solid_SIDIS_He3_hgc.gcard, 10000 events, then plot
  photon yield per Cherenkov detector.
```

The skill gap-checks against a six-field spec (physics goal, SoLID config, beam, GCard, output, analysis), asks about anything missing, shows a plan, runs it on approval.

After init, two upstream worked examples live in your workspace as templates:

- **`solid_gemc/analysis/hgc_study/`** — the config + run + analyze pipeline (GCards, batch scripts, ROOT analysis macros).
- **`solid_gemc/geometry/hgc_moved/`** — custom detector authoring (Perl generators, factory text files, GCard wiring).

## What it does

- **NL-driven simulation as a first-class step.** The orchestrator turns a plain-English study spec into a validated GCard + run command. Edit the GCard or re-describe to iterate.
- **Single runtime seam.** All `gemc`, `xmllint`, ROOT, and `evio2root` calls go through `bin/solid-gemc-run`. The container tag is pinned in one place. No host-side ROOT required.
- **EVIO + post-convert to ROOT.** `gemc` 2.9 writes EVIO natively; the wrapper post-converts to ROOT inside the same container so analysis can stay Python via uproot. Both files end up in `runs/<id>/`.

## Requirements

- [Apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git` on the host. (No host-side `tcsh` needed — the wrapper invokes `tcsh` *inside* the container.)
- Python 3.9+ with `uproot numpy matplotlib` (only for the `analyze` step).
- ~1.7 GB of disk for the cached JLabCE 2.5 image, plus ~1 GB per workspace for the cloned + built `solid_gemc` tree.
- Claude Code with plugin support.

## Links

- [License (MIT)](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/LICENSE)
- [solid_gemc upstream](https://github.com/JeffersonLab/solid_gemc)

## Acknowledgments

- **solid_gemc** — the SoLID experiment's GEMC-based simulation. See [github.com/JeffersonLab/solid_gemc](https://github.com/JeffersonLab/solid_gemc).
- **GEMC** — the geometry-and-tracking framework underneath. See [gemc.jlab.org](https://gemc.jlab.org).
- **JLabCE 2.5 container** — built and maintained at Jefferson Lab; see [github.com/JeffersonLab/solid_release](https://github.com/JeffersonLab/solid_release).
