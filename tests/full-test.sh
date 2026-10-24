#!/usr/bin/env bash
# tests/full-test.sh — agent-driven tests for solid-gemc-claude: a real session
# in Claude Code and in Codex, each driven by a fresh subagent playing a new user
# (prompt: tests/full-test-agent.md). Everything runs in a sandbox with a fake
# HOME; the running Claude Code / Codex and the operator's real ~/.claude,
# ~/.codex are never touched (checked by verify). Unavoidable deviations: the
# fake HOME with the login carried over (Claude credentials symlinked, Codex
# auth.json copied), and any org-managed plugins that come with the account.
#
# Two modes (see tests/README.md):
#   full  (this script)        no shortcuts — published install; each session's
#                              init really downloads the image, clones and builds;
#                              unit checks on the installed plugin (the scripted run
#                              is the quick test's: it would pre-fill the image)
#   basic (tests/basic-test.sh) the quick test's shortcuts — working-tree copy,
#                              .sif and prebuilt templates/solid_gemc linked (init
#                              skips scons), sessions only
# In both modes the two subagents run in parallel.
#
# Flow (the main agent orchestrates):
#   <script> setup              # prints SANDBOX=<dir> and starts one tmux session per tool
#   subagents, prompt = <dir>/agent-claude.md and <dir>/agent-codex.md
#   <script> verify <dir>       # on-disk checks + verdicts → <dir>/logs/summary.md
#   <script> cleanup <dir>      # stop sessions + sandbox daemons, remove <dir>
#
# Full mode installs from the published GitHub marketplace, so run it after a
# push; an image-host outage fails the test. SGC_KEEP=1 makes cleanup keep the
# sandbox.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "${PLUGIN_ROOT}/tests/lib.sh"

MODE="${SGC_TEST_MODE:-full}"
[[ "${MODE}" == full || "${MODE}" == basic ]] || fail "SGC_TEST_MODE must be full or basic"
GITHUB_SOURCE="zhaozhiwen/solid_gemc_claude"
TOOLS=(claude codex)

session_name() { echo "sgct-$(basename "$1" | tr -c 'A-Za-z0-9\n' '-')-$2"; }

cmd_setup() {
  local src t name ws root project request budget testenv=""
  for c in claude codex apptainer git wget python3 tmux; do require "$c"; done
  project="hgc_${MODE}"
  request="Run the heavy-gas Cherenkov study (cherenkov.gcard) with 2 events in a new project named ${project}."
  if [[ "${MODE}" == basic ]]; then
    read_consts "${PLUGIN_ROOT}"; quick_links "${PLUGIN_ROOT}"; budget=25
  else
    unset SGC_UV_CACHE; budget=75   # a real first run: fresh downloads, no test cache
  fi
  new_sandbox "sgc-${MODE}"
  timing_start "${PLUGIN_ROOT}" "$(basename "${SCRATCH}")"
  # A successful setup must leave the sessions (and the Codex daemon) running for
  # the subagents; only a failed setup stops them.
  trap 'rc=$?; if [[ ${rc} -ne 0 ]]; then
          for t in "${TOOLS[@]}"; do tmux kill-session -t "=$(session_name "${SCRATCH}" "${t}")" 2>/dev/null || true; done
          kill_sandbox_procs "${SCRATCH}"; printf "\n[%s-test] setup failed; sandbox kept: %s\n" "${MODE}" "${SCRATCH}" >&2
        fi' EXIT
  state_sum > "${SCRATCH}/state-before.txt"

  if [[ "${MODE}" == basic ]]; then
    SGC_UV_CACHE="${PLUGIN_ROOT}/.test-cache/uv"; mkdir -p "${SGC_UV_CACHE}"
    # Test cache for an optional venv; no scons in the sessions' init (prebuilt linked tree),
    # so the two sessions share nothing they write and can run in parallel.
    testenv="UV_CACHE_DIR='${SGC_UV_CACHE}' UV_LINK_MODE=copy SOLID_GEMC_SKIP_BUILD=1"
    plugin_copy "${PLUGIN_ROOT}"; src="${PLUGIN_COPY}"
  else
    src="${GITHUB_SOURCE}"
  fi
  log "setup (${MODE}) — clean Claude Code + Codex (fake HOME), plugin from ${src}"
  # Login only: no onboarding state, no pre-trusted folders — a new user's first
  # screens appear for real and the subagent answers them.
  mkdir -p "${FAKE_HOME}/.claude" "${FAKE_HOME}/.codex"
  ln -s "${HOME}/.claude/.credentials.json" "${FAKE_HOME}/.claude/.credentials.json"
  install -m 600 "${HOME}/.codex/auth.json" "${FAKE_HOME}/.codex/auth.json"
  pass "login carried over (Claude credentials symlinked, Codex auth.json copied)"
  install_plugin "${src}"
  root="$(dirname "$(dirname "${WRAPPER[claude]}")")"
  read_consts "${root}"

  if [[ "${MODE}" == basic ]]; then
    link_sif   # unit checks + scripted run are the quick test's job
  else
    unit_checks "${root}"   # no scripted run: the sessions' own init is the real first run
  fi

  log "session — start one real session per tool (driven by subagents)"
  for t in "${TOOLS[@]}"; do
    name="$(session_name "${SCRATCH}" "${t}")"; ws="${SCRATCH}/wsB-${t}"
    mkdir -p "${ws}" "${SCRATCH}/tmp-${t}"
    [[ "${MODE}" == basic ]] && ln -s "${SG}" "${ws}/solid_gemc"
    # Default modes on purpose: Claude Code's default permission mode, Codex's
    # default sandbox + approvals. The `sleep` keeps the pane for capture.
    tmux new-session -d -s "${name}" -x 220 -y 50 \
      "cd '${ws}' && env -i HOME='${FAKE_HOME}' PATH='${TOOL_PATH}' USER='${USER}' LOGNAME='${USER}' LANG=C.UTF-8 TERM=xterm-256color TMPDIR='${SCRATCH}/tmp-${t}' ${testenv} ${t}; sleep 86400"
    sed -e "s|@TOOL@|${t}|g" -e "s|@SESSION@|${name}|g" -e "s|@SANDBOX@|${SCRATCH}|g" \
        -e "s|@WS@|${ws}|g" -e "s|@REQUEST@|${request}|g" -e "s|@PROJECT@|${project}|g" \
        -e "s|@BUDGET@|${budget}|g" \
        -e "s|@VERDICT@|${SCRATCH}/logs/verdict-${t}.md|g" \
        "${PLUGIN_ROOT}/tests/full-test-agent.md" > "${SCRATCH}/agent-${t}.md"
    pass "${t}: session ${name} started in ${ws}; agent prompt ${SCRATCH}/agent-${t}.md"
  done
  printf 'MODE=%q\nROOT=%q\nSOURCE=%q\nPROJECT=%q\nREQUEST=%q\nTIMING=%q\n' \
    "${MODE}" "${root}" "${src}" "${project}" "${request}" "${TIMING_FILE}" > "${SCRATCH}/state.env"

  log "setup done — ${N_PASS} pass, ${N_KFAIL} known-fail, ${SECONDS}s"
  echo "Step timing: ${TIMING_FILE}"
  echo "SANDBOX=${SCRATCH}"
  echo "Run the two subagents in parallel."
}

cmd_verify() {
  local S="${1:?usage: verify <sandbox>}" t ws run v ok=1
  [[ -f "${S}/state.env" ]] || fail "${S} is not an agent-test sandbox (no state.env)"
  # shellcheck disable=SC1091
  source "${S}/state.env"; read_consts "${ROOT}"
  local FH="${S}/home" out="${S}/logs/summary.md"
  # Each condition runs in a subshell, so an `exit 1` inside it fails only that check.
  check() { if ( eval "$2" ); then echo "- [x] $1"; else echo "- [ ] **FAIL** $1"; ok=0; fi; }
  {
    echo "# ${MODE^} test — ${S}"; echo; echo "Source: ${SOURCE}"; echo
    for t in "${TOOLS[@]}"; do
      ws="${S}/wsB-${t}"; run=$(ls -d "${ws}/${PROJECT}"/runs/*/ 2>/dev/null | head -1 || true)
      v="${S}/logs/verdict-${t}.md"
      local sif="${FH}/.${t}/plugins/data/${DATA_NAME}/cache/sif/${SIF_NAME}"
      echo "## ${t}"
      check "workspace initialized (marker + launcher)" "[[ -f '${ws}/.solid-gemc-workspace' && -x '${ws}/bin/solid-gemc-run' ]]"
      check "no cache/ in the workspace" "[[ ! -e '${ws}/cache' ]]"
      check "setup request logged in the workspace log.md" "grep -q 'workspace initialized' '${ws}/log.md' 2>/dev/null"
      if [[ "${MODE}" == full ]]; then
        check ".sif downloaded into the fake ${t} data dir (a real file)" "[[ -f '${sif}' && ! -L '${sif}' ]]"
        check "solid_gemc cloned + built in the workspace" "[[ -d '${ws}/solid_gemc/.git' && -x '${ws}/solid_gemc/source/2.9/solid_gemc' ]]"
      else
        check ".sif present in the fake ${t} data dir" "[[ -f '${sif}' ]]"
        check "solid_gemc link kept and built" "[[ -L '${ws}/solid_gemc' && -x '${ws}/solid_gemc/source/2.9/solid_gemc' ]]"
      fi
      check "run dir with gcard.gcard, out.evio, out.root, log.txt, config.json" \
            "[[ -n '${run}' ]] && for f in gcard.gcard out.evio out.root log.txt config.json; do [[ -s '${run}'\$f ]] || exit 1; done"
      check "analyze plots in the run dir" "[[ -n '${run}' ]] && [[ -s '${run}'plots.pdf ]] && ls '${run}'*.svg >/dev/null 2>&1"
      check "request logged verbatim in ${PROJECT}/log.md" "grep -qF '${REQUEST}' '${ws}/${PROJECT}/log.md' 2>/dev/null"
      check "subagent verdict OVERALL: PASS (${v##*/})" "grep -q '^OVERALL: PASS' '${v}' 2>/dev/null"
      echo; echo "### ${t} timeline (from the subagent)"
      awk '/^## Timeline/{f=1; next} /^## |^OVERALL/{f=0} f' "${v}" 2>/dev/null || true
      echo
    done
    echo "## isolation"
    check "operator's real ~/.claude + ~/.codex plugin state unchanged" "[[ \"\$(state_sum)\" == \"\$(cat '${S}/state-before.txt')\" ]]"
    echo; [[ ${ok} == 1 ]] && echo "RESULT: PASS" || echo "RESULT: FAIL"
  } > "${out}"
  cp "${out}" "${TIMING%.tsv}-summary.md"
  cat "${out}"; echo "Kept: ${TIMING%.tsv}-summary.md (setup steps: ${TIMING})"
  [[ ${ok} == 1 ]]
}

cmd_cleanup() {
  local S="${1:?usage: cleanup <sandbox>}" t
  [[ -f "${S}/state.env" ]] || fail "${S} is not an agent-test sandbox (no state.env)"
  for t in "${TOOLS[@]}"; do tmux kill-session -t "=$(session_name "${S}" "${t}")" 2>/dev/null || true; done
  kill_sandbox_procs "${S}"
  pgrep -f "^${S}/home/" >/dev/null && fail "processes from ${S}/home still running"
  if [[ -n "${SGC_KEEP:-}" ]]; then echo "sessions stopped; sandbox kept: ${S}"
  else rm -rf "${S}"; echo "sessions stopped; sandbox removed: ${S}"; fi
}

case "${1:-}" in
  setup)   cmd_setup ;;
  verify)  cmd_verify "${2:-}" ;;
  cleanup) cmd_cleanup "${2:-}" ;;
  *) sed -n '2,27p' "$0"; exit 2 ;;
esac
