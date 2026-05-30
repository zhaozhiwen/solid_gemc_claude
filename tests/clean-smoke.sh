#!/usr/bin/env bash
# tests/clean-smoke.sh — plumbing smoke test for solid-gemc-claude.
#
# Exercises bin/solid-gemc-run (including the init/analyze/setup-python/paths
# subcommands and the off-Claude PLUGIN_ROOT/cache fallback) + the workspace
# template + the simulation loop the orchestrator skill drives (gcard prep +
# solid_gemc + evio2root) + the analyze step, against a sandboxed
# CLAUDE_PLUGIN_DATA. Does NOT go through Claude Code or Codex, so it does not
# test skill dispatch, MCP approval, the approval gate, or NL-trigger
# auto-load — see tests/CLEAN-INSTALL-CHECKLIST.md
# (Claude) and tests/CODEX-CHECKLIST.md (Codex) for the manual flows.
#
# Usage:
#   tests/clean-smoke.sh
#       Fresh state. Needs the .sif and solid_gemc tree from scratch:
#       ~1.7 GB wget pull (Duke webhome) + ~5–10 min for two scons builds.
#
#   SGC_REUSE_SIF=/abs/path/to/<pinned-name>.sif tests/clean-smoke.sh
#       Symlinks an existing .sif into the sandbox to skip the wget pull.
#
#   SGC_REUSE_SOLID_GEMC=/abs/path/to/built/solid_gemc tests/clean-smoke.sh
#       Symlinks an existing built solid_gemc tree to skip the clone +
#       scons builds. Both reuse vars stack.
#
# Requires: apptainer, bash >= 4, git, wget, python3.
# (tcsh runs inside the container, not on the host.)
# Optional: python3 with uproot+numpy+matplotlib (the plugin's venv at
#           ${CLAUDE_PLUGIN_DATA}/venv will be used if present). Without
#           them, the analyze step is skipped (the rest still runs).

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- helpers ----------------------------------------------------------------
log()  { printf '\n--- %s ---\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$*"; }
fail() { printf '\n[FAIL] %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found on PATH"
}

require bash
require apptainer
require git
require wget
require python3
# Note: tcsh is needed *inside* the container, not on the host.

# --- sandbox ----------------------------------------------------------------
SCRATCH=$(mktemp -d -t sgc-smoke.XXXXXX)
KEEP_ON_FAIL=1
cleanup() {
  local rc=$?
  if [[ $rc -ne 0 && $KEEP_ON_FAIL -eq 1 ]]; then
    printf '\n[smoke] preserved scratch for inspection: %s\n' "${SCRATCH}" >&2
  else
    rm -rf "${SCRATCH}"
  fi
}
trap cleanup EXIT

export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
export CLAUDE_PLUGIN_DATA="${SCRATCH}/data"
mkdir -p "${CLAUDE_PLUGIN_DATA}/cache/sif"

SIF_NAME=$(grep '^SIF_NAME=' "${PLUGIN_ROOT}/bin/solid-gemc-run" | head -1 | cut -d'"' -f2)
SIF_PATH="${CLAUDE_PLUGIN_DATA}/cache/sif/${SIF_NAME}"

if [[ -n "${SGC_REUSE_SIF:-}" ]]; then
  [[ -f "${SGC_REUSE_SIF}" ]] || fail "SGC_REUSE_SIF=${SGC_REUSE_SIF} not a file"
  log "reusing .sif via symlink"
  ln -sfn "${SGC_REUSE_SIF}" "${SIF_PATH}"
  pass "linked ${SGC_REUSE_SIF}"
fi

sgrun() {
  SOLID_GEMC_CLAUDE_CACHE="${CLAUDE_PLUGIN_DATA}/cache" \
    "${PLUGIN_ROOT}/bin/solid-gemc-run" "$@"
}

# --- phase 0: wrapper subcommands + off-Claude path resolution --------------
# Container-free, no network. Verifies the new subcommands exist and that the
# three-tier cache/venv resolution does the right thing on and off Claude.
log "phase 0 — wrapper subcommands + path resolution (no container)"
for sub in init analyze setup-python paths; do
  "${PLUGIN_ROOT}/bin/solid-gemc-run" help | grep -qE "^  ${sub} " \
    || fail "subcommand '${sub}' missing from help"
done
pass "init/analyze/setup-python/paths present in help"

# Under Claude (CLAUDE_PLUGIN_DATA set) cache stays strictly inside it.
sgrun paths | grep -qx "cache:      ${CLAUDE_PLUGIN_DATA}/cache" \
  || fail "Claude-tier cache did not resolve to \$CLAUDE_PLUGIN_DATA/cache"
pass "Claude tier: cache inside \$CLAUDE_PLUGIN_DATA"

# Off Claude (no CLAUDE_PLUGIN_DATA, no override): cache co-locates with the
# wrapper at PLUGIN_ROOT/cache (here PLUGIN_ROOT is this repo clone).
OFF_CACHE=$(env -u CLAUDE_PLUGIN_DATA -u SOLID_GEMC_CLAUDE_CACHE \
  "${PLUGIN_ROOT}/bin/solid-gemc-run" paths | awk '/^cache:/{print $2}')
[[ "${OFF_CACHE}" == "${PLUGIN_ROOT}/cache" ]] \
  || fail "off-Claude cache resolved to '${OFF_CACHE}', expected '${PLUGIN_ROOT}/cache'"
pass "non-Claude tier: cache co-locates at \$PLUGIN_ROOT/cache"

# The override (tier 1) wins over everything — the escape hatch for a pre-staged
# .sif or a shared cache across version-pinned installs.
OVR="${SCRATCH}/shared-sif"
OVR_CACHE=$(env -u CLAUDE_PLUGIN_DATA SOLID_GEMC_CLAUDE_CACHE="${OVR}" \
  "${PLUGIN_ROOT}/bin/solid-gemc-run" paths | awk '/^cache:/{print $2}')
[[ "${OVR_CACHE}" == "${OVR}" ]] \
  || fail "override cache resolved to '${OVR_CACHE}', expected '${OVR}'"
pass "override tier: \$SOLID_GEMC_CLAUDE_CACHE wins"

# Realistic Codex install path (deep, version-pinned, custom CODEX_HOME with no
# leading dot) must still co-locate at PLUGIN_ROOT/cache — regression guard for
# the 2026-05-30 field report. Copy the wrapper in so readlink -f resolves
# PLUGIN_ROOT into the replica. (No platform detection now — tier 3 is
# unconditional — so this just confirms a deep install path resolves cleanly.)
CDX_ROOT="${SCRATCH}/codex_home/plugins/cache/solid-gemc-claude/solid-gemc-claude/0.0.5"
mkdir -p "${CDX_ROOT}/bin"
cp "${PLUGIN_ROOT}/bin/solid-gemc-run" "${CDX_ROOT}/bin/solid-gemc-run"
CDX_CACHE=$(env -u CLAUDE_PLUGIN_DATA -u SOLID_GEMC_CLAUDE_CACHE -u CODEX_HOME \
  "${CDX_ROOT}/bin/solid-gemc-run" paths | awk '/^cache:/{print $2}')
[[ "${CDX_CACHE}" == "${CDX_ROOT}/cache" ]] \
  || fail "Codex install cache resolved to '${CDX_CACHE}', expected '${CDX_ROOT}/cache'"
pass "Codex install: deep version-pinned path co-locates at \$PLUGIN_ROOT/cache"

# --- phase 1: workspace template + image cache ------------------------------
log "phase 1 — workspace skeleton + image cache"
WS="${SCRATCH}/ws"
mkdir -p "${WS}" && cd "${WS}"
# Workspace-common files only (the five at templates/, not the per-project
# template at templates/workspace/). The per-project template is seeded
# later in phase 3 for the smoke project.
cp "${PLUGIN_ROOT}/templates/CLAUDE.md"    ./CLAUDE.md
cp -L "${PLUGIN_ROOT}/templates/AGENTS.md" ./AGENTS.md
cp "${PLUGIN_ROOT}/templates/.gitignore"   ./.gitignore
cp "${PLUGIN_ROOT}/templates/log.md"       ./log.md
cp "${PLUGIN_ROOT}/templates/result.md"    ./result.md
cp "${PLUGIN_ROOT}/templates/report.html"  ./report.html
[ -f CLAUDE.md ]   || fail "workspace CLAUDE.md missing"
[ -f AGENTS.md ]   || fail "workspace AGENTS.md missing (Codex project rules)"
[ -f .gitignore ]  || fail "workspace .gitignore missing"
[ -f log.md ]      || fail "workspace log.md missing"
[ -f result.md ]   || fail "workspace result.md missing"
[ -f report.html ] || fail "workspace report.html missing"
pass "workspace-common files copied (6 files incl. AGENTS.md)"

# Pull the .sif if not already reused.
sgrun pull
[ -f "${SIF_PATH}" ] || fail ".sif missing after pull"
pass ".sif cached at $(basename "${SIF_PATH}")"

# --- phase 2: clone + build solid_gemc --------------------------------------
log "phase 2 — solid_gemc tree (clone + 2× scons build)"
if [[ -n "${SGC_REUSE_SOLID_GEMC:-}" ]]; then
  [[ -d "${SGC_REUSE_SOLID_GEMC}/.git" ]] \
    || fail "SGC_REUSE_SOLID_GEMC=${SGC_REUSE_SOLID_GEMC} not a git clone"
  ln -sfn "${SGC_REUSE_SOLID_GEMC}" solid_gemc
  pass "linked pre-built solid_gemc"
else
  sgrun clone
  pass "cloned solid_gemc (HEAD of master)"
  sgrun build
  pass "scons build (mod/gemc/2.9 + source/2.9)"
fi
[ -x solid_gemc/source/2.9/solid_gemc ] \
  || fail "solid_gemc binary missing at solid_gemc/source/2.9/solid_gemc"
pass "solid_gemc binary present"

# --- phase 2.5: container bind regression -----------------------------------
# Regression for the cwd+cache-only bind bug: the skill cd's into a deep
# subdir (solid_gemc/script) for cwd-relative geometry lookup, then the
# in-container command reads/writes absolute paths under the workspace root
# (binary, libgemc.so, the run dir) that are NOT under that cwd. The seam
# must explicitly --bind the workspace tree, not lean on apptainer's
# implicit $HOME/$TMPDIR mount. Container-free: SOLID_GEMC_RUN_DRYRUN prints
# the resolved apptainer argv without the .sif.
log "phase 2.5 — container bind regression (workspace root must be bound)"
DEEP=solid_gemc/script
[[ -d "${DEEP}" ]] || DEEP=$(find solid_gemc/analysis -mindepth 1 -maxdepth 1 -type d | head -1)
[[ -n "${DEEP}" && -d "${DEEP}" ]] || fail "no deep subdir under solid_gemc to test cwd-relative run path"
WS_REAL=$(readlink -f "${WS}")
SOLID_REAL=$(readlink -f "${WS}/solid_gemc")
BIND_ARGV=$(
  cd "${DEEP}" && \
  SoLID_GEMC="${WS}/solid_gemc" SOLID_GEMC_RUN_DRYRUN=1 sgrun exec true
)
grep -qxF -- "${WS_REAL}"    <<<"${BIND_ARGV}" \
  || { printf '%s\n' "${BIND_ARGV}" >&2; fail "workspace root ${WS_REAL} not bound — run dir/GCard would be invisible in-container"; }
grep -qxF -- "${SOLID_REAL}" <<<"${BIND_ARGV}" \
  || { printf '%s\n' "${BIND_ARGV}" >&2; fail "solid_gemc tree ${SOLID_REAL} not bound — binary/libgemc.so would be invisible in-container"; }
pass "workspace root + solid_gemc tree explicitly bound from a deep cwd"

# --- phase 3: seed project + gcard prep (cherenkov.gcard) -------------------
# Mirrors the skill's per-project flow: seed a project subdir from the
# per-project template (flat — no geometry/ or analysis/ subdirs),
# resolve the preset, copy from upstream into <project>/, apply batch
# overrides on the live <gcard> block.
log "phase 3 — seed project + prepare cherenkov.gcard (small, fast, self-contained)"
PROJECT=cherenkov_smoke
cp -r "${PLUGIN_ROOT}/templates/workspace/." "${PROJECT}/"
[ -f "${PROJECT}/CLAUDE.md" ]            || fail "project CLAUDE.md missing under ${PROJECT}/"
[ -f "${PROJECT}/log.md" ]               || fail "project log.md missing under ${PROJECT}/"
[ -f "${PROJECT}/result.md" ]            || fail "project result.md missing under ${PROJECT}/"
[ -f "${PROJECT}/report.html" ]          || fail "project report.html missing under ${PROJECT}/"
pass "seeded project ${PROJECT}/ from templates/workspace/"

PRESET=cherenkov
SRC=$(find solid_gemc/analysis -mindepth 2 -maxdepth 2 -name "${PRESET}.gcard" 2>/dev/null | head -1)
[[ -n "$SRC" ]] || fail "${PRESET}.gcard not found under solid_gemc/analysis/"
DEST="${PROJECT}/$(basename "${SRC}")"
SOURCE_DIR=$(dirname "${SRC}")
cp "${SRC}" "${DEST}"
python3 - "${DEST}" 2 out.evio 0 <<'PY'
import re, sys, pathlib
path, n_events, output_name, gui_keep = sys.argv[1:5]
strip_keys = ['OUTPUT', 'N'] + ([] if gui_keep == '1' else ['USE_GUI'])
text = pathlib.Path(path).read_text()
m = re.search(r'(<gcard>)(.*?)(</gcard>)', text, re.DOTALL)
head, body, tail = m.groups()
body = re.sub(r'^[ \t]*<option name="(' + '|'.join(strip_keys) + r')"[^>]*/>[ \t]*\n',
              '', body, flags=re.MULTILINE)
adds = [f'<option name="OUTPUT" value="evio,{output_name}"/>',
        f'<option name="N" value="{n_events}"/>']
if gui_keep != '1':
    adds.append('<option name="USE_GUI" value="0"/>')
new_body = body.rstrip() + '\n' + '\n'.join(adds) + '\n'
pathlib.Path(path).write_text(text[:m.start(2)] + new_body + text[m.end(2):])
PY
sgrun validate-gcard "${DEST}" >/dev/null
[ -f "${DEST}" ]                                           || fail "config: ${DEST} not created"
grep -q '<option name="OUTPUT" value="evio,out.evio"/>'    "${DEST}" || fail "config: OUTPUT override missing"
grep -q '<option name="N" value="2"/>'                     "${DEST}" || fail "config: N override missing"
grep -q '<option name="USE_GUI" value="0"/>'               "${DEST}" || fail "config: USE_GUI override missing"
pass "cherenkov.gcard configured (2 events, USE_GUI=0, OUTPUT=evio,out.evio)"

# --- phase 4: run (gemc + evio2root) ----------------------------------------
# Mirrors the skill's "run gemc + evio2root" sub-step. The cd into
# $SOURCE_DIR is the cwd-relative-geometry-lookup discipline; absolute
# GCARD_ABS / RUN_DIR_ABS paths are how we keep the workspace dirs in
# scope from a different cwd. Per-run output lands under the project's
# runs/<id>/.
log "phase 4 — run gemc + evio2root (N=2 events, ~10 s)"
RUN_ID=$(date -u +%Y%m%d-%H%M%S)-$(head -c 12 /dev/urandom | base32 | tr 'A-Z' 'a-z' | head -c 6)
RUN_DIR="${PROJECT}/runs/${RUN_ID}"
mkdir -p "${RUN_DIR}"
cp "${DEST}" "${RUN_DIR}/gcard.gcard"
WORKSPACE_ABS=$(readlink -f .)
RUN_DIR_ABS="${WORKSPACE_ABS}/${RUN_DIR}"
GCARD_ABS="${WORKSPACE_ABS}/${RUN_DIR}/gcard.gcard"

GEMC_EC_FILE=$(mktemp)
( cd "${SOURCE_DIR}" && \
  SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
    sgrun exec "solid_gemc '${GCARD_ABS}' -OUTPUT='evio,${RUN_DIR_ABS}/out.evio'"; \
  echo $? > "${GEMC_EC_FILE}" ) 2>&1 | tee "${RUN_DIR_ABS}/log.txt" >/dev/null
GEMC_EXIT=$(cat "${GEMC_EC_FILE}"); rm -f "${GEMC_EC_FILE}"
[[ "${GEMC_EXIT}" = "0" ]] \
  || fail "gemc step exited with ${GEMC_EXIT}; see ${RUN_DIR}/log.txt"
[ -f "${RUN_DIR}/out.evio" ] || fail "out.evio not produced"
pass "gemc step: exit 0, out.evio=$(stat -c %s "${RUN_DIR}/out.evio") bytes"

EVIO_EC_FILE=$(mktemp)
( cd "${RUN_DIR_ABS}" && \
  SoLID_GEMC="${WORKSPACE_ABS}/solid_gemc" \
    sgrun exec "evio2root -INPUTF=out.evio -R=flux"; \
  echo $? > "${EVIO_EC_FILE}" ) 2>&1 | tee -a "${RUN_DIR_ABS}/log.txt" >/dev/null
EVIO2ROOT_EXIT=$(cat "${EVIO_EC_FILE}"); rm -f "${EVIO_EC_FILE}"
[[ "${EVIO2ROOT_EXIT}" = "0" ]] \
  || fail "evio2root exited with ${EVIO2ROOT_EXIT}; see ${RUN_DIR}/log.txt"
[ -f "${RUN_DIR}/out.root" ] || fail "out.root not produced"
pass "evio2root: exit 0, out.root=$(stat -c %s "${RUN_DIR}/out.root") bytes"

# Sanity: log.txt non-trivial size + has gemc + evio2root markers.
LOG_SIZE=$(stat -c %s "${RUN_DIR}/log.txt")
(( LOG_SIZE > 1000 )) || fail "log.txt only ${LOG_SIZE} bytes; capture broken"
grep -q "Number of events to be simulated set to: 2" "${RUN_DIR}/log.txt" \
  || fail "log.txt missing gemc N=2 confirmation"
grep -q "Input File set to: out.evio" "${RUN_DIR}/log.txt" \
  || fail "log.txt missing evio2root marker"
pass "log.txt captured (${LOG_SIZE} bytes, both phases visible)"

# --- phase 5: analyze (real subcommand — self-installs the venv) ------------
# Exercises `solid-gemc-run analyze`, which lazily runs `setup-python` (the
# shared venv install) and then bin/solid-gemc-analyze.py. This is the same
# code path Codex/standalone use, so it covers analyze + setup-python at once.
log "phase 5 — analyze subcommand (lazily installs venv, then plots)"
if sgrun setup-python; then
  sgrun analyze "${RUN_DIR}" 4 >/dev/null
  PNG_COUNT=$(ls "${RUN_DIR}"/*.png 2>/dev/null | wc -l)
  (( PNG_COUNT >= 1 )) || fail "analyze: no PNGs produced from out.root"
  pass "analyze: ${PNG_COUNT} PNGs written to ${RUN_DIR}/ (venv via setup-python)"
else
  printf '  [SKIP] setup-python failed (no network / no python3+uv); analyze skipped\n'
fi

# --- phase 6: leakage scan --------------------------------------------------
# Hard-block: the literal `/home/${USER}` path slipping into committed
# files. JLab hostnames / shared-FS paths are softer — they sometimes
# legitimately appear in CLAUDE.md/BUILD_LOG.md/CHANGELOG.md narrative;
# pre-publish manual review handles those. This file (`tests/clean-smoke.sh`)
# and `BUILD_LOG.md` (gitignored maintainer log) are excluded because they
# legitimately discuss the leakage pattern.
log "phase 6 — leakage scan (hard-block on /home/\${USER})"
strays=$(grep -RIl "/home/${USER}" "${PLUGIN_ROOT}" 2>/dev/null \
         | grep -Ev "(^${PLUGIN_ROOT}/\.git/|tests/clean-smoke\.sh\$|BUILD_LOG\.md\$|PLAN\.md\$)" \
         || true)
if [[ -n "${strays}" ]]; then
  echo "leaks found in:"
  echo "${strays}"
  fail "leakage scan failed — replace with /home/\$USER placeholder"
fi
pass "no /home/${USER} leakage in shipped files (BUILD_LOG.md / PLAN.md excluded — they're not shipped)"

# --- summary -----------------------------------------------------------------
log "ALL GREEN — clean smoke passes"
echo "Sandbox: ${SCRATCH}  (will be removed)"
echo "Run dir was: ${RUN_DIR_ABS}"
echo
echo "To re-run with the same .sif + tree:"
echo "  SGC_REUSE_SIF=${SIF_PATH:-/abs/path/to/.sif} \\"
echo "  SGC_REUSE_SOLID_GEMC=${WORKSPACE_ABS}/solid_gemc \\"
echo "  tests/clean-smoke.sh"
