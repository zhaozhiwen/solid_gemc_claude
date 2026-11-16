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

[Apptainer](https://apptainer.org) ≥ 1.4 must already be on the host; the plugin pulls its pinned `.sif` on first use via `wget`.

**Next:** set up a workspace and run your first study — see [First run](https://github.com/zhaozhiwen/solid_gemc_claude#first-run). Everyday use, your own detector and updating are in the [README](https://github.com/zhaozhiwen/solid_gemc_claude#using-your-workspace).
