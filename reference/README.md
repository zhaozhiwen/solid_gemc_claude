# `reference/` — background knowledge for working with `solid_gemc`

These files are **not** part of the plugin's runtime. They're the
reference library a Claude Code session should consult when helping
a user reason about the SoLID GEMC simulation stack — geant4 → gemc →
solid_gemc — that the plugin drives.

Treat this dir as load-bearing for *understanding*, not for *execution*.
Reading these end-to-end is overkill for routine tasks; grep them when a
specific question comes up (e.g. "what does `PRODUCTIONCUT` actually do",
"is `solid_hgc` a stub", "what's the Birks coefficient for the EC
scintillator", "why is the detector path resolved cwd-relative").

## What's in here

### Source-code digests

| File | Covers |
|---|---|
| [`gemc.md`](gemc.md) | Digest of the **gemc 2.9 framework** source at `mod/gemc/2.9/` (~240k LOC). Top-level architecture, entry point, SConstruct + `LIBRARY=shared` gating, the `goptions` engine with cmdline override syntax, GCard XML schema, the five detector factories, hit-processor map, the four registered output formats (`evio` / `hipo` / `txt` / `txt_simple` — **no ROOT**), sensitive-detector machinery, generator, fields, materials, physics lists, plus quick-lookup tables and a "surprising behaviors" call-out section. |
| [`solid_gemc.md`](solid_gemc.md) | Digest of the **SoLID layer** at `source/2.9/` (~1.9k LOC). What this layer adds beyond gemc, `solid_gemc.cc` entry point, SConstruct linkage to `libgemc.so`, per-processor breakdown of the 7 SoLID hit processors (`solid_ec`, `solid_ec_ps`, `solid_spd`, `solid_lgc`, `solid_gem`, `solid_hgc`, `solid_mrpc`) with full-vs-stub status, key physics constants with file:line citations, and the "how to add an 8th hit processor" recipe. |

When to consult: any time you need to reason about *how* the simulation
works internally — bugs that manifest in geometry loading, output
formats, hit-processor outputs, build failures, or option override
behavior. Cite back to file:line when answering.

### Workflow guide

| File | Covers |
|---|---|
| [`gemc_simulation_general_note.md`](gemc_simulation_general_note.md) | The SoLID-collaboration-maintained "how to use gemc for SoLID" guide. Mirror of <https://solid.jlab.org/wiki/index.php/Gemc_simulation_general_note> (fetched 2026-05-10). Building a simulation end-to-end: parameters, geometry text format with the full entry table, materials, mirrors, hit/bank/process definitions, fields, GCard option reference, output formats, evio2root usage, debug knobs, display shortcuts, and 3D-display-file workflow. |

When to consult: any time a user is **authoring** geometry, materials,
hits, banks, or constructing a GCard from scratch — as opposed to
running a canonical preset. This is the human-facing how-to; the source
digests above are the cross-reference.

### Physics reference (Geant4 cross sections + dE/dx)

| File | Covers |
|---|---|
| [`passage-particles-matter.md`](passage-particles-matter.md) | Full markdown extraction of PDG 2025 "Review of Passage of Particles Through Matter". Useful to understand what Geant4 is modeling when interpreting energy deposits, multiple scattering, range/straggling, Cherenkov/scintillation yields, hadronic interactions, etc. |
| [`passage-particles-matter-summary.md`](passage-particles-matter-summary.md) | Short digest of the above, for quick lookup. |
| [`rpp2025-rev-passage-particles-matter.pdf`](rpp2025-rev-passage-particles-matter.pdf) | Source PDF (PDG 2025 review). |
| [`rpp2025-rev-passage-particles-matter.txt`](rpp2025-rev-passage-particles-matter.txt) | `pdftotext` extraction of the PDF, for grep'ing exact numbers/citations. |

When to consult: when a user asks *why* a hit processor uses a specific
formula or constant (Birks' law, Bethe-Bloch, photon yield, Moliere
multiple-scattering radius, hadronic cross sections), or when sanity-
checking simulation output against analytic expectations.

## Suggested reading order for a fresh agent

1. **`solid_gemc.md`** first — it's the smallest and frames the layer
   the plugin actually exercises.
2. **`gemc.md`** next — the framework underneath. Skim, don't read end
   to end.
3. **`gemc_simulation_general_note.md`** for any task that touches GCard
   authoring or detector text-file editing.
4. The `passage-particles-matter*` files are reference-only — pull on
   demand.

## What's NOT in here

- Plugin-internal docs (CLAUDE.md, PLAN.md, BUILD_LOG.md, command
  bodies, skill bodies) — those live in the repo root and the relevant
  dirs.
- Upstream worked examples — those live in the user's workspace after
  `solid-gemc-init`, at `solid_gemc/analysis/hgc_study/` (config + run +
  analyze pipeline) and `solid_gemc/geometry/hgc_moved/` (custom-
  detector authoring with Perl generators).
- Geant4 user docs and gemc.jlab.org HTML docs — link to upstream
  rather than mirroring; URLs are inside the files above.
