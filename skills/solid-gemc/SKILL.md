---
name: solid-gemc
description: Orchestrate the full solid_gemc (SoLID experiment) simulation flow from a single natural-language user request. Load whenever the user asks to "simulate", "run", "do a SoLID / solid_gemc / PVDIS / SIDIS / J/psi / He-3 / heavy-gas Cherenkov" study — including one-shot setups like "PVDIS A_PV asymmetry on LD2 at 11 GeV" or "SIDIS heavy-gas Cherenkov yield on He-3". Captures the physics spec across six fields, asks targeted clarifying questions when something required is missing, presents a brief plan for approval, then drives `solid-gemc-init → solid-gemc-config → solid-gemc-run → solid-gemc-analyze` in sequence with post-condition checks.
---

# solid-gemc — full-flow orchestrator

Use this skill the moment the user asks for a SoLID-flavored
simulation. It is the front door for everything else this plugin
does. The four core slash commands
(`/solid-gemc-claude:solid-gemc-init`, `…config`, `…run`, `…analyze`)
are the *steps*; this skill is the *director* that turns
"simulate PVDIS A_PV on LD2" into a planned sequence of those steps
the user has approved.

The default flow this skill drives:

```
init  →  config  →  (optionally edit gcards/<preset>.gcard)  →  run  →  analyze
```

`init` is one-shot per workspace — if `solid_gemc/` already has a
built binary and the `.sif` is cached, skip step 1.

There is no bring-your-own-binary alternative for solid_gemc. If the
user needs something the canonical configs don't cover, the
divergence point is **the GCard** — they pick a closer canonical and
edit it, or they hand-author one. The binary, the geometry tree, and
the physics list all come from upstream solid_gemc.

## When to load this skill

Trigger on any of:

- "let's do a SoLID simulation", "simulate PVDIS / SIDIS / J/psi /
  DDVCS / He-3 …", "run solid_gemc against …", "set up a solid_gemc
  study of …".
- A physics setup that names a SoLID magnet config (PVDIS, SIDIS,
  CLEO, BaBar), a SoLID target (LD2, LH2, NH3, ³He), or a SoLID
  detector subsystem (LGC/HGC heavy-gas Cherenkov, GEM, EC, MRPC,
  SPD, baffle) without "solid_gemc" named explicitly.
- "where do I start?" inside a workspace scaffolded by this plugin.
- The upstream HGC study: "run the heavy-gas Cherenkov study from
  solid_gemc/analysis/hgc_study". That uses the same flow with
  `config` pointing at one of the hgc_study GCards (or the user can
  follow upstream's `run.sh` via `bin/solid-gemc-run shell` instead —
  call out both paths in the plan).

Do **not** load this skill when:

- The user is mid-flow and only wants one step ("just copy the
  PVDIS_LD2 GCard" → `/solid-gemc-claude:solid-gemc-config` alone;
  "plot runs/<id>" → `…analyze` alone).
- A previous run is failing and the user wants to debug — that's a
  debugging task, not a fresh orchestration. Read
  `runs/<id>/log.txt` + `config.json` and reason from there.
- The user is iterating on an existing `gcards/<preset>.gcard` for a
  previous study; use `solid-gemc-run` directly.

**Co-existence with `geant4_claude/skills/geant4`.** SoLID-specific
vocabulary (`PVDIS`, `SIDIS`, `solid_gemc`, `J/psi`, `He-3`, the
SoLID subsystem names) should keep description-match arbitration
clean. If a user request mentions "Geant4" or "GDML" or "main.cc"
without any SoLID context, prefer the `geant4` skill. If a request
mentions both ("simulate PVDIS using Geant4"), this skill wins —
SoLID is more specific.

## Step 1 — Capture and gap-check the spec

A working solid_gemc simulation needs all six fields below. Read the
user's message and, for each, decide whether they specified it,
whether a default is safe, or whether you must ask.

| Field | What it is | Example |
|---|---|---|
| **Physics goal** | What's being measured / counted | "PVDIS A_PV asymmetry vs Q²", "HGC photoelectron yield vs Cherenkov radius", "J/psi recoil acceptance on LH2" |
| **SoLID config** | Magnet + spectrometer configuration that fixes the geometry | "PVDIS, LD2 target, full magnet config", "SIDIS He-3, heavy-gas Cherenkov in", "J/psi LH2 simple" |
| **Beam** | Particle, energy, event count | "11 GeV e-, 10000 events" |
| **GCard** | Preset name from `solid_gemc/script/` (or `solid_gemc/analysis/*/`), with any parameter overrides | `solid_PVDIS_LD2_moved_full.gcard` (canonical), `N=10000`, `OUTPUT=evio,out.evio` |
| **Output** | ROOT file shape (per-event, per-hit, integrated) — usually defaulted by the GCard. gemc 2.9 writes **EVIO natively** (the build has no ROOT writer); `solid-gemc-run` post-converts to ROOT via `evio2root` so uproot analysis works the same. | `runs/<id>/out.evio` (raw) + `runs/<id>/out.root` (converted) |
| **Analysis** | Plots / numbers to produce | "auto-histogram all numeric branches", "asymmetry binned in Q²", "PE yield vs radius via custom analysis script" |

### What must be asked, never guessed

- **Physics goal** — without it, the run id is meaningless and the
  analysis step is undefined.
- **SoLID config** — there are ~20 canonical GCards in
  `solid_gemc/script/`. PVDIS vs SIDIS vs J/psi are different physics;
  LD2 vs LH2 vs ³He vs NH3 are different targets. Never pick one
  without explicit user choice — list available presets and ask.
- **Beam energy** if not standard for the chosen config (most SoLID
  configs assume 11 GeV; flag and ask if user implies otherwise).

For each missing required field, ask one focused question via
`AskUserQuestion` for multi-option fields, or plain prose for
one-line answers. Tell the user *which* field is missing and *why* a
default is not safe. Don't chain a bunch of guesses together.

### What can default

- **GCard preset name** — once "SoLID config" is locked, the preset
  is derived from it. PVDIS + LD2 + full → `solid_PVDIS_LD2_moved_full`.
- **n_events** — first run defaults to 100 (fast smoke). Tell the
  user this in the plan and suggest a production number for the
  follow-up.
- **OUTPUT format** — `evio,out.evio`. gemc 2.9 in JLabCE 2.5
  supports only `evio` and `txt` natively (no ROOT writer); the
  `solid-gemc-run` step post-converts EVIO → ROOT via `evio2root` so
  `solid-gemc-analyze` reads `out.root` with uproot the same way as
  any TTree-based file. If the user explicitly asks for `txt` output,
  warn that `solid-gemc-analyze` can't auto-plot it.
- **USE_GUI** — always 0 in the orchestrator (batch run). Even if
  the canonical GCard has `USE_GUI=1`, the `config` step flips it.
- **Physics list, hall material, geometry detail level** — never
  touch; the canonical preset has the right values for its physics.

### When the user actually wants the upstream `hgc_study` flow

If the user asks specifically about "heavy-gas Cherenkov study",
"HGC mirror radius study", "compare He-3 vs NH3 HGC", or anything
that points at `solid_gemc/analysis/hgc_study/`: that's an upstream
ready-made workflow with its own `load.sh` / `run.sh` / `analysis.C`.
Recommend it as the *alternative* path in the plan — `bin/solid-gemc-run
shell`, then follow upstream's README. The plugin's own flow still
works (copy the hgc GCards via `config`, run with `solid-gemc-run`,
analyze with `solid-gemc-analyze`), but the upstream flow has more
canned comparison plots.

## Step 2 — Present a brief plan for approval

Once the spec is complete, show the user a compact plan in this
shape (no headings beyond what's here, no preamble, no "great,
here's what I'll do"):

```
Plan: <one-sentence description of the simulation>

Spec
- Physics goal:  <…>
- SoLID config:  <…>
- Beam:          <…>
- GCard:         <preset name + parameter overrides>
- Output:        <runs/<id>/out.root | other if user asked>
- Analysis:      <auto-plots | custom script in analysis/ | hgc_study upstream>

Steps
1. /solid-gemc-claude:solid-gemc-init     — workspace + .sif pull + clone + 2× scons (skip if already done)
2. /solid-gemc-claude:solid-gemc-config <preset>  — copy + override USE_GUI/OUTPUT/N
3. <only if user wants non-default beam/physics:> edit gcards/<preset>.gcard
4. /solid-gemc-claude:solid-gemc-run --gcard gcards/<preset>.gcard
5. /solid-gemc-claude:solid-gemc-analyze runs/<id>
     <one line: auto-plots | custom analysis/<id>.py | container-side ROOT macro>

Defaults applied
- <only list defaults you actually filled in; skip section if none>

Open questions / risks
- <only list real ones — non-standard beam, missing canonical GCard
  for the requested config, output format that bypasses the analyze
  path, etc. Don't manufacture caveats.>
```

Then use `AskUserQuestion` with three options:

1. **Approve and run** — proceed with the steps above.
2. **Edit the spec** — user wants to change something; loop back to step 1.
3. **Just write the plan, don't run yet** — leaves the plan in the
   chat without executing; useful when the user wants a second look.

Wait for the user's choice. Do not start writing files before approval.

## Step 3 — Execute, in order

Only after the user picks "Approve and run". For each step:

1. Run it.
2. Check its post-condition before moving on:
   - `init` → `CLAUDE.md`, `.gitignore`, `log.md`, `result.md`,
     `gcards/`, `runs/`, `analysis/` exist; `.sif` cached;
     `solid_gemc/source/2.9/solid_gemc` exists and is executable.
   - `config` → `gcards/<preset>.gcard` exists; the file contains
     live `<option name="OUTPUT" .../>`, `<option name="N" .../>`,
     `<option name="USE_GUI" value="0"/>` inside the `<gcard>` block;
     `bin/solid-gemc-run validate-gcard` returns 0.
   - `run` → `runs/<id>/{gcard.gcard, out.evio, out.root, log.txt,
     config.json}` exist; `config.json` `exit_code` is 0; both
     `out.evio` and `out.root` are non-empty.
   - `analyze` → expected PNGs under `runs/<id>/`, or — for
     histogram-only output files — the schema summary lists ≥1
     histogram (the analyze command will say so).
3. If a step fails, **stop**. Report the failure (last 20 lines of
   `runs/<id>/log.txt` or the command's stderr) and ask the user how
   to proceed. Do not silently retry, do not paper over the error,
   do not move to the next step.

Maintain the workspace's handoff documents per the rule in
`templates/workspace/CLAUDE.md` non-negotiable #6 — that file is the
authoritative spec; this skill just reminds you to apply it. The
orchestrator slice:

- Capture the user's **original request verbatim** (don't paraphrase
  — future readers need to tell what was asked vs. what was inferred).
- Capture the **plan** you presented (the six-field spec + step list
  shown in step 2 above).
- Capture the user's **decision** (approved as-is, edited spec to …,
  or plan-only).
- Capture the **outcome** (run id, status, one or two lines on what
  happened).

Prepend all four as a single dated section at the top of `log.md`
before reporting back to the user. Update `result.md` with the key
numbers and plot paths after analysis. Use the template that ships
in `log.md`.

## Step 4 — Final report

End with a single block:

```
Done.
- Run id:  <id>
- Output:  runs/<id>/out.root
- Plots:   runs/<id>/<plot1>.png, runs/<id>/<plot2>.png  (or "(histogram-only output; no auto-plots — see analysis/)")
- Updated: log.md, result.md

Next: <one concrete suggestion — vary the beam energy, scale up n_events,
       try a different canonical config, run a custom analysis/<id>.py>
```

No "let me know if you have more questions". No emoji. No recap of
the plan — the plots and numbers are the recap.

## Cross-references

- `commands/solid-gemc-init.md` — workspace + image + clone + build.
- `commands/solid-gemc-config.md` — canonical GCard → workspace
  `gcards/`, with batch + EVIO-output overrides + a `.source` sidecar
  for cwd-relative geometry loading at run time.
- `commands/solid-gemc-run.md` — fires `solid_gemc <gcard>` inside
  the container; writes provenance.
- `commands/solid-gemc-analyze.md` — uproot inspect + auto-plot
  TTrees, enumerate pre-built histograms.
- `templates/workspace/CLAUDE.md` — the rules that apply once the
  workspace is scaffolded; loaded into Claude's context for every
  subsequent action in the workspace.
- `https://gemc.jlab.org` — GCard option reference (`BEAM_P`,
  `PHYSICS`, `OUTPUT`, `N`, …) for any user request that needs
  non-canonical overrides.
- Upstream `solid_gemc/analysis/hgc_study/` — the ready-made HGC
  study workflow (canonical worked example for **config + run +
  analyze**). GCards + `run.sh` + ROOT analysis scripts. Recommended
  as a first-run example. See workspace `CLAUDE.md` for the two
  paths in.
- Upstream `solid_gemc/geometry/hgc_moved/` — the canonical worked
  example for **custom detector authoring** (factory text files via
  `<detector name="..." factory="TEXT" ...>`). Has a `readme.md` plus
  the full Perl-generator → text-file pipeline. If a user needs to
  write a new detector, point them here. The plugin doesn't ship a
  detector-authoring slash command at v0.0.1.
