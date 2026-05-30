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

`/plugin update` (Claude) handles upgrades. [Apptainer](https://apptainer.org) ≥ 1.4 must already be on the host; the plugin pulls its pinned `.sif` on first use via `wget`.

## Quickstart

There are no slash commands. The `solid-gemc` orchestrator skill auto-loads on any SoLID-flavored request (Claude Code or Codex CLI), gap-checks a seven-field spec (project name, physics goal, SoLID config, beam, GCard, output, analysis), shows a plan, and runs it on approval — driving everything through `bin/solid-gemc-run` (bootstrap the workspace, pick + edit a GCard, run `solid_gemc`, convert EVIO → ROOT, record provenance, plot).

Ask your harness something like:

```text
Follow the examples at "solid_gemc/analysis/hgc_study/" and
"solid_gemc/geometry/hgc_moved/" to run the heavy-gas Cherenkov study on
SIDIS He-3 at 5 GeV π- with the moved configuration, 1000 events, then plot
photoelectron yield in various illustrative ways and show me the result in
an HTML file.
```

`init` runs once as a one-shot bootstrap (pull the `.sif`, clone `solid_gemc`, run both scons builds, scaffold a workspace) — automatically on first use, or when you ask to "init solid-gemc-claude". After it, two upstream worked examples live in your workspace, both self-contained:

| Example | What it teaches |
|---|---|
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards, batch run scripts, ROOT analysis macros |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators, the factory text files they emit, and the GCard wiring |

`bin/solid-gemc-run analyze runs/<id>` produces uproot plots from the post-converted `out.root`. `bin/solid-gemc-run shell` drops you into a tcsh prompt with the env exported, to follow upstream's scripts directly.

## What it does

- **NL-driven simulation as a first-class step.** The orchestrator turns a plain-English study spec into a validated GCard + run command. Edit the GCard or re-describe to iterate.
- **Single runtime seam.** All `gemc`, `xmllint`, ROOT, and `evio2root` calls go through `bin/solid-gemc-run`. The container tag is pinned in one place. No host-side ROOT required.
- **EVIO + post-convert to ROOT.** `gemc` 2.9 writes EVIO natively; the wrapper post-converts to ROOT inside the same container so analysis can stay Python via uproot. Both files end up in `runs/<id>/`.

## Requirements

- [Apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git` on the host. (No host-side `tcsh` needed — the wrapper invokes `tcsh` *inside* the container.)
- Python 3.9+ with `uproot numpy matplotlib` (only for the `analyze` step).
- ~1.7 GB of disk for the cached JLabCE 2.5 image, plus ~1 GB per workspace for the cloned + built `solid_gemc` tree.
- Claude Code (plugin support) **or** OpenAI Codex CLI (Agent Skills).

## Links

- [License (MIT)](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/LICENSE)
- [solid_gemc upstream](https://github.com/JeffersonLab/solid_gemc)

## Acknowledgments

- **solid_gemc** — the SoLID experiment's GEMC-based simulation. See [github.com/JeffersonLab/solid_gemc](https://github.com/JeffersonLab/solid_gemc).
- **GEMC** — the geometry-and-tracking framework underneath. See [gemc.jlab.org](https://gemc.jlab.org).
- **JLabCE 2.5 container** — built and maintained at Jefferson Lab; see [github.com/JeffersonLab/solid_release](https://github.com/JeffersonLab/solid_release).
