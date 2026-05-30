#!/usr/bin/env bash
# Assert every AGENTS.md is byte-identical to its sibling CLAUDE.md.
#
# Why: AGENTS.md (Codex) must mirror CLAUDE.md (Claude) — same content, one
# source of truth. We *can't* use symlinks: `codex plugin add` does not copy
# symlinks, so a symlinked AGENTS.md silently vanishes from the installed
# plugin (and the workspace scaffold). So they are real copies, and this lint
# guards against drift. See BUILD_LOG Phase 19.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
while IFS= read -r agents; do
  claude="$(dirname "$agents")/CLAUDE.md"
  if [[ -L "$agents" ]]; then
    echo "[FAIL] $agents is a symlink — must be a real file (codex plugin add drops symlinks)"
    fail=1; continue
  fi
  if [[ ! -f "$claude" ]]; then
    echo "[FAIL] $agents has no sibling CLAUDE.md"
    fail=1; continue
  fi
  if diff -q "$claude" "$agents" >/dev/null; then
    echo "[ok]   $agents == $(dirname "$agents")/CLAUDE.md"
  else
    echo "[FAIL] $agents differs from its sibling CLAUDE.md — re-copy: cp '$claude' '$agents'"
    fail=1
  fi
done < <(find . -path ./.git -prune -o -name AGENTS.md -print)

[[ $fail -eq 0 ]] && echo "all AGENTS.md mirror their sibling CLAUDE.md" || exit 1
