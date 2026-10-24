# Backlog

Known issues and polish that no test fails on yet. One item per bullet: what a user
sees, where it comes from, and the likely fix. Remove an item in the commit that fixes
it; a fix to `skills/` needs a basic-test run (`tests/README.md`).

## Skill (`skills/solid-gemc/SKILL.md`)

- **Template note copied into logs.** The `log.md` template's Steps line says
  "exactly as printed on screen in step 2 — record only what the user saw"; agents copy
  that sentence into `<project>/log.md`. Fix: move the instruction out of the template
  block into the prose above it.
- **Plan doesn't fit a small Codex screen.** On an 80×23 terminal only "Approve this
  plan?" and the options are visible; the plan scrolls off (Codex also prints the GCard
  just before it). Fix: a shorter plan block, and don't print the GCard before the plan.
- **Codex appends workspace `log.md` entries** at the bottom, though the file says to
  prepend. Fix: give the skill a small prepend snippet instead of prose.
- **Unexplained `12` in the run command.** `"$SGC_RUN" run "$DEST" "$SOURCE_DIR" 12`
  — the max-plots argument isn't shown in the plan. Fix: drop it (the default is 12)
  or name it in the plan step.
- **"Error: Exit code 2" before the init question.** Step 0's check exits non-zero when
  init is needed, and Claude Code shows that in red. Fix: make the check print a status
  and exit 0.
- **Codex still asks ~5 approvals per run** after `/permissions`: two long inline
  scripts (GCard edit, log writing) besides `init` and `run`. Read-only commands also
  needed escalation on lily because Codex's own sandbox fails to start there (bwrap
  error) — host-specific. Fix: move the GCard edit into the wrapper too (one short
  command), keep log writing as file edits.

## Untested

- **Optical photons on by default** (`OPTICAL=1` → `RECORD_OPTICALPHOTONS=1` in the
  skill's GCard edit, 2026-10-24). Tested on `cherenkov.gcard` only (5 events: ~120
  photon hits/event in `solid_hgc`). Not yet measured on a full PVDIS/SIDIS config,
  where run time and output size grow most. Next basic/full test covers the skill path;
  time a full-config run before relying on it.
