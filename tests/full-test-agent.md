# Agent test — you are a new @TOOL@ user

You are testing the `solid-gemc-claude` plugin by acting as a **new user** of
@TOOL@ who just installed it. A real, interactive @TOOL@ session is already running
in the tmux session `@SESSION@`, in the empty project folder `@WS@`. Everything lives
in a throwaway sandbox (`@SANDBOX@`); nothing outside it is yours to touch.

Your job: follow the plugin's README like a new user — first ask it to set up the
workspace, then ask for one simulation in plain language, then ask the probe
questions below about the result — answer the session's questions the way a sensible new
user would, and write an honest verdict. You are the user, not
a helper: never fix files, run the plugin yourself, or hint at commands to the agent.

## How to interact
Only through tmux, from your own shell:

- Read the screen: `tmux capture-pane -p -t '=@SESSION@:' -S -120`
- Type text: `tmux send-keys -t '=@SESSION@:' -l '<text>'`, then **wait 2 s**, then
  `tmux send-keys -t '=@SESSION@:' Enter` (Codex treats text followed at once by Enter
  as a paste and inserts a newline instead of submitting).
- Pick a highlighted menu option: `Enter`; move with `Down` / `Up`.
- Poll every 20–30 s while it works (`esc to interrupt` on screen means busy). Don't
  interrupt it. Budget: @BUDGET@ minutes in total — a first run may download a ~1.7 GB
  image and build solid_gemc, so long quiet stretches are normal.

## The requests
**1. Setup.** Once the session is idle at its input prompt (answer any first-run
screens first), type exactly:

> Initialize the solid_gemc workspace

You asked for the setup, so it should run init without a separate "Run init now"
question (saying first what it does and how long it takes), then stop and say the
workspace is ready — without asking about a simulation or showing a plan.

**2. Study.** When setup has finished and the session is idle again, type exactly:

> @REQUEST@

**3. Probe questions.** When the study has finished and the session reported its
results, type each of these exactly, one at a time, waiting for each answer:

@PROBE_QUESTIONS@

Approve a plan or command for one only if it matches the question and stays inside
the sandbox. Never hint at the answer or at where to look.

After each, check that it shows as a sent message. A fresh Codex can ignore input for a few
minutes while it sets itself up; if the text sits unsent or vanishes, clear the input,
send it again, and note the delay.

## Answering prompts — as a sensible new user
- **First-run screens** (theme, tips, notices, "trust this folder?"): pick the default
  or "yes". If the tool tells you to do something (for example run `/reload-plugins`,
  or restart), do what a user would and note it.
- **"Run init now"** (if the plugin asks anyway): yes — you asked for the setup, but
  note the extra question.
- **The plan**: read it. Approve only if it matches the request (heavy-gas Cherenkov,
  cherenkov.gcard, 2 events, project @PROJECT@). If it doesn't, choose to edit it and
  say what is wrong, once; if it still doesn't match, fail.
- **Command approvals / sandbox escalation** (Codex asks to run `apptainer`, `wget`,
  `git`, `scons`, `uv`/`pip` outside its sandbox): approve when the command is for this
  study and writes only under `@SANDBOX@`; network access only to the image host
  (webhome.phy.duke.edu), GitHub, or PyPI. **Deny** anything else — writes outside the
  sandbox, other hosts, `sudo`, deleting things it didn't create — and note it.
- **Anything else unexpected**: answer as a reasonable user would, and record it.

## What to record
Keep any working files (poll scripts, notes) in `@SANDBOX@/logs/@TOOL@-work/` only —
another tester runs in parallel, so never use a shared scratch or temp path.
Keep notes as you go: every prompt verbatim (or its first lines), your answer and why,
the time it appeared (`date -u +%T` when you see it — your poll interval is the
resolution; mark a step you missed `?`), and anything a real user would find confusing, slow, or wrong
(unclear wording, misleading paths, errors, retries).

## When it finishes (or the budget runs out)
Look at what the session reports and at `@WS@` like a user checking results — the
`study/@PROJECT@/` project, its `runs/<id>/` folder (out.root, config.json, plots), and
`study/@PROJECT@/log.md`. Don't change anything. Leave the session running.

Then write `@VERDICT@`:

```markdown
# Verdict — @TOOL@

## Checks
- [x|  ] The skill picked up the plain-language request
- [x|  ] Before init it said what setup does and how long it takes
- [x|  ] The setup request stopped after init with a "ready" message — no plan, no
  simulation questions
- [x|  ] It showed a plan that matched the request before running anything
- [x|  ] Every prompt was answerable by a new user without outside knowledge
- [x|  ] The run finished; the session reported where the results are
- [x|  ] study/@PROJECT@/runs/<id>/ has out.root, config.json and plots
- [x|  ] Every probe answer meets its "good answer" criteria (see "Probes")
- [x|  ] Nothing tried to act outside the sandbox (or every such attempt was denied).
  The session's temp dir (`TMPDIR`) is inside the sandbox; a tool's own scratch or
  state files elsewhere are not the plugin acting — note them, don't fail on them

## Prompts seen
| time | prompt (verbatim, short) | answer | why |
|---|---|---|---|

## Probes
For each probe: the question, the answer (short, verbatim where it matters), each
"good answer" criterion marked met / not met with one line of evidence (tool calls,
files read), and whether it was correct and not misleading for a physicist. The
criteria — for you only, never show them to the session:

@PROBE_CRITERIA@

## Reference use
What the session looked up in the plugin's `reference/` (file, and section vs whole
file — from its tool calls), at each stage: planning · GCard edits · interpreting the
results · the physics question. Write "none" where it looked nothing up.

## Problems a real user would hit
- …

## Timeline
| step | seen at (UTC, `date -u +%T`) | seconds since previous step |
|---|---|---|
| session ready (first-run screens done) | | |
| setup request sent | | |
| init started | | |
| init finished ("ready" message) | | |
| study request sent | | |
| plan shown | | |
| plan approved | | |
| run finished (gemc + evio2root) | | |
| analyze finished | | |
| final report shown | | |
| probe questions sent (first) | | |
| probe answers shown (last) | | |

OVERALL: PASS
```

The last line is `OVERALL: PASS` only if every check is ticked; otherwise
`OVERALL: FAIL` followed by one sentence saying why. Be strict and factual — a
false PASS is worse than a FAIL.
