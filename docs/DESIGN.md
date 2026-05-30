---
title: Design
layout: default
nav_order: 2
---

This page covers the *why* behind solid-gemc-claude. For *how to use it*,
see [Home]({{ site.baseurl }}/).

## The problem

[solid_gemc](https://github.com/JeffersonLab/solid_gemc) is the SoLID
experiment's GEMC-based simulation. Running it end-to-end requires
Geant4, GEMC, ROOT, and a working tcsh build chain — each with its own
version pin. The standard install path is a multi-hour scons-and-
environment setup that varies per host.

The plugin wraps that complexity behind a natural-language skill and one
runtime wrapper, so a user can go from `git clone` to `out.root`
without ever touching the underlying toolchain. It runs on both Claude
Code and Codex CLI.

## Architecture

```
                            host                          container
                            ────                          ─────────
  skills/solid-gemc/        ─┐                            JLabCE 2.5 .sif
  (orchestrator, NL)         │      bin/                  ┌─────────────┐
                             ┼  solid-gemc-run ─► apptainer│ gemc, ROOT, │
  bin/solid-gemc-run         │   init/analyze/    exec ───►│ evio2root,  │
  init / analyze / …        ─┤   exec/…                    │ solid_gemc  │
                             │                            └──────┬──────┘
  Python (uproot, numpy)     │                                   │
  for analysis  ◄────────────┴── runs/<id>/out.root ──────────── ┘
```

Two components live on the host (no slash commands):

- **One orchestrator skill** — `skills/solid-gemc/`. Drives the whole
  workflow from natural language; auto-loads on SoLID-flavored requests.
- **One runtime wrapper** — `bin/solid-gemc-run`. The single command
  surface and the single container seam: `init` / `analyze` /
  `setup-python` / pull / clone / build / shell / exec / root /
  validate-gcard.

Everything else lives inside the JLabCE 2.5 apptainer image: gemc 2.9,
Geant4, ROOT, evio2root, plus the freshly cloned and built `solid_gemc`
tree.

## Why a skill, not slash commands?

The workflow has too many parameters — physics goal, SoLID config, beam
energy/particle/count, GCard variant, output path, analysis type, project
name — to fit a flag-heavy command, and slash commands are Claude-only
anyway (Codex has no equivalent). So the plugin ships **no slash
commands**: the orchestrator skill is the entry point and `bin/solid-gemc-run`
does the work, identically on both platforms.

The orchestrator skill at `skills/solid-gemc/SKILL.md` works from a
**seven-field spec**: it gap-checks the user's natural-language request
against the required fields, asks for what's missing (via `AskUserQuestion`
on Claude, a plain numbered question on Codex), presents a plan, gates on
user approval, then drives `bin/solid-gemc-run` with stop-on-failure
post-condition checks.

| Field | Example |
|---|---|
| Physics goal | "PVDIS A_PV asymmetry vs Q²" |
| SoLID config | "PVDIS, LD2 target, full magnet config" |
| Beam | "11 GeV e⁻ on LD2, 10000 events" |
| GCard | `solid_PVDIS_LD2_moved_full.gcard` + parameter overrides |
| Output | `runs/<id>/out.root` |
| Analysis | "asymmetry binned in Q²" |

## Design principles

These rules every command and skill follows. They aren't suggestions —
breaking them creates the failure modes they were written to prevent.

**Single runtime seam.** All `gemc`, `xmllint`, `root` invocations go
through `bin/solid-gemc-run`. Commands and skills never call
`apptainer exec` directly. Upgrading the container image is a one-file
change.

**Pinned image, one source of truth.** The container tag lives only in
`bin/solid-gemc-run`. Anywhere else that displays the tag (info
subcommand, README) reads from that script. Eliminates docs/runtime
drift.

**No host-side ROOT requirement.** Default analysis is Python
(uproot + numpy + matplotlib). Anything that needs ROOT runs inside the
container via `bin/solid-gemc-run root`. Users don't have to install
ROOT to use the plugin.

**Fresh-clone reproducibility.** Every command works after `git clone`
on a machine with apptainer + Python. No reliance on cached state in
the maintainer's `$HOME` or absolute `/home/$USER` paths.

**No leakage.** No internal hostnames, absolute home paths, API tokens,
or personal email in committed files. The one allowed exception is
`gemc.jlab.org` as a documentation reference URL.

**Idempotent operations.** Running anything twice doesn't corrupt
state. `bin/solid-gemc-run init` re-detects existing files and refuses
to overwrite without `--force`.

**Cache resolution, no `$HOME` fallback.** Cache location resolves
`$SOLID_GEMC_CLAUDE_CACHE` → `$CLAUDE_PLUGIN_DATA/cache` → fatal error.
Silent `$HOME` fallback would hide state divergence between dev
machines.

## Resolved decisions

**Why JLabCE 2.5?** GEMC + Geant4 + the deps to build `solid_gemc` are
all in there. The sister-plugin's image (`ghcr.io/gemc/g4install`) has
only Geant4 — gemc itself isn't prebuilt. JLabCE 2.5 is the standard
SoLID build environment.

**Why EVIO + post-convert, not direct ROOT output?** gemc 2.9 in
JLabCE 2.5 supports only EVIO and TXT output (`-help-output` confirms).
We post-convert EVIO → ROOT inside the container with `evio2root`, so
both `out.evio` and `out.root` end up in `runs/<id>/`. Analysis stays
Python via uproot. HIPO output deferred past v0.0.3.

**Why `wget` to pull the `.sif`, not `apptainer pull docker://`?** The
`.sif` is hosted at a webhome URL, not a container registry. Direct
`wget` is simpler than scripting around `apptainer pull`'s registry
expectations.

**Why two `scons` builds in `init`?** `solid_gemc` builds in two
passes: `mod/gemc/2.9` produces `libgemc.so` (requires
`LIBRARY=shared`), then `source/2.9` links against it. Skipping or
reordering produces an unlinked binary that segfaults on first run.

## Known limitations (v0.0.3)

- The `.sif` is at a personal Duke webhome
  (`webhome.phy.duke.edu`). No SLA. Mirror locally if you need
  durability.
- `solid_gemc` has no upstream pin — `init` clones HEAD of master. The
  resolved commit SHA is recorded per-run in `runs/<id>/config.json`,
  so a run is reproducible after the fact, just not before.
- ROOT analysis runs only inside the container. Upstream's HGC study
  assumes host-side ROOT; we recommend the in-container path for
  portability.

## See also

- [Home]({{ site.baseurl }}/) — install and usage.
- [GitHub repo](https://github.com/zhaozhiwen/solid_gemc_claude).
- [solid_gemc upstream](https://github.com/JeffersonLab/solid_gemc).
