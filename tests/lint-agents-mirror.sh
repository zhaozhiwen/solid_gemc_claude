#!/usr/bin/env bash
# Assert the CLAUDE.md / AGENTS.md single-source invariant.
#
# AGENTS.md is the canonical rules file (a real file, which Codex reads); the
# CLAUDE.md beside it is the one-line import `@AGENTS.md`, which Claude Code
# expands. One source per folder, so a user's edit to AGENTS.md reaches both
# tools. A plain file (not a symlink) because `codex plugin add` drops symlinks.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
while IFS= read -r agents; do
  dir="$(dirname "$agents")"
  claude="$dir/CLAUDE.md"
  if [[ -L "$agents" ]]; then
    echo "[FAIL] $agents is a symlink — AGENTS.md must be the real (canonical) file"
    fail=1; continue
  fi
  if [[ -L "$claude" || ! -f "$claude" ]]; then
    echo "[FAIL] $claude must be a plain file containing @AGENTS.md"
    fail=1; continue
  fi
  if [[ "$(cat "$claude")" != "@AGENTS.md" ]]; then
    echo "[FAIL] $claude must contain exactly '@AGENTS.md' (edit AGENTS.md instead)"
    fail=1; continue
  fi
  echo "[ok]   $claude → @AGENTS.md (real $(stat -c%s "$agents") b)"
done < <(git ls-files -co --exclude-standard -- 'AGENTS.md' '*/AGENTS.md')  # shipped files only (not the gitignored templates/solid_gemc clone)

[[ $fail -eq 0 ]] && echo "all CLAUDE.md import their AGENTS.md" || exit 1
