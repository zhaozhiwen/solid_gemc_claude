#!/usr/bin/env bash
# SessionStart hook: idempotently install Python deps from requirements.txt
# into ${CLAUDE_PLUGIN_DATA}/venv. Pattern follows the official Claude Code
# plugins reference (https://code.claude.com/docs/en/plugins-reference).
#
# - Diffs bundled requirements.txt against a stored copy in DATA.
# - On match: silent no-op (~10ms).
# - On mismatch (first install or update): creates venv if needed, installs deps,
#   then mirrors requirements.txt into DATA. If install fails, DATA copy is
#   never updated, so the next session retries.
#
# Uses `uv` when available (fast); falls back to `python3 -m venv` + pip.

set -eu

ROOT="${CLAUDE_PLUGIN_ROOT:?must be set by Claude Code}"
DATA="${CLAUDE_PLUGIN_DATA:?must be set by Claude Code}"
REQ="$ROOT/requirements.txt"
STORED="$DATA/requirements.txt"
VENV="$DATA/venv"

# Minimum Python for the analyze deps (uproot>=5 / numpy>=1.24 /
# matplotlib>=3.7 / pdg all floor here on current releases). Single
# source of truth for both install paths below — KEEP IN SYNC with the
# "Python 3.9+" line in README.md Requirements and docs/index.md.
PY_MIN=3.9

# Idempotency check — exit fast if already in sync.
if diff -q "$REQ" "$STORED" >/dev/null 2>&1; then
    exit 0
fi

mkdir -p "$DATA"

echo "[solid_gemc_claude] installing Python deps into $VENV (one-time, ~30s)..."

# Create venv if it doesn't exist (or if it's stale and broken).
if [ ! -x "$VENV/bin/python" ]; then
    rm -rf "$VENV"
    if command -v uv >/dev/null 2>&1; then
        # ">=$PY_MIN", not an exact "3.11" pin: uv reuses any discovered
        # interpreter that satisfies the floor and downloads a managed
        # CPython only if none on the host qualifies. An exact pin forced
        # a download even with a fine 3.9/3.10 present and silently
        # diverged from the python3 fallback path below.
        uv venv "$VENV" --python ">=$PY_MIN" >/dev/null
    else
        # Fallback uses whatever `python3` is — enforce the same floor
        # here so a too-old interpreter fails with a clear message
        # instead of a cryptic numpy/matplotlib build error mid-install.
        if ! python3 - "$PY_MIN" <<'PY'
import sys
need = tuple(int(x) for x in sys.argv[1].split('.'))
raise SystemExit(0 if sys.version_info[:2] >= need else 1)
PY
        then
            echo "[solid_gemc_claude] python3 is $(python3 -V 2>&1 | awk '{print $2}'); need >= $PY_MIN (see README Requirements). Install a newer python3, or install 'uv'." >&2
            exit 1
        fi
        python3 -m venv "$VENV"
    fi
fi

PY="$VENV/bin/python"

# Install / upgrade deps. uv is faster but optional.
if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$PY" -r "$REQ" >/dev/null
else
    "$PY" -m pip install --upgrade pip >/dev/null
    "$PY" -m pip install -r "$REQ" >/dev/null
fi

# Mark success only on successful install. On failure (set -e exits earlier),
# STORED is unchanged, so next session retries.
cp "$REQ" "$STORED"

echo "[solid_gemc_claude] Python deps ready."
