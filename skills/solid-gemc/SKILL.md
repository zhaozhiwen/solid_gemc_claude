---
name: solid-gemc
description: Orchestrate the full solid_gemc (SoLID experiment) simulation flow from a single natural-language user request. Load whenever the user asks to "simulate", "run", "do a SoLID / solid_gemc / PVDIS / SIDIS / J/psi / He-3 / heavy-gas Cherenkov" study — including one-shot setups like "PVDIS A_PV asymmetry on LD2 at 11 GeV" or "SIDIS heavy-gas Cherenkov yield on He-3". Captures the physics spec across seven fields (including project name), asks targeted clarifying questions when something required is missing, presents a brief plan for approval, then drives the run end-to-end: `/solid-gemc-claude:init` (one-shot workspace bootstrap), seed a project subdir from the per-project template if it doesn't exist, then a `bin/solid-gemc-run` driven simulation (the skill writes the GCard edits, runs `solid_gemc` + `evio2root` inside the container, records provenance), then `/solid-gemc-claude:analyze` for host-side uproot plots.
---

# solid-gemc — full-flow orchestrator

Use this skill the moment the user asks for a SoLID-flavored
simulation. It is the front door for everything else this plugin
does. The plugin's slash-command surface is intentionally small —
`/solid-gemc-claude:init` (workspace bootstrap) and
`/solid-gemc-claude:analyze` (host-side uproot plots).
**Everything in between is this skill's job**, driving
`bin/solid-gemc-run` directly. This keeps the plugin a thin wrapper
around upstream `solid_gemc` (which already ships canonical GCards,
`hgc_study/run.sh`, and `hgc_moved/` for detector authoring) instead
of duplicating that workflow as more slash commands.

## Workspace layout

The plugin uses a **two-tier workspace**:

- **Workspace root** (the dir `/solid-gemc-claude:init` was run in) holds
  workspace-common files: `CLAUDE.md`, `.gitignore`, `log.md`,
  `result.md`, plus the `solid_gemc/` build tree.
- **Project subdirs** (one per SoLID study, named by the user)
  contain the per-project files: their own `CLAUDE.md`, `log.md`,
  `result.md`, plus `geometry/` (custom detector authoring,
  mimics `solid_gemc/geometry/hgc_moved/`) and `analysis/` (GCards
  + run outputs + analysis scripts, mimics
  `solid_gemc/analysis/hgc_study/`).

Per-run outputs land at `<project>/analysis/runs/<id>/`.

## Default flow this skill drives

```
init                                          (one-shot per workspace)
  → ensure <project>/ subdir exists           (seed from templates/workspace/ if not)
  → pick a GCard from solid_gemc/script/      (canonical) or solid_gemc/analysis/*/
  → copy to <project>/analysis/<preset>.gcard + apply batch overrides
  → bin/solid-gemc-run exec "solid_gemc <gcard>"     (run gemc; emits out.evio)
  → bin/solid-gemc-run exec "evio2root -INPUTF=out.evio"  (post-convert)
  → write <project>/analysis/runs/<id>/{gcard.gcard, out.evio, out.root, log.txt, config.json}
  → /solid-gemc-claude:analyze <project>/analysis/runs/<id>   (host-side uproot)
```

`init` is one-shot per workspace and idempotent. **Step 3a force-
checks the workspace state and invokes init if anything is missing**
— no extra prompt at that point. The user has already approved when
they approved the plan, and init is a prerequisite for everything
else this skill does.

There is no bring-your-own-binary alternative for solid_gemc. If
the user needs something the canonical configs don't cover, the
divergence point is **the GCard** — they pick a closer canonical
and edit it, or hand-author one. The binary, the geometry tree,
and the physics list all come from upstream solid_gemc.

## Non-negotiables

Two hard rules that bound this skill's execution. Both apply
every time the skill activates, no exceptions outside the narrow
carve-outs at the bottom of each section.

### 1. Plan first, approval gate always

**This skill never creates files or runs commands without explicit
user approval of the plan first — even when the user's initial
message looks fully specified.** Your interpretation of "PVDIS LD2
11 GeV 10000 events default analysis" is one of many. You might
pick the wrong canonical GCard (`solid_PVDIS_LD2_moved_full` vs
`solid_PVDIS_LD2_simple`), default to a wrong analysis shape, or
seed a project subdir with an unintended name. Showing your
interpretation first surfaces those misreads cheaply, before any
artifact is written.

The discipline:

1. **Always derive the seven-field spec from the user's message**
   (step 1). Even when the user appears to have given "all the
   details", make the derivation explicit — what you read into
   each field, and why.
2. **Always ask via `AskUserQuestion`** for any field that is
   ambiguous (not just missing). If "LD2" could resolve to two
   canonicals, ask. Don't guess silently.
3. **Always present the plan** (step 2) and gate execution on the
   `AskUserQuestion` approval choice.
4. **Never start step 3 without the explicit "Approve and run"
   choice.** A user message that says "go" or "yes" before they
   have seen the plan does not authorize execution — the plan
   must be on screen first, presented in this turn.

This rule holds even when the user is annoyed, says "stop asking,
just run it", or has done this dance before. The plan
presentation is cheap; the alternative is a wrong run, a
mis-named project subdir, or a slow batch firing against the
wrong canonical.

Narrow exceptions, both already documented in "Do not load
this skill when" below: (a) pure re-runs of an existing
`<project>/analysis/<preset>.gcard`, where the user has already
seen the GCard and is iterating; (b) `solid-gemc-analyze` against
an existing `runs/<id>/`. Neither creates new artifacts that the
user hasn't already seen.

### 2. Log every user input + the final plan to `<project>/log.md`

**Every orchestration leaves a verbatim trail in
`<project>/log.md`.** The trail is what makes future Claude
sessions (or a future human reader) able to tell what was asked
versus what was inferred — paraphrasing erases that distinction.

A complete log entry has four sections, prepended as a single
dated block at the top of `<project>/log.md`:

```
## YYYY-MM-DD HH:MM UTC — <one-line headline>

### User input (verbatim)

> <user message 1, quoted verbatim — block-quote with `>` prefix>
>
> <user message 2 if the spec was revised mid-orchestration>
>
> <…every user message in this orchestration cycle, in order>

### Final plan (the approved version)

- Project name:  <…>
- Physics goal:  <…>
- SoLID config:  <…>
- Beam:          <…>
- GCard:         <preset + parameter overrides>
- Output:        <…>
- Analysis:      <…>

Steps (the seven-field plan you presented in step 2):
1. <…>
2. <…>
…

Defaults applied (only if any):
- <…>

### Decision

<"Approved and run" | "Edited spec to …, then approved" | "Plan only — did not run">

### Outcome

- Run id:  <id> (or "n/a — plan only" or "stopped at step <N>: <reason>")
- Status:  <succeeded | failed at step <N> with <reason>>
- Notes:   <one or two lines: what worked, what surprised, what's next>
```

The four sections are mandatory. Specifically:

- **User input** must quote every user message verbatim
  (using markdown `>` block-quote). Do not summarize. If the
  user revised the spec, capture all revisions in order, not
  just the final ask.
- **Final plan** must be the approved version (after any user
  edits), with all seven spec fields filled in plus the step
  list and any defaults you applied. Future readers should be
  able to tell from this block alone what would have been run.
- **Decision** must record which option from step 2's
  `AskUserQuestion` was picked, and any spec edits the user
  made along the way.
- **Outcome** must record the run id and status. Even if the
  orchestration is "plan only", say so; even if it crashed at
  step 3c, record the partial state with a pointer to
  `<project>/analysis/runs/<id>/log.txt`.

**When the log entry is written:** at the very end of the
orchestration, after `analyze` completes (or after the
unrecoverable failure that stopped the flow). If a crash leaves
the run dir incomplete, still write the log entry with
`Outcome: stopped at step <N>`. Never skip the log entry — a
silent run is the worst possible outcome.

Also append a one-line entry to the workspace-level `log.md`
(the lightweight cross-project index at the workspace root):
`YYYY-MM-DD — <project>: <one-line milestone>` plus a link to
`<project>/log.md` for detail.

This rule has no exceptions. Even the carve-out cases above
(pure re-runs, `analyze` alone) log a short entry — at minimum
the user's request + the run id + the outcome.

## When to load this skill

Trigger on any of:

- "let's do a SoLID simulation", "simulate PVDIS / SIDIS / J/psi /
  DDVCS / He-3 …", "run solid_gemc against …", "set up a
  solid_gemc study of …".
- A physics setup that names a SoLID magnet config (PVDIS, SIDIS,
  CLEO, BaBar), a SoLID target (LD2, LH2, NH3, ³He), or a SoLID
  detector subsystem (LGC/HGC heavy-gas Cherenkov, GEM, EC, MRPC,
  SPD, baffle) without "solid_gemc" named explicitly.
- "where do I start?" inside a workspace scaffolded by this plugin.
- The upstream HGC study: "run the heavy-gas Cherenkov study from
  solid_gemc/analysis/hgc_study". That is the canonical worked
  example — use one of its GCards as the preset; if the user just
  wants to follow upstream's `run.sh` verbatim, recommend
  `bin/solid-gemc-run shell` and skip the skill flow.

Do **not** load this skill when:

- The user already has a `<project>/analysis/runs/<id>/out.root`
  and only wants plots — call
  `/solid-gemc-claude:analyze` directly.
- A previous run is failing and the user wants to debug — that's a
  debugging task, not a fresh orchestration. Read the run dir's
  `log.txt` + `config.json` and reason from there.
- The user is iterating on an existing
  `<project>/analysis/<preset>.gcard` and just wants a re-run —
  execute the run loop in step 3 below directly without re-running
  the gap-check.

**Co-existence with `geant4_claude/skills/geant4`.** SoLID-specific
vocabulary (`PVDIS`, `SIDIS`, `solid_gemc`, `J/psi`, `He-3`, the
SoLID subsystem names) should keep description-match arbitration
clean. If a user request mentions "Geant4" or "GDML" or "main.cc"
without any SoLID context, prefer the `geant4` skill. If a request
mentions both ("simulate PVDIS using Geant4"), this skill wins —
SoLID is more specific.

## Step 1 — Capture and gap-check the spec

A working solid_gemc simulation needs all seven fields below. Read
the user's message and, for each, decide whether they specified
it, whether a default is safe, or whether you must ask.

| Field | What it is | Example |
|---|---|---|
| **Project name** | The `<name>/` subdir under the workspace root where this study lives | `pvdis_ld2_aPV`, `sidis_he3_hgc`, `jpsi_lh2_acceptance`, `cherenkov_radius_scan` |
| **Physics goal** | What's being measured / counted | "PVDIS A_PV asymmetry vs Q²", "HGC photoelectron yield vs Cherenkov radius", "J/psi recoil acceptance on LH2" |
| **SoLID config** | Magnet + spectrometer configuration that fixes the geometry | "PVDIS, LD2 target, full magnet config", "SIDIS He-3, heavy-gas Cherenkov in", "J/psi LH2 simple" |
| **Beam** | Particle, energy, event count | "11 GeV e-, 10000 events" |
| **GCard** | Preset from `solid_gemc/script/` or `solid_gemc/analysis/*/`, with any parameter overrides | `solid_PVDIS_LD2_moved_full.gcard` (canonical), `N=10000`, `OUTPUT=evio,out.evio` |
| **Output** | gemc 2.9 writes **EVIO natively** (the build has no ROOT writer); the skill post-converts to ROOT via `evio2root` so uproot analysis works the same. | `<project>/analysis/runs/<id>/out.evio` (raw) + `out.root` (converted) |
| **Analysis** | Plots / numbers to produce | "auto-histogram all numeric branches", "asymmetry binned in Q²", "PE yield vs radius via custom script in `<project>/analysis/`" |

### What must be asked, never guessed

- **Physics goal** — without it, the project name and run id are
  meaningless and the analysis step is undefined.
- **SoLID config** — there are ~20 canonical GCards in
  `solid_gemc/script/`. PVDIS vs SIDIS vs J/psi are different
  physics; LD2 vs LH2 vs ³He vs NH3 are different targets. Never
  pick one without explicit user choice — list available presets
  and ask.
- **Beam energy** if not standard for the chosen config (most
  SoLID configs assume 11 GeV; flag and ask if the user implies
  otherwise).

For each missing required field, ask one focused question via
`AskUserQuestion` for multi-option fields, or plain prose for
one-line answers. Tell the user *which* field is missing and *why*
a default is not safe. Don't chain a bunch of guesses together.

### What can default

- **Project name** — derive from (SoLID config + physics goal):
  e.g. "PVDIS A_PV on LD2" → `pvdis_ld2_aPV`. Confirm with the
  user once in the plan. If a same-named `<project>/` already
  exists in the workspace, default to **using it** (the skill
  adds runs to its `analysis/runs/`); ask only if the user
  appeared to want a fresh project.
- **GCard preset name** — once "SoLID config" is locked, the
  preset is derived from it. PVDIS + LD2 + full →
  `solid_PVDIS_LD2_moved_full`.
- **n_events** — first run defaults to 100 (fast smoke). Tell the
  user this in the plan and suggest a production number for the
  follow-up.
- **OUTPUT format** — `evio,out.evio`. gemc 2.9 in JLabCE 2.5
  supports only `evio` and `txt` natively (no ROOT writer); the
  skill post-converts EVIO → ROOT via `evio2root` so
  `/solid-gemc-claude:analyze` reads `out.root` the same way as any
  TTree-based file. If the user explicitly asks for `txt` output,
  warn that `/solid-gemc-claude:analyze` can't auto-plot it.
- **USE_GUI** — always 0 in the orchestrator (batch run). Even if
  the canonical GCard has `USE_GUI=1`, the skill flips it.
- **Physics list, hall material, geometry detail level** — never
  touch; the canonical preset has the right values for its
  physics.

### When the user actually wants the upstream `hgc_study` flow

If the user asks specifically about "heavy-gas Cherenkov study",
"HGC mirror radius study", "compare He-3 vs NH3 HGC", or anything
that points at `solid_gemc/analysis/hgc_study/`: that's an upstream
ready-made workflow with its own `load.sh` / `run.sh` /
`analysis.C`. Two ways in:

- **Skill-driven** — create a project subdir (e.g.
  `hgc_study_<variant>/`), copy one of the hgc GCards into its
  `analysis/`, run through this skill. The `analyze` step gives
  host-side uproot plots from the EVIO → ROOT conversion.
- **Upstream-driven** — `bin/solid-gemc-run shell` drops the user
  into a tcsh prompt with the env set; they
  `cd solid_gemc/analysis/hgc_study` and run `./run.sh`. Their
  analysis is upstream's `.C` scripts (run via
  `bin/solid-gemc-run root <.C>`).

Mention both in the plan when the request maps onto hgc_study;
let the user pick.

## Step 2 — Present a brief plan for approval

Once the spec is complete, show the user a compact plan in this
shape (no headings beyond what's here, no preamble, no "great,
here's what I'll do"):

```
Plan: <one-sentence description of the simulation>

Spec
- Project name:  <…>
- Physics goal:  <…>
- SoLID config:  <…>
- Beam:          <…>
- GCard:         <preset name + parameter overrides>
- Output:        <<project>/analysis/runs/<id>/out.root | other if user asked>
- Analysis:      <auto-plots | custom script in <project>/analysis/ | hgc_study upstream>

Steps
1. /solid-gemc-claude:init    — workspace + .sif pull + clone + 2× scons (skip if already done)
2. seed <project>/ from templates/workspace/. (skip if already there)
3. copy <project>/analysis/<preset>.gcard from solid_gemc/script/<preset>.gcard (or .../analysis/.../<preset>.gcard); apply USE_GUI=0 + OUTPUT=evio,out.evio + N=<n>
4. <only if user wants non-default beam/physics:> edit <project>/analysis/<preset>.gcard
5. bin/solid-gemc-run exec "solid_gemc <abs gcard> -OUTPUT=evio,<abs run dir>/out.evio"  (from the gcard's upstream dir)
   then bin/solid-gemc-run exec "evio2root -INPUTF=out.evio"   (from <project>/analysis/runs/<id>/)
   write <project>/analysis/runs/<id>/{gcard.gcard, out.evio, out.root, log.txt, config.json}
6. /solid-gemc-claude:analyze <project>/analysis/runs/<id>
     <one line: auto-plots | custom <project>/analysis/<id>.py | container-side ROOT macro>

Defaults applied
- <only list defaults you actually filled in; skip section if none>

Open questions / risks
- <only list real ones — non-standard beam, missing canonical GCard
  for the requested config, output format that bypasses the analyze
  path, etc. Don't manufacture caveats.>
```

Then use `AskUserQuestion` with three options. **This gate is
mandatory** — present it even when the user's initial message
already said "go" or "yes" (see "Non-negotiable: plan first,
approval gate always" above).

1. **Approve and run** — proceed with the steps above.
2. **Edit the spec** — user wants to change something; loop back to step 1.
3. **Just write the plan, don't run yet** — leaves the plan in the
   chat without executing; useful when the user wants a second look.

Wait for the user's explicit "Approve and run" choice. **Do not
start writing files or running commands before that choice
appears.** A pre-emptive "go" earlier in the conversation does
not count — the plan must be on screen *in this turn* before
authorization is meaningful.

## Step 3 — Execute, in order

Only after the user picks "Approve and run". Each sub-step has a
post-condition check; if it fails, stop and report.

### 3a. Force-check init; run it if anything is missing

The simulation flow assumes a fully-initialized workspace. **Hard
check** for all of:

- The four workspace-common files at cwd: `CLAUDE.md`, `.gitignore`,
  `log.md`, `result.md`.
- `solid_gemc/.git/` (the upstream tree is cloned).
- `solid_gemc/source/2.9/solid_gemc` (the binary exists and is
  executable).
- The `.sif` is cached (`bin/solid-gemc-run info` reports a path,
  not `[not pulled]`).

If **any** are missing, invoke `/solid-gemc-claude:init` immediately
and wait for it to finish. Do not ask the user again — the plan
they approved listed init as step 1 with "skip if already done", so
running it when not-already-done is exactly what the approval covers.

```bash
init_needed=0
for f in CLAUDE.md .gitignore log.md result.md; do
  [[ -f "$f" ]] || { init_needed=1; break; }
done
[[ -d solid_gemc/.git ]]                  || init_needed=1
[[ -x solid_gemc/source/2.9/solid_gemc ]] || init_needed=1

if (( init_needed )); then
  echo "[skill] workspace not fully initialized; invoking /solid-gemc-claude:init"
  # Invoke the slash command (the agent dispatches; do not return
  # control to the user until init reports success).
fi
```

Note that `bin/solid-gemc-run clone` and `build` are themselves
idempotent — `clone` now prints the existing commit SHA and
warns-but-continues when `solid_gemc/.git` is already present;
`build` re-invokes scons which incrementally no-ops when nothing
has changed. So invoking init on a partially-initialized workspace
is safe.

Post-condition: all four workspace-common files exist; `.sif` is
cached; `solid_gemc/.git/` exists; `solid_gemc/source/2.9/solid_gemc`
is executable. If init returns non-zero, **stop** — report the
failure (last 20 lines of init's output) and do not proceed.

### 3b. Seed the project subdir if missing

```bash
PROJECT=<resolved from spec>
if [[ ! -d "$PROJECT" ]]; then
  cp -r "${CLAUDE_PLUGIN_ROOT}/templates/workspace/." "$PROJECT/"
fi
```

Post-condition: `<project>/` exists with `CLAUDE.md`, `log.md`,
`result.md`, `geometry/`, `analysis/`. If it pre-existed, leave it
alone — never clobber a user's project files.

### 3c. Prepare the GCard

Resolve the preset against `solid_gemc/script/` first, then
`solid_gemc/analysis/*/`. Copy to `<project>/analysis/<preset>.gcard`.
Apply batch overrides **only inside the live `<gcard>…</gcard>`
block** (canonicals often carry a `<!-- comment out … -->` example
block; leave it alone). The robust regex strips any existing
`OUTPUT` / `N` / `USE_GUI` lines (the
`name="USE_GUI"  value=...` double-space variant in some
canonicals is matched by `[^>]*`), then appends the overrides at
the bottom of the live block:

```bash
PRESET=<resolved>
SRC=<solid_gemc/script/solid_${PRESET}.gcard or under solid_gemc/analysis/*/>
DEST="${PROJECT}/analysis/$(basename "$SRC")"
SOURCE_DIR=$(dirname "$SRC")   # needed at run time; gemc 2.9 resolves <detector name="..."> relative to cwd, not the GCard's location

cp "$SRC" "$DEST"
python3 - "$DEST" "${N_EVENTS:-100}" "out.evio" "0" <<'PY'
import re, sys, pathlib
path, n_events, output_name, gui_keep = sys.argv[1:5]
strip_keys = ['OUTPUT', 'N'] + ([] if gui_keep == '1' else ['USE_GUI'])
text = pathlib.Path(path).read_text()
m = re.search(r'(<gcard>)(.*?)(</gcard>)', text, re.DOTALL)
if not m:
    sys.exit(f"[skill] no <gcard>...</gcard> block in {path}")
head, body, tail = m.groups()
body = re.sub(
    r'^[ \t]*<option name="(' + '|'.join(strip_keys) + r')"[^>]*/>[ \t]*\n',
    '', body, flags=re.MULTILINE)
adds = [
    f'<option name="OUTPUT" value="evio,{output_name}"/>',
    f'<option name="N" value="{n_events}"/>',
]
if gui_keep != '1':
    adds.append('<option name="USE_GUI" value="0"/>')
new_body = body.rstrip() + '\n' + '\n'.join(adds) + '\n'
pathlib.Path(path).write_text(text[:m.start(2)] + new_body + text[m.end(2):])
PY

SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
  "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" validate-gcard "$DEST"
```

Post-condition: `<project>/analysis/<preset>.gcard` exists; the
live `<gcard>` block contains the three overrides; `validate-gcard`
returns 0.

### 3d. Run gemc + evio2root

Two important disciplines: (1) **cwd-relative geometry lookup** —
gemc 2.9 resolves `<detector name="…">` from the process cwd, not
from the GCard's path, so we `cd "$SOURCE_DIR"` (the dir holding
the canonical's geometry siblings) before invoking `solid_gemc`.
(2) **Absolute paths** for the GCard and OUTPUT, since cwd has
changed. Pipe-exit-code capture is portable across bash and zsh
via a tempfile (the harness shell may be either).

```bash
RUN_ID=$(date -u +%Y%m%d-%H%M%S)-$(head -c 12 /dev/urandom | base32 | tr 'A-Z' 'a-z' | head -c 6)
RUN_DIR="${PROJECT}/analysis/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"
cp "$DEST" "$RUN_DIR/gcard.gcard"

WORKSPACE_ABS=$(readlink -f .)
RUN_DIR_ABS="${WORKSPACE_ABS}/${RUN_DIR}"
GCARD_ABS="${WORKSPACE_ABS}/${RUN_DIR}/gcard.gcard"

START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ); START_EPOCH=$(date +%s)

GEMC_EC_FILE=$(mktemp)
( cd "$SOURCE_DIR" && \
  SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
  SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
    "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" exec \
      "solid_gemc '${GCARD_ABS}' -OUTPUT='evio,${RUN_DIR_ABS}/out.evio'"; \
  echo $? > "${GEMC_EC_FILE}" ) 2>&1 | tee "${RUN_DIR_ABS}/log.txt"
GEMC_EXIT=$(cat "${GEMC_EC_FILE}"); rm -f "${GEMC_EC_FILE}"

EVIO2ROOT_EXIT=0
if [[ "$GEMC_EXIT" = "0" && -f "${RUN_DIR_ABS}/out.evio" ]]; then
  EVIO_EC_FILE=$(mktemp)
  ( cd "$RUN_DIR_ABS" && \
    SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
    SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
      "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" exec \
        "evio2root -INPUTF=out.evio"; \
    echo $? > "${EVIO_EC_FILE}" ) 2>&1 | tee -a "${RUN_DIR_ABS}/log.txt"
  EVIO2ROOT_EXIT=$(cat "${EVIO_EC_FILE}"); rm -f "${EVIO_EC_FILE}"
fi
END_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ); END_EPOCH=$(date +%s)
EXIT_CODE=$([ "$GEMC_EXIT" = "0" ] && echo "$EVIO2ROOT_EXIT" || echo "$GEMC_EXIT")
```

Post-condition: `<project>/analysis/runs/<id>/{gcard.gcard,
out.evio, out.root, log.txt}` exist and are non-empty;
`EXIT_CODE` is 0.

### 3e. Write the provenance `config.json`

```bash
SIF_NAME=$(grep '^SIF_NAME=' "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" | head -1 | cut -d'"' -f2)
SOLID_GEMC_SHA=$(cd solid_gemc && git rev-parse HEAD 2>/dev/null || echo unknown)
GEMC_VERSION_PINNED=$(grep '^GEMC_VERSION=' "${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run" | head -1 | cut -d'"' -f2)
N_EVENTS=$(grep -oE '<option name="N" value="[^"]+"' "$RUN_DIR/gcard.gcard" | head -1 | sed 's/.*value="//; s/"$//')

python3 - "$RUN_DIR/config.json" <<PY
import json, sys, pathlib
d = {
  "run_id":           "${RUN_ID}",
  "project":          "${PROJECT}",
  "gcard_source":     "${DEST}",
  "gcard_frozen":     "${RUN_DIR}/gcard.gcard",
  "source_dir":       "${SOURCE_DIR}",
  "n_events":         "${N_EVENTS}",
  "sif_name":         "${SIF_NAME}",
  "solid_gemc_repo":  "https://github.com/JeffersonLab/solid_gemc",
  "solid_gemc_sha":   "${SOLID_GEMC_SHA}",
  "gemc_version":     "${GEMC_VERSION_PINNED}",
  "start_utc":        "${START_ISO}",
  "end_utc":          "${END_ISO}",
  "wall_seconds":     ${END_EPOCH} - ${START_EPOCH},
  "gemc_exit_code":   ${GEMC_EXIT},
  "evio2root_exit":   ${EVIO2ROOT_EXIT},
  "exit_code":        ${EXIT_CODE},
  "command":          "solid_gemc <gcard> -OUTPUT=evio,<run>/out.evio; evio2root -INPUTF=out.evio",
  "cwd_gemc":         "${SOURCE_DIR}",
  "cwd_evio2root":    "${RUN_DIR}",
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(d, indent=2) + "\n")
PY
```

`<project>/analysis/runs/<id>/config.json` is the **provenance
record**. Treat the run dir as immutable from this point on.

### 3f. Analyze

Hand off to
`/solid-gemc-claude:analyze <project>/analysis/runs/<id>`
— host-side uproot, auto-plots numeric branches into PNGs
alongside `out.root`. For asymmetries / fits / multi-run
comparisons, write a script under `<project>/analysis/`.

### Failure handling

If a sub-step's post-condition check fails, **stop**. Report the
failure (last 20 lines of the run's `log.txt` or the command's
stderr) and ask the user how to proceed. Do not silently retry,
do not paper over the error, do not move to the next step.

### Handoff documents

Apply **Non-negotiable #2** at the top of this skill (log every
user input + final plan to `<project>/log.md`). The four-section
block (User input verbatim → Final plan → Decision → Outcome)
gets prepended at the top of `<project>/log.md` at the very end
of step 3, after `analyze` completes (or after the failure that
stopped the flow). Don't skip it; even a crashed run gets a log
entry with `Outcome: stopped at step <N>`.

In addition: update `<project>/result.md` with the key numbers
and plot paths after analysis (only for runs that produced
notable results — skip for trivial smokes). Append a one-line
entry to the workspace-level `log.md` (the cross-project index)
pointing at `<project>/log.md` for detail.

## Step 4 — Final report

End with a single block:

```
Done.
- Project: <project>
- Run id:  <id>
- Output:  <project>/analysis/runs/<id>/out.root
- Plots:   <project>/analysis/runs/<id>/<plot1>.png, …  (or "(histogram-only output; no auto-plots)")
- Updated: <project>/log.md, <project>/result.md, log.md

Next: <one concrete suggestion — vary the beam energy, scale up n_events,
       try a different canonical config, run a custom <project>/analysis/<id>.py>
```

No "let me know if you have more questions". No emoji. No recap
of the plan — the plots and numbers are the recap.

## Cross-references

- `commands/init.md` — workspace bootstrap (the four
  workspace-common files + image + clone + build).
- `commands/analyze.md` — uproot inspect + auto-plot
  TTrees, enumerate pre-built histograms.
- `bin/solid-gemc-run` — the maintainer-side wrapper this skill
  drives via `exec`, `validate-gcard`, `shell`, `root`. Single
  seam for everything that needs the JLabCE 2.5 container.
- `templates/CLAUDE.md` — workspace-wide rules loaded into
  Claude's context for every session in the workspace.
- `templates/workspace/CLAUDE.md` — per-project rules; copied
  into each project subdir at seed time.
- `https://gemc.jlab.org` — GCard option reference (`BEAM_P`,
  `PHYSICS`, `OUTPUT`, `N`, …) for any user request that needs
  non-canonical overrides. Plugin-local mirror of the SoLID-side
  "how to use gemc" guide lives in
  `reference/gemc_simulation_general_note.md`.
- `reference/gemc.md` and `reference/solid_gemc.md` — source-
  level digests of the gemc 2.9 framework and the SoLID hit
  processors. Consult when a user hits an unexpected behavior in
  geometry loading, hit-processor output, build flags, or option
  overrides.
- Upstream `solid_gemc/analysis/hgc_study/` — the ready-made HGC
  study workflow (canonical worked example for **config + run +
  analyze**). GCards + `run.sh` + ROOT analysis scripts.
  Recommended as a first-run example.
- Upstream `solid_gemc/geometry/hgc_moved/` — the canonical
  worked example for **custom detector authoring** (factory text
  files via `<detector name="..." factory="TEXT" ...>`). Has a
  `readme.md` plus the full Perl-generator → text-file pipeline.
  If a user needs to write a new detector, point them here. The
  plugin doesn't ship a detector-authoring slash command at
  v0.0.3.
