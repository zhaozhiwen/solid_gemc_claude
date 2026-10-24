#!/usr/bin/env bash
# Workspace launcher: `solid-gemc-run init` copies this file to
# <workspace>/bin/solid-gemc-run. On every call it runs the newest installed
# solid-gemc-claude wrapper, so plugin updates need no workspace change. It holds
# no plugin path. The two search globs are a contract: a release that changes
# them must tell users to re-run `init` (which rewrites this file). Don't edit.
set -euo pipefail

claude_glob="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/cache/*/solid-gemc-claude/*/bin/solid-gemc-run"
codex_glob="${CODEX_HOME:-${HOME}/.codex}/plugins/cache/*/solid-gemc-claude/*/bin/solid-gemc-run"
if [[ -n "${CODEX_THREAD_ID:-}${CODEX_CI:-}" && -z "${CLAUDECODE:-}" ]]; then
  globs=("${codex_glob}" "${claude_glob}")
else
  globs=("${claude_glob}" "${codex_glob}")
fi

for g in "${globs[@]}"; do
  # Newest by the <ver> path component, regardless of marketplace name.
  # shellcheck disable=SC2086  # the glob must expand
  w="$(ls -d ${g} 2>/dev/null | awk -F/ '{print $(NF-2) "\t" $0}' | sort -V | tail -1 | cut -f2 || true)"
  [[ -n "${w}" && -x "${w}" ]] && exec "${w}" "$@"
done

printf '[solid-gemc-run] error: no installed solid-gemc-claude wrapper found in\n  %s\n  %s\nInstall the plugin in Claude Code or Codex.\n' \
  "${globs[0]}" "${globs[1]}" >&2
exit 1
