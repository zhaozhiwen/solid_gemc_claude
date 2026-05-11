#!/usr/bin/env bash
# tests/clean-smoke.sh — plumbing smoke test for solid-gemc-claude.
#
# Exercises bin/solid-gemc-run + the workspace template + the simulation
# loop the orchestrator skill drives (gcard prep + solid_gemc +
# evio2root) + the analyze step, against a sandboxed CLAUDE_PLUGIN_DATA.
# Does NOT go through Claude Code, so it does not test slash-command
# dispatch, the SessionStart hook, MCP approval, the skill's
# AskUserQuestion gate, or the orchestrator's NL-trigger auto-load —
# see tests/CLEAN-INSTALL-CHECKLIST.md for the manual flow that covers
# those.
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

# --- phase 1: workspace template + image cache ------------------------------
log "phase 1 — workspace skeleton + image cache"
WS="${SCRATCH}/ws"
mkdir -p "${WS}" && cd "${WS}"
cp -r "${PLUGIN_ROOT}/templates/workspace/." .
[ -f CLAUDE.md ]   || fail "workspace/CLAUDE.md missing"
[ -f .gitignore ]  || fail "workspace/.gitignore missing"
[ -f log.md ]      || fail "workspace/log.md missing"
[ -f result.md ]   || fail "workspace/result.md missing"
for d in gcards runs analysis; do
  [ -d "$d" ] || fail "workspace skeleton missing $d/"
  [ -f "$d/.gitkeep" ] || fail "$d/.gitkeep missing"
done
pass "workspace template copied (7 files / 3 dirs)"

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

# --- phase 3: gcard prep (cherenkov.gcard) ----------------------------------
# Mirrors the skill's "prepare the GCard" sub-step: resolve the preset,
# copy from upstream, apply batch overrides on the live <gcard> block,
# write a sidecar recording the source dir for cwd-relative geometry
# lookup at run time. The sidecar is bookkeeping inside the smoke test;
# the skill carries the same info in its own state.
log "phase 3 — prepare cherenkov.gcard (small, fast, self-contained)"
PRESET=cherenkov
SRC=$(find solid_gemc/analysis -mindepth 2 -maxdepth 2 -name "${PRESET}.gcard" 2>/dev/null | head -1)
[[ -n "$SRC" ]] || fail "${PRESET}.gcard not found under solid_gemc/analysis/"
DEST="gcards/$(basename "${SRC}")"
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
printf '%s\n' "${SOURCE_DIR}" > "${DEST}.source"
sgrun validate-gcard "${DEST}" >/dev/null
[ -f "${DEST}" ]          || fail "config: ${DEST} not created"
[ -f "${DEST}.source" ]   || fail "config: ${DEST}.source sidecar missing"
grep -q '<option name="OUTPUT" value="evio,out.evio"/>'    "${DEST}" || fail "config: OUTPUT override missing"
grep -q '<option name="N" value="2"/>'                     "${DEST}" || fail "config: N override missing"
grep -q '<option name="USE_GUI" value="0"/>'               "${DEST}" || fail "config: USE_GUI override missing"
pass "cherenkov.gcard configured (2 events, USE_GUI=0, OUTPUT=evio,out.evio)"

# --- phase 4: run (gemc + evio2root) ----------------------------------------
# Mirrors the skill's "run gemc + evio2root" sub-step. The cd into
# $SOURCE_DIR is the cwd-relative-geometry-lookup discipline; absolute
# GCARD_ABS / RUN_DIR_ABS paths are how we keep the workspace dirs in
# scope from a different cwd.
log "phase 4 — run gemc + evio2root (N=2 events, ~10 s)"
RUN_ID=$(date -u +%Y%m%d-%H%M%S)-$(head -c 12 /dev/urandom | base32 | tr 'A-Z' 'a-z' | head -c 6)
RUN_DIR="runs/${RUN_ID}"
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
    sgrun exec "evio2root -INPUTF=out.evio"; \
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

# --- phase 5: analyze (optional — requires plugin venv) ---------------------
log "phase 5 — analyze (requires plugin venv with uproot/numpy/matplotlib)"
VENV_PY="${CLAUDE_PLUGIN_DATA}/venv/bin/python"
if [[ -x "${VENV_PY}" ]] && "${VENV_PY}" -c 'import uproot,numpy,matplotlib' 2>/dev/null; then
  "${VENV_PY}" - "${RUN_DIR}/out.root" "${RUN_DIR}" 4 <<'PY' >/dev/null
import sys, pathlib
import uproot, numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
root_path, run_dir, max_plots = sys.argv[1], sys.argv[2], int(sys.argv[3])
f = uproot.open(root_path)
cn = f.classnames()
trees = {k: f[k] for k, v in cn.items() if v.startswith("TTree")}
plotted = 0
for tname, tree in trees.items():
    short = tname.split(";")[0]
    if tree.num_entries == 0: continue
    for bname in tree.keys():
        if plotted >= max_plots: break
        try: arr = tree[bname].array(library="np")
        except Exception: continue
        try: flat = np.concatenate(arr).astype(float)
        except (TypeError, ValueError):
            try: flat = np.asarray(arr, dtype=float)
            except: continue
        if flat.size == 0 or not np.isfinite(flat).any(): continue
        plt.figure(); plt.hist(flat[np.isfinite(flat)], bins=40)
        plt.xlabel(bname); plt.ylabel("count"); plt.title(f"{short}/{bname}")
        safe = bname.replace("/", "_").replace(" ", "_")
        plt.savefig(pathlib.Path(run_dir) / f"hist_{short}_{safe}.png",
                    dpi=110, bbox_inches="tight")
        plt.close()
        plotted += 1
    if plotted >= max_plots: break
print(plotted)
PY
  PNG_COUNT=$(ls "${RUN_DIR}"/*.png 2>/dev/null | wc -l)
  (( PNG_COUNT >= 1 )) || fail "analyze: no PNGs produced from out.root"
  pass "analyze: ${PNG_COUNT} PNGs written to ${RUN_DIR}/"
else
  printf '  [SKIP] plugin venv missing or uproot not installed at %s\n' "${VENV_PY}"
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
