# Tests

Three automated tests, plus the CI lints. All three install the plugin into a
**clean Claude Code and Codex** inside a throwaway sandbox — a fake `HOME` and a
whitelisted environment (`env -i`) — so they test what a user actually gets
(the real install dirs, per-tool data dirs, workspace launcher, skill loading), and
the running Claude Code / Codex sessions and your real `~/.claude`, `~/.codex` are
never touched. Each test ends by hashing your real plugin state and comparing it with
the start. The basic and full tests share one script (`full-test.sh`), its
`setup` / `verify` / `cleanup` steps, and the agent prompt.

| | Quick test | Basic test | Full test |
|---|---|---|---|
| Run it | on every change | when `skills/` or the orchestrator flow changes | before a release |
| Command | `tests/quick-test.sh` | `tests/basic-test.sh setup` → subagents → `verify` → `cleanup` | `tests/full-test.sh setup` → subagents → `verify` → `cleanup` |
| Plugin source | a copy of the working tree | a copy of the working tree | the published GitHub marketplace (`SGC_SOURCE=local`: a fresh clone of HEAD) |
| Image | symlinked into each fake data dir | symlinked | really downloaded by the plugin |
| solid_gemc | workspaces link `templates/solid_gemc` | linked | `init` really clones and builds |
| Tiers | 0 + A | B only | 0 + A + B |
| Agents | none | one real session per tool, a subagent playing the user; both in parallel | same |
| Time | ~1 min | ~10–15 min | ~45–60 min |
| Cost | no model calls; PyPI only on the first run (then the test uv cache) | model calls (2 sessions + 2 subagents) | model calls; ~3.4 GB download; 4 scons builds |

## Quick test

**What it checks**
- **Tier 0 — wrapper unit checks** (container-free, on the working tree):
  - the image cache follows the detected tool (Claude Code / Codex, custom and
    default homes); no tool or both → an existing `.sif` is used read-only and
    nothing is downloaded;
  - the workspace launcher picks the newest installed version, prefers the detected
    tool, falls back to the wrapper that ran `init`, else errors;
  - `init` writes the launcher in a workspace and never overwrites the wrapper when
    run inside a plugin checkout;
  - the venv anchors at the workspace root from any subfolder.
- **Setup**: real `claude plugin` / `codex plugin` installs into the sandbox.
- `init` runs with `SOLID_GEMC_SKIP_BUILD=1`: no scons on the linked prebuilt tree (the
  test is for the plugin, not solid_gemc); `init` still requires the binary and runs its
  in-container `which solid_gemc` check.
- **Tier A — installed plugin, no model** (once per tool): the installed wrapper's
  `init` writes the workspace files, marker and launcher and no `cache/` →
  `info` through the launcher reports that tool's install and data dir (a plain
  terminal is read-only) → the workspace and solid_gemc tree are bind-mounted from a
  deep folder → a 2-event `cherenkov.gcard` run (gemc + `evio2root -R=flux`) →
  `analyze` writes plots and the venv sits at the workspace root.
- **Leak scan**: no `/home/$USER` in shipped files.

**How to run**
```bash
# once: a built solid_gemc clone for the test (gitignored, ~1 GB)
bin/solid-gemc-run clone templates/solid_gemc && bin/solid-gemc-run build templates/solid_gemc

tests/quick-test.sh                 # needs claude, codex, apptainer, git, wget, python3
SGC_SIF=/abs/path/<sif> tests/quick-test.sh   # if no .sif is in your plugin data dir
SGC_KEEP=1 tests/quick-test.sh      # keep the sandbox for inspection
```
The venvs install from a persistent, test-only uv cache (`.test-cache/uv`, gitignored,
~200 MB; never your real `~/.cache/uv`), so only the first run downloads from PyPI. The
full test doesn't use it.

Pass: `ALL GREEN — N pass, 1 known-fail`. A failure keeps the sandbox
(`/tmp/sgc-quick.*`, path printed); its `logs/` has every install and init log.

## Basic test

The full test's real agent sessions, with the quick test's shortcuts: the plugin from
the working tree, the `.sif` and `templates/solid_gemc` linked, no tiers 0/A (run the
quick test for those). It checks the part only an agent session reaches — the skill
picking up the request, the init and plan gates, and how the agent drives the run —
in ~10–15 min instead of an hour.

```bash
tests/basic-test.sh setup                # prints SANDBOX=<dir>
#   → two subagents in parallel: <dir>/agent-claude.md and <dir>/agent-codex.md
tests/basic-test.sh verify <dir>         # → <dir>/logs/summary.md, RESULT: PASS|FAIL
tests/basic-test.sh cleanup <dir>
```
`verify` checks the same things as the full test, except that the `.sif` and
`solid_gemc` are expected to be the links. The sessions run with
`SOLID_GEMC_SKIP_BUILD=1` (a wrapper test hook): `init` skips scons on the prebuilt
linked tree — the test is for the plugin, not solid_gemc — so the two sessions write
nothing in common and run in parallel. The full test never sets it.

## Full test

A real user's first session in each tool, with none of the quick test's shortcuts:
published install, real download and build, Claude Code's default permission mode,
Codex's default sandbox and approvals, nothing pre-trusted. A fresh subagent per tool
plays a new user (`tests/full-test-agent.md`): it types one plain-language request,
answers every prompt as a sensible user would — approving init, approving the plan only
if it matches the request, approving Codex escalations only for this study's commands
inside the sandbox — and writes a verdict listing every prompt it saw.

**What it checks**
- tier 0 on the **installed** plugin; tier A with a real `init` (download into the
  fake data dir + clone + build);
- per tool, from the subagent's session (`verify`): workspace initialized (marker +
  launcher); `.sif` downloaded into that tool's data dir; no workspace `cache/`;
  solid_gemc cloned + built; `hgc_full/runs/<id>/` with `gcard.gcard`, `out.evio`,
  `out.root`, `log.txt`, `config.json` and plots; the request verbatim in
  `hgc_full/log.md`; the verdict ends `OVERALL: PASS`.

Unavoidable deviations from a real user: the fake `HOME` with the login carried over
(Claude credentials symlinked, Codex `auth.json` copied), and any org-managed plugins
that come with the account.

**How to run** (the main agent orchestrates)
```bash
tests/full-test.sh setup                 # background; prints SANDBOX=<dir>
#   → one subagent per tool, in parallel, prompt = <dir>/agent-claude.md / agent-codex.md
tests/full-test.sh verify <dir>          # → <dir>/logs/summary.md, RESULT: PASS|FAIL
tests/full-test.sh cleanup <dir>         # stops sessions + sandbox processes; SGC_KEEP=1 keeps <dir>
```
- The default source is the published `main`, so unpushed work isn't tested — use
  `SGC_SOURCE=local` after committing.
- If the image host (personal Duke webhome, no SLA) is down, the test fails at the
  download — what a real user would hit. There is no fallback.
- Read only `summary.md`; triage a FAIL with a fresh subagent on `<dir>/logs/`.
- Status: built, not yet run (basic test likewise).

## Known-fail
A Codex-installed `init` writes no workspace `CLAUDE.md`: `codex plugin add` drops
symlinks, and `templates/CLAUDE.md` is a symlink to `AGENTS.md`. Codex itself reads
`AGENTS.md`, but a later Claude Code session in that workspace gets no rules. Reported
as `KNOWN-FAIL`, not a failure, until `init` is fixed.

## Not covered yet
Behaviors already in the plugin that no test checks (from the deleted manual
checklists):
- **Negative trigger** — a pure Geant4 request ("build a Geant4 sim of a lead block")
  must not load this plugin's skill (`SKILL.md` description + its "Do not load" list).
- **"Just write the plan"** — choosing it at the plan gate must create no GCard copy and
  no `runs/` dir; only the `<project>/log.md` entry ("Plan only — did not run") that the
  log-every-request rule requires.
- **Clean session start** — opening a session triggers no hook, no MCP prompt, no
  Python install.
- **`init` twice** — the second run skips existing files without `--force`, doesn't
  re-download the image, and scons has nothing to rebuild.
- **Plugin update** — after a version bump the image is still `[present]` (no
  re-download).
- **The in-app `/plugin` screen** — tests install with the `claude plugin` command line,
  which goes through the same install code.

## Lints (CI, `.github/workflows/lint.yml`)
- `lint-skill-frontmatter.py` — strict-YAML skill frontmatter (Codex silently skips a
  skill whose description has an unquoted `: `).
- `lint-agents-mirror.sh` — every shipped `CLAUDE.md` is a symlink to a real `AGENTS.md`.
- `bash -n` on the shell scripts; `py_compile` on the Python.

## Files
| File | Role |
|---|---|
| `lib.sh` | shared: sandbox + `iso`, install, isolation guard, sandbox-process cleanup, tier 0, tier A |
| `quick-test.sh` | the quick test |
| `full-test.sh` | `setup` / `verify` / `cleanup` for the full test (`SGC_TEST_MODE=basic` → basic) |
| `basic-test.sh` | the basic test: runs `full-test.sh` in basic mode |
| `full-test-agent.md` | the subagent's prompt (basic + full); `setup` fills in `@TOOL@`, `@SESSION@`, `@PROJECT@`, … |
| `lint-*.{sh,py}` | the CI lints |

## Who runs what
- **Agents decide when to run the quick test — not after every change**: after a change
  that can affect install or runtime behavior (`bin/`, `templates/`, the skill's
  commands, `tests/`) and before proposing a commit; not for docs-only or wording edits;
  several edits batched into one run.
- **Agents suggest the basic test; the maintainer decides.** After changes to `skills/`
  or the orchestrator flow, the agent recommends it with the reason and runs it only
  when the maintainer says so.
- **Agents never run the full test.** They recommend it to the maintainer — before a
  release, and after changes to install, the image download, `init`/build, or the
  skill's flow — and the maintainer starts it.

## Rules and gotchas
- Don't use `~/claude/geant4_claude` code in these tests (no `source`, no calls);
  copying a snippet and modifying it is fine — note it in BUILD_LOG.
- Never point a test at `~/claude/run_solid_gemc/` — `init` runs scons on whatever tree
  it is given; use `templates/solid_gemc`.
- Interactive Codex starts an `app-server` daemon from `$CODEX_HOME/packages/` that
  outlives its tmux session and recreates files after `rm -rf`; the tests kill every
  process running from the sandbox `HOME` (TERM, then KILL).
- Codex treats text followed at once by Enter as a paste: pause before Enter.
- Claude Code's first start after an install says "Plugins changed"; `/reload-plugins`
  doesn't refresh plugin `bin/` on PATH — a fresh start does.
- Codex reads a **local** marketplace's skills and templates from its source dir, not
  its install cache.
- Inside a `solid_gemc` that is a symlink to a tree outside the workspace, the wrapper
  can't find the workspace marker (`pwd -P` leaves it); pass `SoLID_GEMC`, as the skill
  does.
