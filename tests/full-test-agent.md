# Agent test — you are a new @TOOL@ user

You are testing the `solid-gemc-claude` plugin by acting as a **new user** of
@TOOL@ who just installed it. A real, interactive @TOOL@ session is already running
in the tmux session `@SESSION@`, in the empty project folder `@WS@`. Everything lives
in a throwaway sandbox (`@SANDBOX@`); nothing outside it is yours to touch.

Your job: ask for one simulation in plain language, answer the session's questions
the way a sensible new user would, and write an honest verdict. You are the user, not
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

## The request
Once the session is idle at its input prompt (answer any first-run screens first),
type exactly:

> @REQUEST@

Then check that it shows as a sent message. A fresh Codex can ignore input for a few
minutes while it sets itself up; if the text sits unsent or vanishes, clear the input,
send it again, and note the delay.

## Answering prompts — as a sensible new user
- **First-run screens** (theme, tips, notices, "trust this folder?"): pick the default
  or "yes". If the tool tells you to do something (for example run `/reload-plugins`,
  or restart), do what a user would and note it.
- **"Run init now"** (the plugin's first question): yes — you want the study to run.
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
`@PROJECT@/` project, its `runs/<id>/` folder (out.root, config.json, plots), and
`@PROJECT@/log.md`. Don't change anything. Leave the session running.

Then write `@VERDICT@`:

```markdown
# Verdict — @TOOL@

## Checks
- [x|  ] The skill picked up the plain-language request
- [x|  ] It asked before running init, and the question was clear
- [x|  ] It showed a plan that matched the request before running anything
- [x|  ] Every prompt was answerable by a new user without outside knowledge
- [x|  ] The run finished; the session reported where the results are
- [x|  ] @PROJECT@/runs/<id>/ has out.root, config.json and plots
- [x|  ] Nothing tried to act outside the sandbox (or every such attempt was denied).
  The session's temp dir (`TMPDIR`) is inside the sandbox; a tool's own scratch or
  state files elsewhere are not the plugin acting — note them, don't fail on them

## Prompts seen
| time | prompt (verbatim, short) | answer | why |
|---|---|---|---|

## Problems a real user would hit
- …

## Timeline
| step | seen at (UTC, `date -u +%T`) | seconds since previous step |
|---|---|---|
| session ready (first-run screens done) | | |
| request sent | | |
| init question shown | | |
| init finished | | |
| plan shown | | |
| plan approved | | |
| run finished (gemc + evio2root) | | |
| analyze finished | | |
| final report shown | | |

OVERALL: PASS
```

The last line is `OVERALL: PASS` only if every check is ticked; otherwise
`OVERALL: FAIL` followed by one sentence saying why. Be strict and factual — a
false PASS is worse than a FAIL.
