---
name: solid-gemc
description: Orchestrate the full solid_gemc (SoLID experiment) simulation flow from a single natural-language user request. Load whenever the user asks to "simulate", "run", "do a SoLID / solid_gemc / PVDIS / SIDIS / J/psi / He-3 / heavy-gas Cherenkov" study — including one-shot setups like "PVDIS A_PV asymmetry on LD2 at 11 GeV" or "SIDIS heavy-gas Cherenkov yield on He-3". Captures the physics spec across seven fields (including project name), asks targeted clarifying questions when something required is missing, presents a brief plan for approval, then drives the run end-to-end via `bin/solid-gemc-run` — `init` (one-shot workspace bootstrap), seed a project subdir from the per-project template if it doesn't exist, then the simulation (the skill writes the GCard edits, runs `solid_gemc` + `evio2root` inside the container, records provenance), then `analyze` for host-side uproot plots. Works on Claude Code and Codex CLI.
---

# solid-gemc — full-flow orchestrator

Use this skill the moment the user asks for a SoLID-flavored
simulation. It is the front door for everything else this plugin
does. The whole workflow runs through one wrapper,
`bin/solid-gemc-run`: `init` (workspace bootstrap), the
simulation loop in between, and `analyze` (host-side uproot plots).
On Claude Code those endpoints are also exposed as the
`/solid-gemc-claude:init` and `/solid-gemc-claude:analyze` slash
commands; on Codex (and any other harness) this skill calls the
wrapper subcommands directly. Either way the wrapper is the single
seam. This keeps the plugin a thin layer over upstream `solid_gemc`
(which already ships canonical GCards, `hgc_study/run.sh`, and
`hgc_moved/` for detector authoring).

## Locating the runtime (all platforms)

Everything below drives the wrapper through two variables. Resolve
them once at the start of execution, then use `$SGC_RUN` / `$SGC_ROOT`
everywhere — never hardcode a platform's plugin-path env var:

```bash
# $SGC_RUN — the wrapper. Claude sets CLAUDE_PLUGIN_ROOT; otherwise
# (Codex, standalone) the installed plugin puts solid-gemc-run on PATH.
SGC_RUN="${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run}"
[ -x "$SGC_RUN" ] || SGC_RUN="$(command -v solid-gemc-run)" \
  || { echo "[skill] solid-gemc-run not found on PATH"; exit 1; }

# $SGC_ROOT — the plugin root (for templates/ and reference/).
SGC_ROOT="$("$SGC_RUN" paths | awk '/^root:/{print $2}')"
```

The wrapper resolves its own cache and venv (it falls back to
`~/.cache` / `~/.local/share` off Claude), so this skill no longer
prefixes `SOLID_GEMC_CLAUDE_CACHE=…` on every call.

## Workspace layout

The plugin uses a **two-tier workspace**:

- **Workspace root** (the dir `init` was run in) holds
  workspace-common files: `CLAUDE.md`, `.gitignore`, `log.md`,
  `result.md`, `report.html`, plus the `solid_gemc/` build tree.
- **Project subdirs** (one per SoLID study, named by the user)
  contain the per-project files: their own `CLAUDE.md`, `log.md`,
  `result.md`, `report.html`. GCards, run outputs, analysis scripts,
  and (if applicable) custom-detector Perl generators all live
  directly in the project subdir — no enforced subdir split, mirroring
  the flat style of upstream `solid_gemc/analysis/hgc_study/`.

Per-run outputs land at `<project>/runs/<id>/`.

## Default flow this skill drives

```
init                                          (one-shot per workspace)
  → ensure <project>/ subdir exists           (seed from templates/workspace/ if not)
  → pick a GCard from solid_gemc/script/      (canonical) or solid_gemc/analysis/*/
  → copy to <project>/<preset>.gcard + apply batch overrides
  → bin/solid-gemc-run exec "solid_gemc <gcard>"     (run gemc; emits out.evio)
  → bin/solid-gemc-run exec "evio2root -INPUTF=out.evio -R=flux"  (post-convert; -R=flux publishes the raw integrated bank — see step 3d)
  → write <project>/runs/<id>/{gcard.gcard, out.evio, out.root, log.txt, config.json}
  → solid-gemc-run analyze <project>/runs/<id>        (host-side uproot)
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

**This skill never creates files or runs commands without an
explicit `AskUserQuestion` "Approve and run" choice picked in the
current turn — full stop. Not when the user says "go". Not when
the user says "yes". Not when the user says "no clarifying
questions". Not when the user says "just run it" or "skip the
approval". Not when the initial message looks fully specified.**

Your interpretation of "PVDIS LD2 11 GeV 10000 events default
analysis" is one of many. You might pick the wrong canonical
GCard (`solid_PVDIS_LD2_moved_full` vs `solid_PVDIS_LD2_simple`),
default to a wrong analysis shape, seed a project subdir with an
unintended name, or pick wrong defaults for materials / mirror
tilt / focal length / sensor QE. Showing your interpretation first
surfaces those misreads cheaply, before any artifact is written.

#### Clarifying questions ≠ approval gate

These are two different things, governed by two different rules.
The user can waive one but not the other.

| Question type | What it covers | Waivable by user? |
|---|---|---|
| Clarifying (step 1) | Ambiguous spec fields — which GCard variant, what beam energy, which project name | **Yes** — if the user says "fill in sensible defaults" or "no clarifying questions", skip these and fill defaults |
| Approval gate (step 2) | Final execution authorization for THIS plan in THIS turn | **Never. Mandatory regardless of what the user said about questions.** |

If the user says "stop asking clarifying questions and just run
my study": fill in defaults instead of asking, present the
resulting plan, **then still gate on a final `AskUserQuestion`
with Approve / Edit / Plan-only options.** The user can pick
"Approve and run" in one click — cost to them: a few seconds. Cost
of skipping: a wrong run, mis-named project, or hours of
re-doing work because a default was wrong.

#### What "always" means, concretely

- The approval gate is **a specific structured choice with the
  three Approve / Edit / Plan-only options** — not a text
  presentation that ends with "let me know if this looks right",
  not a prose summary asking for confirmation. On Claude Code this
  is an `AskUserQuestion` tool call. On Codex (or any harness
  without `AskUserQuestion`) it is an explicit, numbered
  Approve / Edit / Plan-only question the user must answer before
  you proceed — the requirement (an explicit per-turn pick before
  any write) is identical; only the mechanism differs. The user
  must pick an option.
- The gate fires **after** the plan is on screen as text in the
  same turn. The order is: present the plan as text →
  `AskUserQuestion` with three options → wait for the explicit
  option pick → then and only then proceed to step 3.
- A user message that said "go" or "yes" **before** the plan was
  presented in this turn is **not** the approval. The approval
  is the option the user picks **after** seeing the plan in this
  turn.
- Pre-fetched authorization from earlier in the conversation
  (e.g., "any setting, just go") does not transfer across turns
  or across plans. Every plan gets its own gate.

#### Failure pattern to recognize and reject in yourself

If your inner monologue contains any of these, **stop and fire
the gate before proceeding**:

> "The user said no clarifying questions, so I'll just run it."
> (Wrong: clarifying questions ≠ approval gate.)

> "The plan is on screen as text, so the user can read it before
> I act."
> (Wrong: text ≠ tool call. Without `AskUserQuestion`, the user
> has no structured way to redirect.)

> "The user already said 'go' / 'yes' in their first message."
> (Wrong: pre-emptive authorization before seeing the plan does
> not count.)

> "This is the third turn in a row of the same plan, the user
> obviously approves."
> (Wrong: every plan, every turn, gets its own gate.)

> "It's faster to just do it and ask forgiveness."
> (Wrong: every wrong run is more expensive than the 3 seconds
> the gate costs.)

#### Narrow exceptions

Only these two cases skip the gate, and they're carve-outs for
**no new artifacts being created**:

(a) **Pure re-run** of an existing
`<project>/<preset>.gcard` that the user explicitly
named — the user has already seen and approved this GCard's
content in a prior gated orchestration. The re-run produces a
new `runs/<id>/` but uses the already-approved GCard.

(b) **`analyze` against an existing `runs/<id>/`** — no new
simulation artifacts; just plots from an existing ROOT file.

**Neither** "the user said no questions" nor "the user said go
already" nor "the user is annoyed" nor "the plan is obvious"
qualifies as an exception. If you're tempted to add a new
exception, you're wrong — fire the gate.

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
  `<project>/runs/<id>/log.txt`.

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

- The user already has a `<project>/runs/<id>/out.root`
  and only wants plots — run `solid-gemc-run analyze` directly
  (or the `/solid-gemc-claude:analyze` slash command on Claude Code).
- A previous run is failing and the user wants to debug — that's a
  debugging task, not a fresh orchestration. Read the run dir's
  `log.txt` + `config.json` and reason from there.
- The user is iterating on an existing
  `<project>/<preset>.gcard` and just wants a re-run —
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
| **Output** | gemc 2.9 writes **EVIO natively** (the build has no ROOT writer); the skill post-converts to ROOT via `evio2root` so uproot analysis works the same. | `<project>/runs/<id>/out.evio` (raw) + `out.root` (converted) |
| **Analysis** | Plots / numbers to produce | "auto-histogram all numeric branches", "asymmetry binned in Q²", "PE yield vs radius via custom script in `<project>/`" |

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

### Project name contract (safety boundary — never waivable)

The project name becomes a directory under the workspace root and
is interpolated into `cp`/`mkdir` paths, the run dir, and the
**unquoted** `config.json` heredoc in step 3e. An unconstrained
name (`/`, `..`, whitespace, quotes, `$()`, backticks, a leading
`-`, or empty) can write outside the workspace, corrupt the
provenance JSON, or inject into later shell. So the resolved
project name **must** match exactly:

```
^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$
```

One anchored rule closes every vector: no `/` (no traversal),
first char alnum/`_` (so no leading `-` flag injection, no hidden
dir, and `.`/`..` cannot match), no whitespace or shell
metacharacters, length 1–64.

- **Derived default** (from SoLID config + physics goal):
  slugify to satisfy the contract by construction — map any run
  of disallowed characters to `_`, strip a leading non-`[A-Za-z0-9_]`,
  trim to 64. If slugification empties it, use `solid_run`.
- **Explicit user-supplied name** that violates the contract:
  **reject and ask for a compliant one**, quoting the rule. This
  is a safety boundary, not a spec ambiguity — it is **not**
  covered by "fill in sensible defaults" / "no clarifying
  questions" and **not** by the approval gate. Silently rewriting
  a name the user typed is also wrong (it changes where their
  study lands); ask.

Step 3b re-checks this with a hard fail-closed guard before the
first filesystem write — that guard, not this prose, is the
enforceable line of defense.

### What can default

- **Project name** — derive from (SoLID config + physics goal):
  e.g. "PVDIS A_PV on LD2" → `pvdis_ld2_aPV`. Confirm with the
  user once in the plan. If a same-named `<project>/` already
  exists in the workspace, default to **using it** (the skill
  adds runs to its `runs/`); ask only if the user
  appeared to want a fresh project.
- **GCard preset name** — once "SoLID config" is locked, the
  preset is derived from it. PVDIS + LD2 + full →
  `solid_PVDIS_LD2_moved_full`.
- **n_events** — first run defaults to 100 (fast smoke). Tell the
  user this in the plan and suggest a production number for the
  follow-up.
- **OUTPUT format** — `evio,out.evio`. gemc 2.9 in JLabCE 2.5
  supports only `evio` and `txt` natively (no ROOT writer); the
  skill post-converts EVIO → ROOT via `evio2root` so the `analyze`
  step reads `out.root` the same way as any TTree-based file. If the
  user explicitly asks for `txt` output, warn that `analyze` can't
  auto-plot it.
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
  `hgc_study_<variant>/`), copy one of the hgc GCards into it,
  run through this skill. The `analyze` step gives
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
- Output:        <<project>/runs/<id>/out.root | other if user asked>
- Analysis:      <auto-plots | custom script in <project>/ | hgc_study upstream>

Steps
1. solid-gemc-run init    — workspace + .sif pull + clone + 2× scons (skip if already done)
2. seed <project>/ from templates/workspace/. (skip if already there)
3. copy <project>/<preset>.gcard from solid_gemc/script/<preset>.gcard (or .../analysis/.../<preset>.gcard); apply USE_GUI=0 + OUTPUT=evio,out.evio + N=<n>
4. <only if user wants non-default beam/physics:> edit <project>/<preset>.gcard
5. bin/solid-gemc-run exec "solid_gemc <abs gcard> -OUTPUT=evio,<abs run dir>/out.evio"  (from the gcard's upstream dir)
   then bin/solid-gemc-run exec "evio2root -INPUTF=out.evio -R=flux"   (from <project>/runs/<id>/; -R=flux requests the raw bank for the flux detector)
   write <project>/runs/<id>/{gcard.gcard, out.evio, out.root, log.txt, config.json}
6. solid-gemc-run analyze <project>/runs/<id>
     <one line: auto-plots | custom <project>/<id>.py | container-side ROOT macro>

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

- The five workspace-common files at cwd: `CLAUDE.md`, `.gitignore`,
  `log.md`, `result.md`, `report.html`.
- `solid_gemc/.git/` (the upstream tree is cloned).
- `solid_gemc/source/2.9/solid_gemc` (the binary exists and is
  executable).
- The `.sif` is cached (`bin/solid-gemc-run info` reports a path,
  not `[not pulled]`).

If **any** are missing, run `"$SGC_RUN" init` immediately and wait
for it to finish. Do not ask the user again — the plan they approved
listed init as step 1 with "skip if already done", so running it
when not-already-done is exactly what the approval covers. (On Claude
Code the `/solid-gemc-claude:init` slash command is the equivalent
shortcut; the wrapper call works on every platform.)

```bash
init_needed=0
for f in CLAUDE.md .gitignore log.md result.md report.html; do
  [[ -f "$f" ]] || { init_needed=1; break; }
done
[[ -d solid_gemc/.git ]]                  || init_needed=1
[[ -x solid_gemc/source/2.9/solid_gemc ]] || init_needed=1

if (( init_needed )); then
  echo "[skill] workspace not fully initialized; running init"
  "$SGC_RUN" init
fi
```

Note that `bin/solid-gemc-run clone` and `build` are themselves
idempotent — `clone` now prints the existing commit SHA and
warns-but-continues when `solid_gemc/.git` is already present;
`build` re-invokes scons which incrementally no-ops when nothing
has changed. So invoking init on a partially-initialized workspace
is safe.

Post-condition: all five workspace-common files exist; `.sif` is
cached; `solid_gemc/.git/` exists; `solid_gemc/source/2.9/solid_gemc`
is executable. If init returns non-zero, **stop** — report the
failure (last 20 lines of init's output) and do not proceed.

### 3b. Seed the project subdir if missing

```bash
PROJECT=<resolved from spec>

# Fail-closed safety guard — the enforceable line of defense for the
# Step 1 "Project name contract". Runs BEFORE the first filesystem
# write because $PROJECT also flows into mkdir/cp paths, RUN_DIR, and
# the unquoted config.json heredoc in step 3e. Never weaken or skip.
if ! printf '%s' "$PROJECT" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$'; then
  echo "[skill] refusing unsafe project name: '${PROJECT}'" >&2
  echo "[skill] must match ^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}\$ (no /, .., whitespace, quotes, shell metachars, leading -)" >&2
  exit 1
fi

if [[ ! -d "$PROJECT" ]]; then
  cp -r "${SGC_ROOT}/templates/workspace/." "$PROJECT/"
fi
```

If the guard trips, **stop** — do not write anything, return to
step 1, and get a contract-compliant name from the user. A tripped
guard means step 1's slugify/reject logic was skipped; that is the
bug, not the name.

Post-condition: `<project>/` exists with `CLAUDE.md`, `log.md`,
`result.md`, `report.html` (flat — no enforced subdirs). If it
pre-existed, leave it alone — never clobber a user's project files.

### 3c. Prepare the GCard

Resolve the preset against `solid_gemc/script/` first, then
`solid_gemc/analysis/*/`. Copy to `<project>/<preset>.gcard`.
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
DEST="${PROJECT}/$(basename "$SRC")"
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

"$SGC_RUN" validate-gcard "$DEST"
```

Post-condition: `<project>/<preset>.gcard` exists; the
live `<gcard>` block contains the three overrides; `validate-gcard`
returns 0.

### 3d. Run gemc + evio2root

Three important disciplines: (1) **cwd-relative geometry lookup** —
gemc 2.9 resolves `<detector name="…">` from the process cwd, not
from the GCard's path, so we `cd "$SOURCE_DIR"` (the dir holding
the canonical's geometry siblings) before invoking `solid_gemc`.
(2) **Absolute paths** for the GCard and OUTPUT, since cwd has
changed. Pipe-exit-code capture is portable across bash and zsh
via a tempfile (the harness shell may be either).
(3) **`evio2root -R=flux`** — without `-R=`, evio2root publishes only the
**digitized** bank for each detector, and the `flux` hitprocess's
digitized output is just `hitn` + `id` (a slim ~200 KB ROOT with no
Edep, no positions, no times — useless for analysis). Adding
`-R=flux` publishes the **raw** integrated bank for the flux
detector with all 27 fields (Edep, x/y/z, t, pid, …). If a study
uses non-flux hitprocesses that also need raw banks, append them
comma-separated: `-R=flux,Hits,…`.

```bash
RUN_ID=$(date -u +%Y%m%d-%H%M%S)-$(head -c 12 /dev/urandom | base32 | tr 'A-Z' 'a-z' | head -c 6)
RUN_DIR="${PROJECT}/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"
cp "$DEST" "$RUN_DIR/gcard.gcard"

WORKSPACE_ABS=$(readlink -f .)
RUN_DIR_ABS="${WORKSPACE_ABS}/${RUN_DIR}"
GCARD_ABS="${WORKSPACE_ABS}/${RUN_DIR}/gcard.gcard"

START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ); START_EPOCH=$(date +%s)

GEMC_EC_FILE=$(mktemp)
( cd "$SOURCE_DIR" && \
  SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
    "$SGC_RUN" exec \
      "solid_gemc '${GCARD_ABS}' -OUTPUT='evio,${RUN_DIR_ABS}/out.evio'"; \
  echo $? > "${GEMC_EC_FILE}" ) 2>&1 | tee "${RUN_DIR_ABS}/log.txt"
GEMC_EXIT=$(cat "${GEMC_EC_FILE}"); rm -f "${GEMC_EC_FILE}"

EVIO2ROOT_EXIT=0
if [[ "$GEMC_EXIT" = "0" && -f "${RUN_DIR_ABS}/out.evio" ]]; then
  EVIO_EC_FILE=$(mktemp)
  ( cd "$RUN_DIR_ABS" && \
    SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
      "$SGC_RUN" exec \
        "evio2root -INPUTF=out.evio -R=flux"; \
    echo $? > "${EVIO_EC_FILE}" ) 2>&1 | tee -a "${RUN_DIR_ABS}/log.txt"
  EVIO2ROOT_EXIT=$(cat "${EVIO_EC_FILE}"); rm -f "${EVIO_EC_FILE}"
fi
END_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ); END_EPOCH=$(date +%s)
EXIT_CODE=$([ "$GEMC_EXIT" = "0" ] && echo "$EVIO2ROOT_EXIT" || echo "$GEMC_EXIT")
```

Post-condition: `<project>/runs/<id>/{gcard.gcard,
out.evio, out.root, log.txt}` exist and are non-empty;
`EXIT_CODE` is 0.

### 3e. Write the provenance `config.json`

```bash
SIF_NAME=$(grep '^SIF_NAME=' "$SGC_RUN" | head -1 | cut -d'"' -f2)
SOLID_GEMC_SHA=$(cd solid_gemc && git rev-parse HEAD 2>/dev/null || echo unknown)
GEMC_VERSION_PINNED=$(grep '^GEMC_VERSION=' "$SGC_RUN" | head -1 | cut -d'"' -f2)
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
  "command":          "solid_gemc <gcard> -OUTPUT=evio,<run>/out.evio; evio2root -INPUTF=out.evio -R=flux",
  "cwd_gemc":         "${SOURCE_DIR}",
  "cwd_evio2root":    "${RUN_DIR}",
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(d, indent=2) + "\n")
PY
```

`<project>/runs/<id>/config.json` is the **provenance
record**. Treat the run dir as immutable from this point on.

### 3f. Analyze

Run `"$SGC_RUN" analyze <project>/runs/<id>` — host-side uproot,
auto-plots numeric branches into PNGs alongside `out.root`. (On
Claude Code the `/solid-gemc-claude:analyze` slash command is the
equivalent shortcut.) For asymmetries / fits / multi-run
comparisons, write a script under `<project>/`.

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
notable results — skip for trivial smokes), then refresh
`<project>/report.html` so the rendered summary (overview,
configuration table, headline figures, run-index row) stays in
sync with `result.md`. Use relative paths into `runs/<id>/` for
embedded plots; do not inline images as base64 — the run dir is
gitignored but it lives next to the report. Append a one-line
entry to the workspace-level `log.md` (the cross-project index)
pointing at `<project>/log.md` for detail, and add/update the
project's card + any cross-project headline plot in the
workspace-level `report.html`.

## Step 4 — Final report

End with a single block:

```
Done.
- Project: <project>
- Run id:  <id>
- Output:  <project>/runs/<id>/out.root
- Plots:   <project>/runs/<id>/<plot1>.png, …  (or "(histogram-only output; no auto-plots)")
- Updated: <project>/log.md, <project>/result.md, <project>/report.html, log.md, report.html

Next: <one concrete suggestion — vary the beam energy, scale up n_events,
       try a different canonical config, run a custom <project>/<id>.py>
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
