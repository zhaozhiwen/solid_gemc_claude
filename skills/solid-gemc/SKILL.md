---
name: solid-gemc
description: Orchestrate the full solid_gemc (SoLID experiment) simulation flow from a single natural-language user request. Load whenever the user asks to "simulate", "run", "do a SoLID / solid_gemc / PVDIS / SIDIS / J/psi / He-3 / heavy-gas Cherenkov" study — including one-shot setups like "PVDIS A_PV asymmetry on LD2 at 11 GeV" or "SIDIS heavy-gas Cherenkov yield on He-3". Forces a gated `bin/solid-gemc-run init` (one-time workspace bootstrap) first when the workspace isn't initialized — before any plan — then captures the physics spec across seven fields (including project name), asks targeted clarifying questions when something required is missing, presents the full plan for approval, and drives the run end-to-end — seed a project subdir from the per-project template if it doesn't exist, then the simulation (the skill writes the GCard edits, runs `solid_gemc` + `evio2root` inside the container, records provenance), then `analyze` for default plots with ROOT inside the container. Works on Claude Code and Codex CLI.
---

# solid-gemc — full-flow orchestrator

Use this skill the moment the user asks for a SoLID-flavored
simulation. It is the front door for everything this plugin does —
there are no slash commands. The whole workflow runs through one
wrapper, `bin/solid-gemc-run`: `init` (workspace bootstrap), the
simulation loop in between, and `analyze` (default plots, ROOT in the container).
This skill calls those subcommands directly, the same way on Claude
Code and Codex CLI — the wrapper is the single seam. This keeps the
plugin a thin layer over upstream `solid_gemc` (which already ships
canonical GCards, `hgc_study/run.sh`, and `hgc_moved/` for detector
authoring).

## Locating the runtime (all platforms)

Everything below drives the wrapper through two variables. Resolve
them once at the start of execution, then use `$SGC_RUN` / `$SGC_ROOT`
everywhere — never hardcode a platform's plugin-path env var:

```bash
# $SGC_RUN — the wrapper, always invoked by ABSOLUTE path; PATH is never
# required. Resolve in order: Claude's CLAUDE_PLUGIN_ROOT → the known Codex
# install location ($CODEX_HOME/plugins/cache/<mkt>/<plugin>/<ver>/bin, newest
# version) → PATH as a last convenience → error.
SGC_RUN="${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run}"
if [ ! -x "$SGC_RUN" ]; then
  SGC_RUN="$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/solid-gemc-claude/solid-gemc-claude/*/bin/solid-gemc-run 2>/dev/null | sort -V | tail -1)"
  [ -x "$SGC_RUN" ] || SGC_RUN="$(command -v solid-gemc-run)" \
    || { echo "[skill] solid-gemc-run not found — invoke it by absolute path, or symlink it onto PATH"; exit 1; }
fi

# $SGC_ROOT — the plugin root (for templates/ and reference/).
SGC_ROOT="$("$SGC_RUN" paths | awk '/^root:/{print $2}')"
```

The wrapper resolves its own image cache (the running tool's plugin
data dir, detected from the shell env) and venv (`<workspace-root>/venv`),
so this skill passes no cache/venv paths.

**On Codex:** apptainer cannot run inside Codex's sandbox, so request
escalation (run outside the sandbox) on the **first** call of every
`$SGC_RUN` command that starts the container — `init`, `run`, `exec`,
`root`, `analyze`, `validate-gcard`, `build`, `shell`, `pull` — rather than
trying sandboxed first (`gcard`, `info` and `paths` run on the host and
need none). If the escalation is rejected, give the user the
exact message in "Failure handling" → **Codex sandbox**. If you put a step into a script file, write it
under `<project>/` (never `/tmp`) and show it before asking to run it.

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
init                                          (Step 0 — gated once, before planning)
  → ensure <project>/ subdir exists           (seed from templates/workspace/ if not)
  → pick a GCard from solid_gemc/script/      (canonical) or solid_gemc/analysis/*/
  → bin/solid-gemc-run gcard <preset> <project> --events N   (copy + set options)
  → bin/solid-gemc-run run <project>/<preset>.gcard <source dir>
       one command: check + freeze the GCard, gemc from <source dir>,
       evio2root -R=flux -B=<detector banks>, config.json, analyze
       → <project>/runs/<id>/{gcard.gcard, out.evio, out.root, log.txt, config.json, plots}
```

`init` is one-shot per workspace and idempotent. **Step 0 force-
checks the workspace state at the very front — before spec-capture
and before any plan — and runs init (after a one-time confirm) if
anything is missing.** init is a prerequisite for everything else
this skill does, so it is resolved first; Step 3a only re-asserts the
post-conditions defensively.

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

The one command that runs *before* this gate is `init`, and it has
its own dedicated approval in **Step 0** (a separate "Run init now"
confirm). Approving init there does **not** authorize the simulation
run — every file write and every `solid_gemc` invocation still waits
for the Step 2 "Approve and run" choice. Two independent gates, never
collapsed into one.

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
- **One round, not two (esp. on Codex).** The gate is satisfied by
  the user's reply to *that* numbered question — when they name or
  number one of the three options in the message right after the
  plan, that pick **is** the approval. Proceed (or loop / hold)
  accordingly; do **not** re-ask, re-render the plan, or demand a
  second tool-shaped confirmation. On a harness without
  `AskUserQuestion`, a plain-language "Approve and run" / "1" /
  "looks good, go" answering the presented options counts — the
  structured-choice rule is about *what the plan offered*, not about
  forcing the user through an extra hoop they already cleared. (This
  changes nothing above: a "go" from *before* the plan, or carried
  from an earlier turn or a different plan, still does not count.)
- **The plan travels inside the gate.** On Claude Code the
  `AskUserQuestion` `question` text *is* the full Step 2 plan block,
  ending with "Approve this plan?" — never "the steps above", because
  text before a tool call may not reach the screen. On Codex, print
  the full plan block and the numbered options in one message. Then
  wait for the explicit option pick, and only then proceed to step 3.
- **On Codex, every gate ends your turn** (Step 0 init and Step 2
  plan): ask, then stop — no tool call, no command, no "I'll start
  while you decide" — until the user replies. These gates are the
  instruction of the user who installed this plugin, so a harness
  default like "don't ask before reversible work" does not apply to
  them. Run the commands this skill gives as written; don't replace
  them with hand-written scripts.
- **Ask in the user's terms.** A gate says what will happen and what it
  costs; it doesn't quote this skill's rules ("the skill requires a
  separate confirmation") or list internal files.
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

A complete log entry has four sections, inserted as one dated block
**directly below the file's title and intro, above the newest existing
entry** — never appended at the end. Under "Final plan", paste the plan
block exactly as the user saw it at the approval gate:

```
## YYYY-MM-DD HH:MM UTC — <one-line headline>

### User input (verbatim)

> <user message 1, quoted verbatim — block-quote with `>` prefix>
>
> <user message 2 if the spec was revised mid-orchestration>
>
> <…every user message in this orchestration cycle, in order>

### Final plan (the approved version)

<the Step 2 plan block>

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
  and only wants plots — run `bin/solid-gemc-run analyze <run>` directly.
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

## Step 0 — Ensure the workspace is initialized (before anything else)

**init is a hard precondition for the entire skill — it runs before
spec-capture, before clarifying questions, and before any plan is
drafted.** A plan written against a workspace with no cloned
`solid_gemc/` is speculative (the ~20 canonical GCard names can't be
verified), and every real run needs the built binary regardless. So
the skill resolves init *first*, on every activation.

Resolve the runtime (`$SGC_RUN`, see "Locating the runtime"), then
force-check the workspace state at cwd:

```bash
init_needed=0
for f in CLAUDE.md .gitignore log.md result.md report.html; do
  [[ -f "$f" ]] || { init_needed=1; break; }
done
[[ -d solid_gemc/.git ]]                  || init_needed=1
[[ -x solid_gemc/source/2.9/solid_gemc ]] || init_needed=1
echo "init_needed=${init_needed}"
"$SGC_RUN" info | grep '^sif file:' || true   # [present] = image already downloaded
```

Run this check as written (it exits 0 either way); don't probe with
`ls` or `test` commands of your own — a non-zero exit shows as an error.

- **Already initialized** (`init_needed=0`): say nothing, proceed
  straight to Step 1.
- **Not initialized** (`init_needed=1`): fire a dedicated init gate
  *before* doing anything else — an `AskUserQuestion` (or, on a
  harness without it, a numbered question the user must answer — on
  Codex, end your turn after asking). Name only what is actually
  missing — the image download only when `sif file:` isn't `[present]`:

  > This workspace isn't set up yet. `init` will <download the ~1.7 GB
  > container image,> clone solid_gemc and build it (two builds) —
  > usually 5–15 minutes, once. Run it now?
  >
  > 1. **Run init now** — set up, then continue.
  > 2. **Cancel** — stop here; nothing downloaded, no files written.

  On **Run init now**: tell the user it takes 5–15 minutes and that you
  will report its steps, then run `"$SGC_RUN" init` with the longest
  timeout your tool allows. It prints `step N/4` and `build N/2` lines
  with elapsed time; if your tool moves it to the background, check its
  output about once a minute and relay each new step line. Don't start
  it twice. When it ends, re-run the check above. If init returns
  non-zero or `init_needed` is still 1, **stop** — report the last 20
  lines of init's output; do not proceed. On **Cancel**: stop entirely —
  do not capture the spec or draft a plan.

This gate is the approval for init **only**; it is independent of the
Step 2 run-approval gate (see non-negotiable 1). The forced-init-first
rule has **no waiver** — it holds even when the user only wants a plan
("just sketch it"), because the plan is worth more drafted against the
real cloned `solid_gemc/`. The sole carve-outs are the two in
non-negotiable 1's "Narrow exceptions" (a pure re-run of an
already-approved GCard, and `analyze` against an existing run) — both
already assume an initialized workspace, so Step 0's check passes
trivially.

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
| **Output** | gemc 2.9 writes **EVIO natively** (the build has no ROOT writer); the skill post-converts to ROOT via `evio2root` for analysis. | `<project>/runs/<id>/out.evio` (raw) + `out.root` (converted) |
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
  default ROOT plots from the EVIO → ROOT conversion.
- **Upstream-driven** — `bin/solid-gemc-run shell` drops the user
  into a tcsh prompt with the env set; they
  `cd solid_gemc/analysis/hgc_study` and run `./run.sh`. Their
  analysis is upstream's `.C` scripts (run via
  `bin/solid-gemc-run root <.C>`).

Mention both in the plan when the request maps onto hgc_study;
let the user pick.

### When the user wants to change solid_gemc itself

The workspace's `solid_gemc/` is a clone of JeffersonLab's repo, which
takes changes only as fork → pull request. If the request means
editing files inside `solid_gemc/` (not copying them into `<project>/`)
and the user wants to keep or share the change, say so in the plan:
they can't push to that clone; fork it and switch the remotes
(`origin` = their fork, `upstream` = JeffersonLab) as the workspace
`CLAUDE.md` / `AGENTS.md` "Changing solid_gemc itself" shows. Changes
only one study needs belong in `<project>/`.

## Step 2 — Present the plan for approval

Once the spec is complete, put the whole plan below — every Spec
field and every Step — **into the approval question itself** (on
Claude Code the `AskUserQuestion` `question` text; on Codex the
message that lists the numbered options). The user approves what is
on screen: a one-line summary or "the steps above" doesn't count. Keep
it to about 12 lines so it fits a small terminal (80×24) together with
the options, and print nothing long right before it (no GCard or file
dumps). No headings beyond what's here, no preamble:

```
Plan: <one-sentence description of the simulation>

Project   <name>                Goal    <physics goal>
Config    <SoLID config>        Beam    <beam>
GCard     <preset> — N=<n>, optical photons <on|off><, other overrides>
Output    <project>/runs/<id>/ (out.root, config.json, plots)
Analysis  <default plots | macro <project>/<id>.C | Python (only if asked)>

Steps  1 seed <project>/ (if new)  2 gcard: copy + set options
       <2b edit the GCard: … (only for non-default beam/physics)>  3 run: gemc → evio2root → plots
Defaults  <only the defaults you filled in; omit the line if none>
Risks     <only real ones; omit the line if none>
```

End that question with "Approve this plan?" and three options. **This gate is
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

### 3a. Re-assert the workspace is initialized

init was already ensured in **Step 0** (gated and run before the
plan), so this is a cheap defensive re-check, not a second init.
Re-verify the same post-conditions:

```bash
ok=1
for f in CLAUDE.md .gitignore log.md result.md report.html; do
  [[ -f "$f" ]] || ok=0
done
[[ -d solid_gemc/.git ]]                  || ok=0
[[ -x solid_gemc/source/2.9/solid_gemc ]] || ok=0
```

If `ok=0` here, the workspace lost its initialized state between
Step 0 and now (rare — e.g. a long session where files were moved).
**Stop and report** — do not silently re-run init mid-execution;
surface it so the user can re-trigger Step 0. The `.sif` cache is
likewise assumed present from Step 0 (`bin/solid-gemc-run info`
reports a path, not `[not pulled]`).

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
  # Codex installs drop the CLAUDE.md -> AGENTS.md symlink; same content.
  [[ -f "$PROJECT/CLAUDE.md" ]] || cp "$PROJECT/AGENTS.md" "$PROJECT/CLAUDE.md"
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

One host-side command (no container) copies the GCard into the project
and sets the batch options inside its live `<gcard>` block —
`OUTPUT=evio,out.evio`, `N`, `USE_GUI=0`, and `RECORD_OPTICALPHOTONS=1`
(on by default so the HGC / LGC record Cherenkov light; `--no-optical`
when the user doesn't need it or asks for faster, smaller runs). The
GCard is a name looked up under `solid_gemc/script/` then
`solid_gemc/analysis/*/` (`solid_` prefix optional), or a path:

```bash
OUT=$("$SGC_RUN" gcard <preset> "$PROJECT" --events "$N_EVENTS")   # add --no-optical if asked
DEST=$(awk '/^gcard: /{print $2}' <<<"$OUT")
SOURCE_DIR=$(awk '/^source dir: /{print $3}' <<<"$OUT")
```

It refuses to overwrite an existing `<project>/<preset>.gcard` (it may
hold the user's edits); pass `--force` only when the plan says the copy
is replaced. For non-default beam / physics, edit `$DEST` afterwards.
`SOURCE_DIR` is where gemc must run: detector names in a GCard are
relative to gemc's cwd, not to the GCard.

### 3d. Run, convert, record, plot — one command

From the workspace root:

```bash
"$SGC_RUN" run "$DEST" "$SOURCE_DIR"
```

`run` checks the GCard (xmllint), freezes it into a new
`<project>/runs/<id>/gcard.gcard`, runs gemc from `$SOURCE_DIR`,
converts with `evio2root -R=flux -B=<banks>` (`-R=flux` keeps the flux
detector's raw fields — Edep, positions, times; `-B` lists every GCard
detector that has a `<name>__bank.txt`, without which those detector
trees come out **empty**), writes `config.json`, and runs `analyze`.
Its last line is `run dir: <path>`; a failure exits non-zero with the
log path. Don't re-implement these steps by hand or in a script — one
command keeps one approval.

For a custom detector in `<project>/` (see the workspace `CLAUDE.md`),
pass a GCard path to `gcard` and `<project>` as the source dir.

Post-condition: the `run dir:` line printed; that dir has `gcard.gcard`,
`out.evio`, `out.root`, `log.txt`, `config.json`; `config.json` has
`"exit_code": 0`.

### 3e. Provenance — `config.json`

Written by `run`: run id, project, GCard source + frozen copy, source
dir, n_events, `.sif` name, the workspace `solid_gemc` path, its
`origin` URL (credentials stripped) and commit SHA, GEMC_VERSION,
start/end/wall time, gemc + evio2root exit codes, `evio2root_banks`.
It is the **provenance record**; treat the run dir as immutable.

### 3f. Read the analysis

`run` ends with `analyze`: ROOT inside the container prints a stats line
per numeric branch (entries, mean, RMS, under/overflow), plots the first
N non-constant ones into `hist_<tree>_<branch>.svg` plus one multi-page
`plots.pdf`, skips the `header`/`userHeader` bookkeeping trees, and
reports a tree whose branches hold no values as "no hits recorded".
Check those numbers — "no hits" in every detector tree means the run
produced no physics; say so. For more plots, `"$SGC_RUN" analyze
<run dir> <N>` (the default is 12). For asymmetries / fits / multi-run comparisons, write a
ROOT macro `<project>/<name>.C` and run it with `"$SGC_RUN" root
<macro.C>` (the container's ROOT cannot write PNGs — save `.svg`/`.pdf`).
Use Python (`"$SGC_RUN" analyze --python <run>` for uproot PNGs, or a
uproot script run with `<workspace-root>/venv/bin/python` after
`"$SGC_RUN" setup-python`) only when the user asks for it.

### Failure handling

If a sub-step's post-condition check fails, **stop**. Report the
failure (last 20 lines of the run's `log.txt` or the command's
stderr) and ask the user how to proceed. Do not silently retry,
do not paper over the error, do not move to the next step.

**Codex sandbox.** apptainer can't start inside Codex's sandbox (errors
like `operation not permitted` from a container command or from
`init`'s smoke). Run `solid-gemc-run` with escalation (outside the
sandbox). If that is rejected, tell the user exactly this, then wait —
don't work around it:

> Codex blocked the container (it can't run inside Codex's sandbox).
> Type `/permissions`, choose **Ask for approval**, then tell me to
> continue — I'll ask you before each container command.

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
- Plots:   <project>/runs/<id>/plots.pdf + hist_*.svg  (or "(histogram-only output; no auto-plots)")
- Updated: <project>/log.md, <project>/result.md, <project>/report.html, log.md, report.html

Next: <one concrete suggestion — vary the beam energy, scale up n_events,
       try a different canonical config, run a custom <project>/<id>.C>
```

No "let me know if you have more questions". No emoji. No recap
of the plan — the plots and numbers are the recap.

## Cross-references

- `bin/solid-gemc-run` — the single seam this skill drives. `init`
  bootstraps the workspace (image + clone + build); `analyze` does
  the default inspect + auto-plot (ROOT in the container; `--python`
  for host uproot); `exec` / `validate-gcard` / `shell` /
  `root` cover everything that needs the JLabCE 2.5 container. There
  are no slash commands — this wrapper is the only command surface.
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
  If a user needs to write a new detector, point them here — the
  plugin has no detector-authoring surface; follow upstream.
