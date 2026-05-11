# Ship `solid_gemc_claude` as a separate plugin

## Context

GEMC (`github.com/gemc/gemc`) is a Geant4 wrapper widely used in JLab
nuclear-physics work. It declares geometry through text/SQLite-backed
factories and runs via a single `gemc <gcard>` invocation, not a
user-built `main.cc`. The user wants Claude Code ergonomics for GEMC
work — orchestrator skill, slash commands, the works.

Original instinct was to add GEMC support to `geant4_claude` as a
second backend. After reconsidering: the user-facing surfaces
(geometry, output, build, workflow, knowledge base) are fundamentally
different enough that mixing them dilutes both plugins' identities and
forces nontrivial DESIGN.md churn. A clean second plugin is simpler in
both build-out and ongoing maintenance.

The trade: two install commands instead of one, two per-plugin
`${CLAUDE_PLUGIN_DATA}` dirs caching their own `.sif` (mitigatable
with shared cache env var). In exchange: each plugin keeps a coherent
identity, independent versioning, smaller scannable surface, and the
orchestrator-skill description matching stays sharp.

## Recommendation (high level)

Create `solid_gemc_claude` as a sibling repo on GitHub
(`zhaozhiwen/solid_gemc_claude`), structurally mirroring `geant4_claude`.
Share **patterns**, not code: port the wrapper, workspace conventions,
orchestrator-skill shape, three-layer testing, and packaging
infrastructure. Each plugin then owns its own files.

The two plugins live in parallel — install one, the other, or both.
When both are installed and the user says "simulate X", the right
orchestrator skill triggers based on the natural-language signal
(e.g. mentions of CLAS12 / GCard / factory → `skills/gemc`;
GDML / `main.cc` / `Hits` TTree → `skills/geant4`). Skills auto-load
on description match, so there's no router needed.

## Repo layout (mirroring `geant4_claude`)

```
solid_gemc_claude/
├── .claude-plugin/{plugin.json, marketplace.json}    # name: solid-gemc-claude
├── .mcp.json                                          # deepwiki against gemc/gemc
├── bin/solid-gemc-run                                       # runtime wrapper, ported
├── commands/
│   ├── solid-gemc-init.md           # scaffold workspace + pull image
│   ├── solid-gemc-detector.md       # NL → factory text file
│   ├── solid-gemc-gcard.md          # NL → GCard XML
│   ├── solid-gemc-run.md            # run `gemc <gcard>` with provenance
│   ├── solid-gemc-analyze.md        # ROOT path via uproot (HIPO later)
│   └── solid-gemc-example.md        # self-contained smoke test
├── skills/
│   ├── gemc/SKILL.md          # full-flow orchestrator
│   ├── solid-gemc-detectors/SKILL.md
│   ├── solid-gemc-gcards/SKILL.md
│   └── gemc-analysis/SKILL.md
├── templates/
│   ├── workspace/             # CLAUDE.md, .gitignore, log.md, result.md, dir skeleton
│   └── example/               # minimal GCard + one factory + analysis
├── docs/DESIGN.md
├── tests/{clean-smoke.sh, clean-install-test.sh, CLEAN-INSTALL-CHECKLIST.md}
├── BUILD_LOG.md               # gitignored — private
├── CHANGELOG.md
├── CLAUDE.md                  # maintainer rules
├── LICENSE                    # MIT
├── README.md
└── requirements.txt + hooks/  # SessionStart Python deps
```

Workspace skeleton (what `solid-gemc-init` writes into `cwd`):

```
my-gemc-project/
├── CLAUDE.md            # workspace rules
├── .gitignore           # excludes runs/, *.root, *.hipo, __pycache__/
├── log.md               # chronological work log (Claude maintains)
├── result.md            # per-run findings (Claude maintains)
├── detectors/           # GEMC factory text files (one per detector)
├── gcards/              # GCard XML files
├── runs/                # one subdir per solid-gemc-run (gitignored)
└── analysis/            # uproot / pyROOT scripts
```

No `src/`, no `geometries/`, no `macros/`, no `build/` — GEMC is
pre-built in the container; geometry lives in `detectors/`; run
configuration lives in `gcards/`.

## Architectural decisions

### 1. Container image

Pin one GEMC image tag in `bin/solid-gemc-run` (single source of truth, same
discipline as `geant4_claude`). The current `geant4_claude` image
(`ghcr.io/gemc/g4install:11.4.0-almalinux-9.4`) does *not* include the
`gemc` binary; need a sibling image. Likely candidate:
`ghcr.io/gemc/gemc:<tag>` — verify exact tag in phase 0 by checking
`ghcr.io/gemc/*` listings.

### 2. Cache sharing (optional)

Each plugin has its own `${CLAUDE_PLUGIN_DATA}` dir, so by default
each caches its own `.sif`. Users who want to dedupe can set both
`GEANT4_CLAUDE_CACHE` and `SOLID_GEMC_CLAUDE_CACHE` to the same directory.
Document the option in both READMEs; don't enforce coupling.

### 3. Wrapper (`bin/solid-gemc-run`)

Port `bin/g4run` with these changes:
- Drop `cmd_build` — GEMC is pre-built in the container; nothing to compile.
- Add `cmd_validate_gcard` (xmllint inside container) as the analogue of
  `validate-gdml`.
- Keep `pull`, `info`, `shell`, `exec`, `root` subcommands as-is in shape.
- Pin a different image tag.
- Cache resolution rules unchanged: `$SOLID_GEMC_CLAUDE_CACHE` →
  `$CLAUDE_PLUGIN_DATA/cache` → fatal error (no `$HOME` fallback).

### 4. Orchestrator skill (`skills/solid-gemc/SKILL.md`)

Same structural pattern as `skills/geant4/SKILL.md`: auto-load on
natural-language triggers; gap-check the user's spec across six
required fields; present plan; `AskUserQuestion` gate; execute
end-to-end with stop-on-failure post-condition checks.

GEMC's six-field spec:

| Field | Example |
|---|---|
| Physics goal | "DVCS reconstruction efficiency in the CLAS12 forward tagger" |
| Detector | "CLAS12 forward tagger only (`ft_default` variation)" |
| Beam | "10.6 GeV e- on hydrogen target, 5000 events" |
| GCard options | "FTFP_BERT physics, magnetic field on, ROOT output" |
| Output | "`runs/<id>/out.root`" |
| Analysis | "missing-mass spectrum + scatter plot vs Q²" |

Trigger words for the skill description so it auto-loads on GEMC
intent without colliding with `skills/geant4`: "GEMC", "GCard",
"factory", "CLAS12", "SoLID", JLab experiment names, "GEMC simulation".

### 5. Naming convention

Plugin name: `solid-gemc-claude` (kebab-case — Claude Code spec requires it;
the existing `geant4_claude` plugin learned this the hard way and the
new plugin inherits the rule from day one).

Slash commands: `/solid-gemc-claude:gemc-<verb>` (matches the
`geant4_claude` pattern; namespaced form is the only reliable invocation
on a clean install).

GitHub repo name: `solid_gemc_claude` (underscore, matches `geant4_claude`
for visual symmetry; the underscore is fine outside Claude Code's
identifier scope).

### 6. Knowledge base

Don't ship a `wiki/` directory at v0.0.1. Lean on:
- `deepwiki` MCP server in `.mcp.json` pointed at `gemc/gemc`
  (free, no-auth, already-proven pattern from `geant4_claude`).
- A reference link to `https://gemc.jlab.org` in the skills'
  description and in `solid-gemc-detector` / `solid-gemc-gcard` command bodies.

Add `wiki/sources/gemc-code/` later as users hit gaps. Karpathy
pattern: only write pages from real usage, never pre-populate for
completeness.

### 7. Plugin add-ons

Same auto-install discipline as `geant4_claude`:
- `requirements.txt` — Python deps for analysis. Start with the same
  baseline (`pdg`, plus `uproot` / `numpy` / `matplotlib`).
- `hooks/install-deps.sh` + `hooks/hooks.json` — SessionStart hook,
  uv-first with `python3 -m venv` fallback, idempotent diff/install.
  Port verbatim; only `requirements.txt` content differs.

## Phased rollout

| Phase | Deliverable | Effort |
|---|---|---|
| **0 — Repo bootstrap** | Create `~/claude/solid_gemc_claude/` + GitHub repo `zhaozhiwen/solid_gemc_claude` (private until v0.0.1). Port `bin/g4run` → `bin/solid-gemc-run` (drop CMake step). Manifest + marketplace.json + minimal CLAUDE.md / DESIGN.md / README.md / LICENSE. Identify and pin the GEMC image tag. | ~1 day |
| **1 — Plumbing** | Workspace template (`CLAUDE.md`, `.gitignore`, `log.md`, `result.md`, dir skeleton). `solid-gemc-init` command. Image pulls cleanly into `${CLAUDE_PLUGIN_DATA}/cache/sif/`. `solid-gemc-run --gcard <existing.gcard>` succeeds against a manually-written test GCard. | ~1 day |
| **2 — Example** | `solid-gemc-example` drops a minimal GCard + one factory text file + an analysis script. End-to-end: `init → example → run → analyze` works. | ~1 day |
| **3 — NL surface** | `solid-gemc-detector` (NL → factory text), `solid-gemc-gcard` (NL → GCard XML). Both validate the output before declaring success. | ~2 days |
| **4 — Orchestrator** | `skills/solid-gemc/SKILL.md` with the six-field spec contract. Reference skills `solid-gemc-detectors`, `solid-gemc-gcards`, `gemc-analysis`. | ~2 days |
| **5 — Tests + publish** | Three-layer testing ported (`clean-smoke.sh`, `clean-install-test.sh`, `CLEAN-INSTALL-CHECKLIST.md`). Pre-publish leakage scan. README + DESIGN.md polish. v0.0.1 tag + push + marketplace self-add. | ~1 day |

Total: ~1 week of focused work. Phase 0 has the keystone unknown
(exact GEMC image tag); the rest is mostly disciplined porting.

The trajectory is almost identical to how `geant4_claude` was built
(the `BUILD_LOG.md` of that repo is the template), just substituting
GEMC abstractions at each layer.

## Critical files (to create in `~/claude/solid_gemc_claude/`)

- `.claude-plugin/plugin.json` — `name: "solid-gemc-claude"`, version
  `0.0.1`, kebab-case throughout.
- `.claude-plugin/marketplace.json` — self-marketplace,
  `name: "solid-gemc-claude"`, source `"./"`.
- `bin/solid-gemc-run` — ported from `~/claude/geant4_claude/bin/g4run`
  (commit `33d460d`); subcommands `pull`, `info`, `shell`, `exec`,
  `root`, `validate-gcard`. No `build`.
- `commands/solid-gemc-{init,detector,gcard,run,analyze,example}.md` — each
  with the standard frontmatter (`description`, `allowed-tools`) and
  body sections (Purpose / Inputs / Steps / Outputs / Failure modes),
  same shape as `~/claude/geant4_claude/commands/geant4-*.md`.
- `skills/solid-gemc/SKILL.md` — orchestrator. Structurally identical to
  `~/claude/geant4_claude/skills/geant4/SKILL.md`; only the
  spec fields, defaults, and trigger language differ. The "skills
  are reference, not workflows" carve-out from the `geant4_claude`
  maintainer `CLAUDE.md` carries over and gets re-documented here.
- `templates/workspace/{CLAUDE.md, .gitignore, log.md, result.md}` —
  adapt from `~/claude/geant4_claude/templates/workspace/`. Same
  non-negotiables, only the layout table changes (`detectors/` +
  `gcards/` instead of `src/` + `geometries/` + `macros/` + `build/`).
- `templates/example/` — minimal GCard + one factory + one analysis
  script. Keep it deliberately tiny (the geant4_claude example main
  is 262 LOC; this should be ~20 LOC of GCard XML + ~30 LOC of factory
  text + ~30 LOC of analysis).
- `CLAUDE.md` (maintainer rules) — port from
  `~/claude/geant4_claude/CLAUDE.md`. Same non-negotiables minus
  cmake-related items; add a section on what's shared in pattern but
  separated in code between the two plugins.
- `docs/DESIGN.md` — architecture doc adapted for GEMC. Cover the
  single-runtime-seam discipline, the orchestrator skill design, the
  MVP boundary (HIPO output deferred, specific-experiment scaffolding
  deferred, etc.).
- `README.md` — mirror the three-quickstart-paths structure that
  `~/claude/geant4_claude/README.md` settled on (orchestrator
  recommended; example end-to-end; manual flow).
- `tests/clean-smoke.sh`, `tests/clean-install-test.sh`,
  `tests/CLEAN-INSTALL-CHECKLIST.md` — port and adapt.
- `LICENSE` — MIT, © 2026 Zhiwen Zhao.
- `CHANGELOG.md` — start with `[0.0.1]` Initial release.
- `.gitignore` — mirror; ensure `BUILD_LOG.md` is excluded.
- `.mcp.json` — single MCP server entry for `deepwiki` pointed at
  `gemc/gemc`.
- `requirements.txt` + `hooks/{install-deps.sh, hooks.json}` — port
  verbatim from `geant4_claude`; only `requirements.txt` content may
  differ (likely include `uproot`, `numpy`, `matplotlib`, `pdg`).

## What stays shared between the two plugins

- **Container infrastructure** (apptainer on the host, optional shared
  cache via aligned env vars).
- **Patterns** (single-runtime-seam, three-layer testing,
  orchestrator-skill shape, six-field spec gap-check, log.md /
  result.md handoff documents, run-id format
  `YYYYMMDD-HHMMSS-<6char>`, generic-provenance `config.json`).

These propagate by porting and adapting, not by linking. Each plugin
owns its own copy. When a pattern improves in one plugin, the other
gets it via a deliberate sync.

## Verification

After phase 0:
- `/plugin marketplace add zhaozhiwen/solid_gemc_claude` succeeds.
- `/plugin install solid-gemc-claude@solid-gemc-claude` succeeds.
- `bin/solid-gemc-run info` reports the pinned image.
- `~/.claude/plugins/cache/solid-gemc-claude/solid-gemc-claude/0.0.1/.claude-plugin/plugin.json`
  exists.

After phase 1:
- `mkdir /tmp/gc_smoke && cd $_ && claude`
- `/solid-gemc-claude:solid-gemc-init` writes the GEMC workspace skeleton; `.sif`
  cached.
- `/solid-gemc-claude:solid-gemc-run --gcard <known-good.gcard>` produces
  `runs/<id>/{out.root, log.txt, config.json}` with the same provenance
  shape as `geant4_claude`.

After phase 2:
- `/solid-gemc-claude:solid-gemc-example` materializes a minimal GCard + factory +
  analysis.
- `/solid-gemc-claude:solid-gemc-run --gcard gcards/example.gcard` writes
  `runs/<id>/out.root` with non-empty hits.
- `/solid-gemc-claude:solid-gemc-analyze runs/<id>` produces a plot in the run dir.

After phase 3:
- `/solid-gemc-claude:solid-gemc-detector "1 m × 5 cm scintillator paddle, tag as
  sensitive"` writes `detectors/<slug>.txt` that gemc parses without
  errors.
- `/solid-gemc-claude:solid-gemc-gcard "1 GeV e- on hydrogen, ROOT output, 1000
  events"` writes `gcards/<slug>.gcard` that xmllint accepts and gemc
  parses.

After phase 4:
- Cross-plugin trigger check: in a fresh `cd /tmp/gc_orch && claude`,
  saying "simulate DVCS in CLAS12 with a 10.6 GeV e- beam, ROOT output,
  missing-mass spectrum" auto-loads `skills/gemc` (not
  `skills/geant4`). Verifiable by asking Claude which skill it just
  activated.
- Orchestrator completes the full plan-and-approve cycle and produces
  a finished run.

After phase 5:
- `tests/clean-smoke.sh` passes on the maintainer host with the GEMC
  image reused via `G4C_REUSE_SIF=` analogue.
- `tests/clean-install-test.sh` drives marketplace-install → init →
  example → run → analyze unattended.
- Pre-publish gate: `grep -RIn "/home/$USER\|jlab\.org\|jefflab" .`
  clean (the `gemc.jlab.org` reference URL is the one allowed
  exception, documented in CLAUDE.md).
- v0.0.1 tag pushed, marketplace install works from a fresh clone.

## Open questions to resolve before phase 0

- **Exact GEMC image to pin.** Check `ghcr.io/gemc/*` listings. The
  `gemc/gemc` GitHub repo's container/release artifacts are the
  authoritative source. The current `geant4_claude` image
  (`g4install`) is *not* it.
- **Output format priority.** Phase 2 needs exactly one format end-to-end.
  Recommend ROOT first (uproot path mirrors `geant4_claude`'s analysis).
  HIPO is more nuclear-physics-native but needs `hipo` tooling on host
  or container-side analysis — defer to phase 6.
- **GCard schema for validation.** Phase 1's `validate-gcard` is xmllint
  well-formedness; semantic validation is whatever `gemc` itself does
  at parse time. A formal XSD would be nicer but not blocking.
- **Existing user collision.** No GEMC plugin exists in the marketplace
  yet, so `solid-gemc-claude` is unclaimed. Confirm before publishing.
- **CLAS12 / SoLID / experiment-specific scaffolding.** Defer past
  v0.0.1. The orchestrator can recognize experiment names and pull
  example GCards from a curated set, but that's phase 6+, not MVP.

## What this plan does not address

- Backporting a GEMC backend into `geant4_claude` — explicitly rejected
  in favor of clean separation. If the two plugins should ever merge,
  do it after both have at least one real user, not before.
- Cross-plugin orchestrator routing. Both `skills/geant4` and
  `skills/gemc` use auto-load-on-description-match; collisions
  resolved by description specificity. No central router needed.
- HIPO output, EVIO output, container-side ROOT macros — all phase 6+.
