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
Learn the examples at solid_gemc repo "solid_gemc/analysis/hgc_study/" and "solid_gemc/geometry/hgc_moved/",
Do the heavy gas Cherenkov simulation on SIDIS He3 moved configuration with 1000 events of 5 GeV pi- at 10 degree theta angle and full phi angle,
then plot number of photoelectron yield in various illustrative ways,
verify the sim result with physics analytic calculation,
finally show me the results in an html file
```

`init` runs once as a one-shot bootstrap (pull the `.sif`, clone `solid_gemc`, run both scons builds, scaffold a workspace) — automatically on first use, or when you ask to "init solid-gemc-claude". After it, two upstream worked examples live in your workspace, both self-contained:

| Example | What it teaches |
|---|---|
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards, batch run scripts, ROOT analysis macros |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators, the factory text files they emit, and the GCard wiring |

Init writes `bin/solid-gemc-run` into your workspace — a launcher that runs the newest installed plugin wrapper, from the agent or a plain terminal (a terminal uses an already-downloaded image; it never downloads one). `bin/solid-gemc-run analyze runs/<id>` plots the post-converted `out.root` with ROOT in the container (SVG + `plots.pdf` + per-branch stats; `--python` for host uproot PNGs). `bin/solid-gemc-run shell` drops you into a tcsh prompt with the env exported, to follow upstream's scripts directly.

## What it does

- **NL-driven simulation as a first-class step.** The orchestrator turns a plain-English study spec into a validated GCard + run command. Edit the GCard or re-describe to iterate.
- **Single runtime seam.** All `gemc`, `xmllint`, ROOT, and `evio2root` calls go through `bin/solid-gemc-run`. The container tag is pinned in one place. No host-side ROOT required.
- **solid_gemc clone for reading.** Init clones JeffersonLab/solid_gemc, which takes changes only as fork → pull request. To keep or submit edits, fork it and run `git -C solid_gemc remote rename origin upstream && git -C solid_gemc remote add origin https://github.com/<you>/solid_gemc.git`.
- **EVIO + post-convert to ROOT.** `gemc` 2.9 writes EVIO natively; the wrapper post-converts to ROOT inside the same container and analysis runs on the container's ROOT (host uproot optional). Both files end up in `runs/<id>/`.

## Requirements

- [Apptainer](https://apptainer.org) ≥ 1.4 on Linux.
- `wget`, `git` on the host. (No host-side `tcsh` needed — the wrapper invokes `tcsh` *inside* the container.)
- Python 3 on the host; Python 3.9+ with `uproot numpy matplotlib` only for the optional `analyze --python`.
- ~1.7 GB in your home dir for the cached JLabCE 2.5 image, plus ~1 GB per workspace for the cloned + built `solid_gemc` tree. The image lives in the agent tool's persistent plugin data dir (`~/.claude/plugins/data/solid-gemc-claude-solid-gemc-claude/` or `~/.codex/plugins/data/solid-gemc-claude-solid-gemc-claude/`), so it survives plugin updates and is shared across workspaces; uninstalling the plugin may delete it.
- Claude Code (plugin support) **or** OpenAI Codex CLI (Agent Skills).

## Testing

Three automated tests run the plugin in a **clean Claude Code and Codex** inside a
throwaway sandbox: a quick test (~1 min, no model calls, installed plugin run end to
end), a basic test (~15 min, real sessions with an agent playing the user, image and
build linked in) and a full test (a real first session in each tool — published
install, real image download and build, an agent playing the user). See
[`tests/README.md`](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/tests/README.md).

## Links

- [License (MIT)](https://github.com/zhaozhiwen/solid_gemc_claude/blob/main/LICENSE)
- [solid_gemc upstream](https://github.com/JeffersonLab/solid_gemc)

## Acknowledgments

- **solid_gemc** — the SoLID experiment's GEMC-based simulation. See [github.com/JeffersonLab/solid_gemc](https://github.com/JeffersonLab/solid_gemc).
- **GEMC** — the geometry-and-tracking framework underneath. See [gemc.jlab.org](https://gemc.jlab.org).
- **JLabCE 2.5 container** — built and maintained at Jefferson Lab; see [github.com/JeffersonLab/solid_release](https://github.com/JeffersonLab/solid_release).
