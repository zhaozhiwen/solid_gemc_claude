---
name: solid-gemc
description: Run SoLID detector simulations with solid_gemc (GEMC) from a plain-language request — PVDIS, SIDIS, J/psi, He-3, DDVCS, LD2/LH2/NH3 targets, heavy-gas or light-gas Cherenkov, GEM, EC, MRPC or baffle studies, "set up / initialize a solid_gemc workspace", or "where do I start" in one, e.g. "PVDIS A_PV on LD2 at 11 GeV" or "HGC photoelectron yield on He-3". Ensures the workspace is initialized (a gated `bin/solid-gemc-run init`) before any plan, captures a seven-field spec, gets explicit approval for the plan, then drives `bin/solid-gemc-run` (gcard, run, analyze). Not for plain Geant4/GDML work without SoLID context. Claude Code and Codex CLI.
---

# solid-gemc — full-flow orchestrator

The front door for everything this plugin does (there are no slash commands).
Every step runs through one wrapper, `bin/solid-gemc-run`, the same way on Claude
Code and Codex CLI. The plugin stays a thin layer over upstream `solid_gemc`,
which ships the canonical GCards, `analysis/hgc_study/` and `geometry/hgc_moved/`.

## Locating the runtime

Your **first command** in a session is this block followed by Step 0's check, in
one call. Run no `pwd`, `ls` or other probe before it — a failed probe shows the
user an error before anything has happened.

```bash
# Claude fills in ${CLAUDE_PLUGIN_ROOT} below (exact install); elsewhere it is empty,
# so: the newest Codex install → PATH → error.
SGC_RUN="${CLAUDE_PLUGIN_ROOT}/bin/solid-gemc-run"
if [ ! -x "$SGC_RUN" ]; then
  SGC_RUN="$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/solid-gemc-claude/solid-gemc-claude/*/bin/solid-gemc-run 2>/dev/null | sort -V | tail -1)"
  [ -x "$SGC_RUN" ] || SGC_RUN="$(command -v solid-gemc-run)" \
    || { echo "[skill] solid-gemc-run not found — invoke it by absolute path, or symlink it onto PATH"; exit 1; }
fi
SGC_ROOT="$("$SGC_RUN" paths | sed -n 's/^root: *//p')"
echo "SGC_RUN=$SGC_RUN"; echo "SGC_ROOT=$SGC_ROOT"
```

**Shell variables don't survive between tool calls.** Write the two printed
absolute paths into every later command; `$SGC_RUN` / `$SGC_ROOT` below stand for
them. The same goes for any value one step prints and a later step uses. Never
hardcode a platform's plugin-path env var. This file avoids shell positional
parameters (a dollar sign followed by a digit) on purpose: Claude Code replaces them
with words of the user's request. Don't add any to the commands you take from it. The wrapper finds its own image cache
and venv; pass no cache or venv paths.

**On Codex:** apptainer cannot run inside Codex's sandbox, so request escalation
on the **first** call of every container command — `init`, `run`, `exec`,
`root`, `analyze`, `validate-gcard`, `build`, `shell`, `pull` — rather than
trying sandboxed first (`gcard`, `info`, `paths` run on the host). If escalation
is rejected, see "Failure handling". If you put a step into a script file, write
it under `<project>/` (never `/tmp`) and show it before asking to run it.

## The flow

```
Step 0  init (gated once per workspace, before any plan)
Step 1  capture the seven-field spec; ask what can't be defaulted
Step 2  plan → approval gate
Step 3  seed <project>/ → bin/solid-gemc-run gcard → bin/solid-gemc-run run
          (gemc, evio2root, config.json, plots in <project>/runs/<id>/) → handoff docs
Step 4  final report
At every step: consult the reference library (next section) — not just on failure.
```

The workspace root (where `init` ran, once and idempotently) holds init's files —
`AGENTS.md`/`CLAUDE.md`, `README.md`, `.gitignore`, `log.md`, `result.md`,
`report.html`, `bin/solid-gemc-run` — and the built `solid_gemc/`. Each study is a
flat project subdir (no enforced subfolders) with its own rules and handoff
documents. There is no bring-your-own binary: if the canonical configs don't fit,
the divergence point is **the GCard** — edit the closest canonical one, or
hand-author one.

## Reference library — use it at every stage

`$SGC_ROOT/reference/` holds what you need to get SoLID physics and gemc behavior
right: source digests of gemc (`gemc.md`) and the SoLID layer (`solid_gemc.md`),
the SoLID gemc guide (`gemc_simulation_general_note.md`, mirror of the wiki), and
the PDG passage-of-particles review (`passage-particles-matter-summary.md`, full
`.md`, `.txt` for exact numbers). **Whenever a plan, an edit, a number or an answer
depends on how gemc, a SoLID detector or the physics works, look it up here instead
of answering from memory.** Start at `reference/README.md` (the index), grep the
file for the term, read only that section (files run to ~1,200 lines — never read
one whole), and name the file + section in what you tell the user.

| Stage | Typical questions | Look in |
|---|---|---|
| Planning (Step 1) | Which detectors a config simulates in full vs as a stub? What will the output contain? | `solid_gemc.md` hit-processor table; `gemc_simulation_general_note.md` |
| GCard edits (3c) | What does `BEAM_P`, `SPREAD_P`, `PHYSICS`, `PRODUCTIONCUT`… do; override syntax | `gemc_simulation_general_note.md` option reference; `gemc.md` §4–5 |
| Custom detector | Geometry, material, hit, bank file formats | `gemc_simulation_general_note.md`; `gemc.md` §6 |
| Results and physics questions (3e, follow-ups) | What a branch means; expected yields, Cherenkov threshold, dE/dx, photoelectrons | `solid_gemc.md` (processor, constants); PDG summary, then full `.md`/`.txt` |
| Failures | Geometry not found; empty tree; build fails; option ignored | `gemc.md` §16 item 1 + §6, §8, §3, §4–5; `solid_gemc.md` stub table |

## Non-negotiable 1 — explicit approval before anything is created or run

**No file is created and no container command (`run`, `exec`, `root`, `build`,
…) runs until the user picks "Approve and run" at the Step 2 gate in this turn.**
Only `init` comes earlier — behind its own "Run init now" pick, or requested
outright by the user (a setup-only request, Step 0); reads on the host
(the Step 0 check, `info`, listing GCards) need no gate. Not when the user says
"go", "yes", "just run it", "skip the approval" or "no clarifying questions", and
not when the request looks fully specified. Your reading of "PVDIS LD2 11 GeV 10000 events" is
one of many — the wrong canonical GCard (`solid_PVDIS_LD2_moved_full` vs
`solid_PVDIS_simple`), analysis, project name or default; showing the plan first
catches that before any artifact exists.

There are **two independent approvals**: init (Step 0 — the "Run init now" pick,
or the user's own setup-only request) and the run (Step 2's "Approve and run").
Approving init never approves a run. Never collapse them.

| Question | Covers | Can the user waive it? |
|---|---|---|
| Clarifying (Step 1) | Ambiguous spec fields | **Yes** — "fill in defaults" / "no questions": fill defaults instead of asking, and list every one on the plan's `Notes` line |
| Approval gate (Step 2) | Running *this* plan, *this* turn | **Never** — still gate; picking "Approve and run" costs one click |

**How a gate works:**
- It is a structured choice, not prose ending in "let me know". On Claude Code,
  an `AskUserQuestion` whose `question` text holds everything the user decides on
  — the whole plan block at Step 2, the init text at Step 0 (text before a tool
  call may not reach the screen — never "the steps above"). On Codex, or any
  harness without `AskUserQuestion`, one message with that text and the numbered
  options.
- **On Codex every gate ends your turn** (Step 0 and Step 2): ask, then stop — no
  tool call, no "I'll start while you decide". These gates are the instruction of
  the user who installed the plugin; a harness default like "don't ask before
  reversible work" does not override them.
- **One round.** On Codex (or any harness without `AskUserQuestion`), the reply
  naming or numbering an option ("1", "Approve and run", "looks good, go") *is* the
  pick — proceed; don't re-ask or re-render the plan.
- The gate message is the question text and the options, **nothing else** — no
  preamble, no closing paragraph, no mention of this skill, its rules or its file
  path. On an 80×24 screen anything extra pushes the plan out of view, and the user
  would approve a plan they can't see. Say what will happen and what it costs.
- Run the commands this skill gives as written; don't replace them with
  hand-written scripts.

**Not approval** — if you catch yourself thinking any of these, fire the gate:
- "They said no clarifying questions, so I'll just run it." (Clarifying ≠ approval.)
- "The plan is on screen as text." (Text is not a structured choice.)
- "They said 'go' in their first message." (Before the plan doesn't count.)
- "Same plan as last turn; they obviously approve." (Every plan, every turn.)
- "Faster to do it and ask forgiveness." (A wrong run costs more than the click.)

**Narrow exceptions** — no new simulation artifacts, so no Step 2 gate:
(a) a pure re-run of an existing `<project>/<preset>.gcard` the user explicitly
names (approved in an earlier gated orchestration) — call `run` only, with the
`source_dir` from that GCard's previous `runs/<id>/config.json`; (b) `analyze` on an existing
`runs/<id>/`; (c) debugging a failed run by reading its `log.txt` and
`config.json`. Nothing else qualifies — not annoyance, not an "obvious" plan.

## Non-negotiable 2 — log every request

Every orchestration — run, plan-only or failure — ends with an entry in
`<project>/log.md`, inserted **directly below the file's intro, above the newest
entry**, never at the end. (Plan-only for a project that doesn't exist yet: run
3b's guard + seed first.) Use the four-section format in the comment of
`$SGC_ROOT/templates/workspace/log.md` (seeded into each project):
- **User input (verbatim)** — every user message of this cycle, block-quoted, in
  order; never paraphrased.
- **Final plan** — the plan block exactly as shown at the approval gate.
- **Decision** — the option picked and any spec edits.
- **Outcome** — run id and status; for a crash, `stopped at step <N>` with a
  pointer to `runs/<id>/log.txt`.

Write it at the very end (after `analyze`, or after the failure that stopped the
flow). Exceptions (a) and (b) log a short entry instead: the request verbatim, the
run id, the outcome. Debugging (c) and a Step 0 **Cancel** write nothing. Also add
one line **at the top** of the workspace `log.md`, below its intro:
`- YYYY-MM-DD — <project>: <one-line milestone> ([log](<project>/log.md))`.

## Step 0 — Ensure the workspace is initialized (before anything else)

init comes before spec capture and before any plan — even for "just sketch a
plan": a plan needs the real cloned `solid_gemc/` (to verify GCard names) and every
run needs the built binary. From the workspace root, run this check as written —
in the same call as the locate block, or with the absolute path in place of
`$SGC_RUN` (it exits 0 either way; don't probe with your own `ls`/`test`, whose
non-zero exit shows as an error):

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

- `init_needed=0`: say nothing; go to Step 1. If the request was only to set up
  the workspace, say it is already set up and suggest a first study instead.
- `init_needed=1` on a **setup-only request** (see below): the request is the
  approval — don't ask again. Say in one line what init will do and how long it
  takes, then run it as below.
- `init_needed=1` on any other request: fire the init gate before anything else.
  Name only what is missing — the image download only when `sif file:` isn't
  `[present]`:

  > This workspace isn't set up yet. `init` will <download the ~1.7 GB
  > container image,> clone solid_gemc and build it (two builds) —
  > usually 5–15 minutes, once. Run it now?
  >
  > 1. **Run init now** — set up, then continue.
  > 2. **Cancel** — stop here; nothing downloaded, no files written.

  On **Run init now**: say it takes 5–15 minutes and that you'll report its steps,
  then run `"$SGC_RUN" init` with the longest timeout your tool allows, its output
  unfiltered (no `| tail`, `| head`, so the step lines appear as they come). It prints
  `step N/4` and `build N/2` lines with elapsed time; if your tool backgrounds it,
  check about once a minute and relay each new step line. Don't start it twice.
  When it ends, re-run the check. Non-zero exit or still `init_needed=1` → **stop**
  and report init's last 20 lines. On **Cancel**: stop entirely — no spec, no plan.

**Setup-only request** ("initialize the workspace", "set up solid-gemc" — the
step the docs tell users to do right after installing): the user asked for init, so
it runs without the gate; after a successful init, stop. Say the workspace is ready (and how long init took), suggest a first study
— e.g. "Run the heavy-gas Cherenkov study on He-3, 100 events" — and add one line
at the top of the workspace `log.md`: `- YYYY-MM-DD — workspace initialized`. No
spec, no plan.

This has no waiver. Exceptions (a)–(c) already assume an initialized workspace.

## Step 1 — Capture and gap-check the spec

For each field: did the user give it, is a default safe, or must you ask?

| Field | What it is | Example |
|---|---|---|
| **Project name** | The `<name>/` subdir for this study | `pvdis_ld2_aPV`, `sidis_he3_hgc` |
| **Physics goal** | What's measured / counted | "PVDIS A_PV vs Q²", "HGC photoelectron yield vs Cherenkov radius" |
| **SoLID config** | Magnet + spectrometer configuration | "PVDIS, LD2 target, full magnet config", "J/psi LH2 simple" |
| **Beam** | Particle, energy, event count | "11 GeV e-, 10000 events" |
| **GCard** | Preset from `solid_gemc/script/` or `solid_gemc/analysis/*/` + overrides | `solid_PVDIS_LD2_moved_full`, `N=10000` |
| **Output** | Fixed by `run` (EVIO, converted to ROOT) | `<project>/runs/<id>/out.evio` + `out.root` |
| **Analysis** | Plots / numbers to produce | "default plots", "asymmetry binned in Q²" |

Check the reference library (Planning row) before filling a field you aren't sure
about — e.g. whether the detector the goal needs is simulated in full.

**Ask, never guess:** the physics goal; the SoLID config (~20 canonical GCards in
`solid_gemc/script/` — PVDIS/SIDIS/J/psi and LD2/LH2/³He/NH3 are different physics;
list the presets and ask); the beam energy when the user implies a non-standard
one (most configs assume 11 GeV). One focused question per missing field
(`AskUserQuestion` for choices, plain prose for a one-line answer), saying why a
default isn't safe. Don't chain guesses together.

**Project name contract (safety boundary, never waivable).** The name becomes a
directory and a path argument to every later command, so it **must** match
`^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$`. A derived default is slugified to fit (runs
of disallowed characters → `_`, strip a leading non-`[A-Za-z0-9_]`, trim to 64;
empty → `solid_run`). A user-typed name that doesn't fit: **reject and ask**,
quoting the rule — never rewrite it silently, and "no questions" doesn't cover it.
Step 3b enforces this with a guard.

**Safe defaults** (state them in the plan):
- Project name from config + goal ("PVDIS A_PV on LD2" → `pvdis_ld2_aPV`); an
  existing `<project>/` of that name is reused unless the user wants a fresh one.
- GCard preset from the locked SoLID config (PVDIS + LD2 + full →
  `solid_PVDIS_LD2_moved_full`).
- 100 events for a first run; suggest a production number for the follow-up.
- If `<project>/<preset>.gcard` already exists, the plan says which: reuse it
  (set `N` in it by hand, skip `gcard`) or replace it (`gcard --force`, which
  discards edits to it).
- Physics list, hall material, geometry detail: never touch.

**Upstream `hgc_study`.** For the heavy-gas Cherenkov study (or anything that
points at `solid_gemc/analysis/hgc_study/`), offer both in the plan: skill-driven
(copy one of its GCards into a project and run it here) or upstream-driven
(`bin/solid-gemc-run shell`, `cd solid_gemc/analysis/hgc_study`, `./run.sh`; its
`.C` analysis via `bin/solid-gemc-run root`). Let the user pick.

**HGC and MRPC record truth hits only.** Their hit processors (`solid_hgc`,
`solid_mrpc`) compute no photon yield, quantum efficiency or timing. When the
analysis needs photoelectrons or timing from them, say so on the plan's Notes line:
photoelectrons are counted from the optical-photon hits (pid −22) in the detector's
tree with a QE applied, in a macro — the way upstream
`solid_gemc/analysis/hgc_study/analysis.C` does (`solid_gemc.md`, stub footgun).

**Changes to `solid_gemc/` itself.** Its `origin` is JeffersonLab (fork + PR
only). If the user wants to keep or share edits inside it, say so in the plan:
fork and switch the remotes as the workspace `AGENTS.md` rule 8
shows. Changes one study needs belong in `<project>/`.

## Step 2 — Present the plan for approval

Put the whole plan into the approval question itself (Non-negotiable 1). It is
**at most the 6 lines below, each under 80 characters** — on an 80×24 terminal the
approval menu (and on Codex its full-screen view, which has no scrollback) leaves
room for little more. No blank lines, no extra headings or preamble, nothing long
printed right before it (no GCard or file dumps), one line per option:

```
Plan: <one-sentence description of the simulation>
Project <name> · Config <SoLID config> · Beam <beam>
Goal <physics goal> · Analysis <default plots | <name>.C macro | Python>
GCard <preset>, N=<n>, optical photons <on|off><, other overrides>
Steps seed <project>/ (if new) → gcard<, edit: …> → run → <project>/runs/<id>/
Notes <defaults you filled in; real risks — omit the line if none>
```

End with "Approve this plan?" and three options:

1. **Approve and run** — proceed with this plan.
2. **Edit the spec** — change something; back to Step 1.
3. **Just write the plan, don't run yet** — leave it in the chat (and log it).

## Step 3 — Execute, in order

Only after "Approve and run". Each sub-step has a post-condition; if it fails,
stop and report (see "Failure handling").

**3a.** Re-run Step 0's check. If `init_needed=1`, stop and report — never re-run
init mid-execution.

**3b. Seed the project subdir if missing.**

```bash
PROJECT='<resolved from spec>'   # single-quoted
# Fail-closed guard for the project name contract. Never weaken or skip.
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

If the guard trips, stop, write nothing, return to Step 1 for a compliant name,
and re-present the plan at the Step 2 gate (Step 1's slugify/reject was skipped —
that is the bug). Post-condition: `<project>/` has
`CLAUDE.md`, `log.md`, `result.md`, `report.html`. An existing project is left
alone — never clobber the user's files.

**3c. Prepare the GCard** (host only):

```bash
"$SGC_RUN" gcard <preset> <project> --events <n>   # add --no-optical if asked
```

It copies the GCard — a path, or a name looked up under `solid_gemc/script/`
(`solid_` prefix optional there) and `solid_gemc/analysis/*/`; if it reports
several matches, pass a path — to `<project>/<its file name>` and sets `OUTPUT=evio,out.evio`, `N`, `USE_GUI=0` and
`RECORD_OPTICALPHOTONS=1` in its live `<gcard>` block (optical photons on so the
HGC/LGC record Cherenkov light; `--no-optical` when not needed or for faster,
smaller runs). It prints `gcard: <path>` and `source dir: <dir>` — use those
values in 3d. It won't overwrite an existing copy (it may hold the user's edits);
pass `--force` only when the plan says so. For non-default beam or physics, edit
the copy now — look each option up first (reference library, GCard-edits row).
The source dir is where gemc must run: detector names in a GCard are
relative to gemc's run folder.

**3d. Run, convert, record, plot — one command**, from the workspace root:

```bash
"$SGC_RUN" run <gcard path> <source dir>
```

`run` checks the GCard (xmllint), freezes it into `<project>/runs/<id>/gcard.gcard`,
runs gemc from the source dir, converts with `evio2root -R=flux -B=<banks>`
(`-R=flux` keeps the flux detector's raw fields; `-B` lists every GCard detector
with a `<name>__bank.txt` — without it those trees come out **empty**), writes
`config.json` (the provenance record: GCard, image, solid_gemc origin + commit,
gemc version, events, times, exit codes, banks) and runs `analyze`. Don't
re-implement any of this by hand — one command keeps one approval. For a GCard
that already lives in `<project>/` (custom detectors), skip `gcard` — it would copy
the file onto itself: set `N` and `USE_GUI=0` (and `RECORD_OPTICALPHOTONS` if
wanted) in its live `<gcard>` block by hand, then
`"$SGC_RUN" run <project>/<file>.gcard <project>`. Post-condition: a last line `run dir: <path>`, and that dir has
`gcard.gcard`, `out.evio`, `out.root`, `log.txt`, `config.json` with
`"exit_code": 0`. If `solid_gemc/` or the workspace is reached through a symlink,
`log.txt` (evio2root's own lines) shows the resolved physical paths while
`config.json` records the workspace paths — the same files, not a problem; don't
report it as one. On failure `run` exits non-zero and names the log and run dir; no
`run dir:` line with `"exit_code": 0` means `analyze` failed. Treat the run dir as
immutable.

**3e. Read the analysis.** Interpret numbers, and answer the user's physics
questions about the run (yields, thresholds, photoelectrons, what a branch means),
from the reference library (Results row) and cite it. `analyze` prints a stats
line per numeric branch
(entries, mean, RMS, under/overflow), plots the first N non-constant ones into
`hist_<tree>_<branch>.svg` plus `plots.pdf`, skips the `header`/`userHeader`
trees, and reports an empty tree as "no hits recorded". Explain empty trees to the
user: the GCard's detector trees are the banks named (first column) in the
`<name>__bank.txt` files that `config.json` lists under `evio2root_banks`;
`evio2root` also writes `flux`, `counter`, `mirror`, `rf`, `allraws`, `chargeTime`
and `ancestors` on every run, and these stay empty unless the GCard has a detector
of that type — say so plainly. Only an empty tree of a GCard detector is a finding:
too few events for that acceptance, or a geometry problem. If every GCard detector
tree is empty, the run produced no physics — say so. More
plots: `"$SGC_RUN" analyze <run dir> <N>` (default 12). Asymmetries, fits,
multi-run comparisons: a ROOT macro `<project>/<name>.C` run with
`"$SGC_RUN" root <macro.C>` (save `.svg`/`.pdf`; the container's ROOT can't write
PNG). Python only when the user asks: `"$SGC_RUN" analyze --python <run>`, or a
uproot script with `<workspace-root>/venv/bin/python` after
`"$SGC_RUN" setup-python`.

**3f. Handoff documents.** Write the log entries (Non-negotiable 2). Only for a
run with a notable result — skip trivial smokes — also update
`<project>/result.md` (key numbers + plot paths), refresh `<project>/report.html`
from it (overview, configuration table, headline figures, run-index row; plots by
relative path into `runs/<id>/`, never base64), and add or update the project's
card (and any cross-project headline plot) in the workspace `report.html`.

### Failure handling

When a post-condition fails, **stop**: report the last 20 lines of the run's
`log.txt` (or the command's stderr) and ask how to proceed. Don't retry silently,
paper over the error, or move on.

Diagnose with the reference library (Failures row) before proposing a fix, and
cite what you found.

**Codex sandbox.** If a container command (or `init`'s smoke test) fails with
`operation not permitted`, run it with escalation. If that is rejected, tell the
user exactly this, then wait — don't work around it:

> Codex blocked the container (it can't run inside Codex's sandbox).
> Type `/permissions`, choose **Ask for approval**, then tell me to
> continue — I'll ask you before each container command.

## Step 4 — Final report

End with a single block — no recap of the plan, no "let me know", no emoji. Write
paths as plain text, not as markdown links (some terminals show only a link's
label):

```
Done.
- Project: <project>
- Run id:  <id>
- Output:  <project>/runs/<id>/out.root
- Plots:   <project>/runs/<id>/plots.pdf + hist_*.svg
- Updated: <only the files actually touched, e.g. <project>/log.md, log.md>

Next: <one concrete suggestion — vary the beam energy, scale up n_events,
       try a different canonical config, run a custom <project>/<name>.C>
```

## References

- The reference library is above ("Reference library — use it at every stage").
- GCard options (`BEAM_P`, `PHYSICS`, `OUTPUT`, `N`, …): `https://gemc.jlab.org`,
  mirrored in `$SGC_ROOT/reference/gemc_simulation_general_note.md`.
- Worked examples in the workspace: `solid_gemc/analysis/hgc_study/` (config + run
  + analyze) and `solid_gemc/geometry/hgc_moved/` (custom detector authoring —
  the plugin has no authoring surface of its own; follow upstream's `readme.md`).
