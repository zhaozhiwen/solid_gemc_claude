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
> [`docs/DESIGN.md`](docs/DESIGN.md) for design intent and `DUAL_PLATFORM_PLAN.md`
> for the cross-platform architecture.

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
`.codex-plugin/` manifests side by side and `CLAUDE.md` / `AGENTS.md`
(symlinked) at the root.

### Claude Code

```text
/plugin marketplace add zhaozhiwen/solid_gemc_claude
/plugin install solid-gemc-claude@solid-gemc-claude
```

The `SessionStart` hook pre-warms the analysis venv.

### Codex CLI

Install as a Codex plugin (cached under `~/.codex/plugins/cache/`); the bundled
`solid-gemc` skill auto-activates on SoLID-flavored requests, the same as on
Claude Code. There is no `SessionStart` hook on Codex, so the analysis venv is
installed lazily on the first `analyze` (idempotent). Ensure `solid-gemc-run`
is on `PATH` (the skill resolves the wrapper via `CLAUDE_PLUGIN_ROOT` on Claude,
else `command -v solid-gemc-run`); if needed, symlink it:

```sh
ln -s <plugin-cache-dir>/bin/solid-gemc-run ~/.local/bin/solid-gemc-run
```

Codex reads `AGENTS.md` (a symlink to `CLAUDE.md`) for project rules.

### Standalone (no harness)

Everything also works from a bare shell — the wrapper owns the workflow:

```sh
git clone https://github.com/zhaozhiwen/solid_gemc_claude && cd solid_gemc_claude
bin/solid-gemc-run init                 # scaffold + pull + clone + build
bin/solid-gemc-run analyze runs/<id>    # uproot plots (venv self-installs)
```

Cache/venv fall back to `~/.cache` / `~/.local/share` when not under a plugin.

## Slash commands (Claude Code)

| Command | Purpose |
|---|---|
| `/solid-gemc-claude:init` | Pull .sif, clone solid_gemc, run both scons builds, scaffold workspace. One-shot bootstrap. |
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
| `solid_gemc/analysis/hgc_study/` | the **config + run + analyze** pipeline — GCards (`cherenkov.gcard`, `solid_SIDIS_He3_hgc.gcard`, …), batch run scripts (`load.sh` / `run.sh`), ROOT analysis (`analysis.C` and the `compare_*.C` scripts) |
| `solid_gemc/geometry/hgc_moved/` | **custom detector authoring** — Perl generators (`solid_SIDIS_hgc_*.pl`), the resulting factory text files (`*__geometry_Original.txt` etc.) referenced by `<detector name="..." factory="TEXT" ...>`, plus a `readme.md` |

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
- No upstream-pin for solid_gemc — `/solid-gemc-claude:init` clones HEAD of master.
  The resolved commit SHA is recorded per-run in `runs/<id>/config.json`.
- ROOT analysis runs inside the container via `bin/solid-gemc-run root`.
  Upstream's HGC study assumes host-side ROOT; we recommend the
  in-container path for portability.

## License

[MIT](LICENSE) — © 2026 Zhiwen Zhao.
