#!/usr/bin/env bash
# SessionStart hook: pre-warm the analysis venv on Claude Code.
#
# The actual install logic lives in `bin/solid-gemc-run setup-python` (the
# single source of truth, shared with the off-Claude lazy path). This hook is
# a thin caller so the venv is ready before the first `analyze`. It is
# idempotent (~10ms no-op when already in sync). Off Claude (Codex, standalone)
# there is no SessionStart hook, so `analyze` ensures the venv lazily instead.
set -eu

ROOT="${CLAUDE_PLUGIN_ROOT:?must be set by Claude Code}"
exec "$ROOT/bin/solid-gemc-run" setup-python
