#!/usr/bin/env bash
# tests/quick-test.sh — quick test for solid-gemc-claude (no model calls).
#
# Sets up a CLEAN Claude Code and Codex inside a throwaway sandbox (fake HOME,
# whitelisted env), installs the plugin into both from a copy of the current
# working tree, then tests what a user gets. The running Claude Code / Codex
# sessions and their ~/.claude, ~/.codex are never touched (checked at the
# end). "Quick" = no 1.7 GB download and no scons build from scratch:
#   - the .sif is symlinked into each fake tool's plugin data dir;
#   - each workspace's solid_gemc/ is a symlink to templates/solid_gemc
#     (a gitignored clone + build: bin/solid-gemc-run clone|build templates/solid_gemc).
#
# Tiers: 0 = unit checks of the working tree's wrapper; A = installed plugin,
# no model (init → info → bind check → gemc + evio2root → analyze, through the
# workspace launcher, once per tool). Real agent sessions: tests/full-test.sh.
#
# Usage:
#   tests/quick-test.sh
#   SGC_SIF=/abs/path/<pinned>.sif tests/quick-test.sh   # else found in your
#                                       # real ~/.claude|~/.codex plugin data dir
#   SGC_KEEP=1 tests/quick-test.sh      # keep the sandbox even on success
#
# Requires: claude, codex, apptainer, git, wget, python3, and a built
# solid_gemc tree at templates/solid_gemc.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "${PLUGIN_ROOT}/tests/lib.sh"

for c in claude codex apptainer git wget python3; do require "$c"; done
read_consts "${PLUGIN_ROOT}"

quick_links "${PLUGIN_ROOT}"

new_sandbox sgc-quick
timing_start "${PLUGIN_ROOT}" quick
# Persistent, test-only uv cache (gitignored; never your real ~/.cache/uv).
SGC_UV_CACHE="${PLUGIN_ROOT}/.test-cache/uv"; mkdir -p "${SGC_UV_CACHE}"
STATE_BEFORE="$(state_sum)"

tier_0 "${PLUGIN_ROOT}"

# --- setup: clean Claude Code + Codex, plugin from the working tree ----------
log "setup — clean Claude Code + Codex (fake HOME), plugin from the working tree"
plugin_copy "${PLUGIN_ROOT}"
install_plugin "${PLUGIN_COPY}"
link_sif

tier_a claude "${SG}"
tier_a codex "${SG}"

# --- leakage scan + isolation guard ------------------------------------------
# Hard-block the literal /home/${USER} in shipped files only (tracked +
# untracked-not-ignored), so the templates/solid_gemc clone is never scanned.
# The test scripts and plans legitimately discuss the pattern.
log "leakage scan + isolation guard"
strays=$( cd "${PLUGIN_ROOT}" && git ls-files -co --exclude-standard \
          | grep -Ev '^tests/(quick-test\.sh|full-test\.sh|lib\.sh|README\.md|full-test-agent\.md)$' \
          | while IFS= read -r f; do [[ -f "${f}" ]] && grep -IlF "/home/${USER}" "${f}"; done || true )
[[ -z "${strays}" ]] || { printf 'leaks found in:\n%s\n' "${strays}"; fail "replace with a /home/\$USER placeholder"; }
pass "no /home/${USER} in shipped files"
[[ "$(state_sum)" == "${STATE_BEFORE}" ]] || fail "the operator's real ~/.claude / ~/.codex plugin state changed"
pass "operator's real ~/.claude + ~/.codex plugin state unchanged"

log "ALL GREEN — ${N_PASS} pass, ${N_KFAIL} known-fail, ${SECONDS}s"
echo "Step timing: ${TIMING_FILE}"
echo "Sandbox: ${SCRATCH}$([[ -n "${SGC_KEEP:-}" ]] && echo '  (kept)' || echo '  (removed; SGC_KEEP=1 keeps it)')"
