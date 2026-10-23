# tests/lib.sh — shared by tests/quick-test.sh and tests/full-test.sh. Sourced,
# not executed. Sets up a clean Claude Code + Codex in a sandbox (fake HOME,
# whitelisted env) and holds tier 0 (wrapper unit checks) and tier A (installed
# plugin, no model).

# --- helpers ----------------------------------------------------------------
# Every result line carries the seconds since the previous one (its step). With
# TIMING_FILE set (timing_start), each line is also kept there as
# total<TAB>step<TAB>status<TAB>message — outside the sandbox, so it survives cleanup.
N_PASS=0; N_KFAIL=0; T_LAST=${SECONDS}; TIMING_FILE=""
step()  { STEP=$((SECONDS-T_LAST)); T_LAST=${SECONDS}
          [[ -z "${TIMING_FILE}" ]] || printf '%s\t%s\t%s\t%s\n' "${SECONDS}" "${STEP}" "$1" "$2" >> "${TIMING_FILE}"; }
log()   { [[ -z "${TIMING_FILE}" ]] || printf '%s\t\t--\t%s\n' "${SECONDS}" "$*" >> "${TIMING_FILE}"
          printf '\n--- %s ---\n' "$*"; }
pass()  { step PASS "$*"; printf '  [PASS] %s (%ss)\n' "$*" "${STEP}"; N_PASS=$((N_PASS+1)); }
kfail() { step KNOWN-FAIL "$*"; printf '  [KNOWN-FAIL] %s (%ss)\n' "$*" "${STEP}"; N_KFAIL=$((N_KFAIL+1)); }
fail()  { step FAIL "$*"; printf '\n[FAIL] %s (%ss)\n' "$*" "${STEP}" >&2; exit 1; }
# timing_start <plugin-root> <name>: TIMING_FILE = <root>/.test-cache/timing/<UTC>-<name>.tsv
timing_start() {
  mkdir -p "$1/.test-cache/timing"
  TIMING_FILE="$1/.test-cache/timing/$(date -u +%Y%m%d-%H%M%S)-$2.tsv"
  printf 'total_s\tstep_s\tstatus\tstep\n' > "${TIMING_FILE}"
}
require() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found on PATH"; }

read_consts() { # plugin-root → SIF_NAME, DATA_NAME
  SIF_NAME=$(grep '^SIF_NAME=' "$1/bin/solid-gemc-run" | head -1 | cut -d'"' -f2)
  DATA_NAME=$(grep '^PLUGIN_DATA_NAME=' "$1/bin/solid-gemc-run" | head -1 | cut -d'"' -f2)
}

# --- sandbox ----------------------------------------------------------------
# new_sandbox prefix. Every tool call runs through iso():
# fake HOME + whitelisted env, so nothing from the operator's session
# (CLAUDECODE, CODEX_*, CLAUDE_CODE_*) leaks in.
new_sandbox() {
  SCRATCH=$(mktemp -d -t "$1.XXXXXX")
  mkdir -p "${SCRATCH}/logs"
  FAKE_HOME="${SCRATCH}/home"; mkdir -p "${FAKE_HOME}"
  TOOL_PATH="$(dirname "$(command -v claude)"):$(dirname "$(command -v codex)"):$(dirname "$(command -v apptainer)"):/usr/local/bin:/usr/bin:/bin"
  trap on_exit EXIT
}
# SGC_UV_CACHE (set by the quick test only) becomes uv's download cache, so the
# per-workspace venv installs from a persistent test cache instead of PyPI each run.
iso() { env -i HOME="${FAKE_HOME}" PATH="${TOOL_PATH}" USER="${USER}" LOGNAME="${USER}" \
  LANG=C.UTF-8 TERM="${TERM:-xterm-256color}" \
  ${SGC_UV_CACHE:+UV_CACHE_DIR="${SGC_UV_CACHE}" UV_LINK_MODE=copy} "$@"; }

# Stop everything running from the sandbox HOME. Interactive Codex leaves an
# app-server daemon from $CODEX_HOME/packages/ that outlives its tmux session and
# recreates files after rm -rf; some ignore SIGTERM, hence the SIGKILL pass.
kill_sandbox_procs() { # sandbox
  local i
  pgrep -f "^$1/home/" | xargs -r kill 2>/dev/null || true
  for (( i=0; i<5; i++ )); do pgrep -f "^$1/home/" >/dev/null || return 0; sleep 1; done
  pgrep -f "^$1/home/" | xargs -r kill -9 2>/dev/null || true
}
on_exit() {
  local rc=$?
  kill_sandbox_procs "${SCRATCH}"
  if [[ ${rc} -ne 0 || -n "${SGC_KEEP:-}" ]]; then
    printf '\n[test] sandbox kept: %s\n' "${SCRATCH}" >&2
  else
    rm -rf "${SCRATCH}"
  fi
}

# --- isolation guard ----------------------------------------------------------
REAL_STATE=("${HOME}/.claude/plugins/installed_plugins.json"
            "${HOME}/.claude/plugins/known_marketplaces.json"
            "${HOME}/.codex/config.toml")
state_sum() { local f; for f in "${REAL_STATE[@]}"; do
  [[ -f "${f}" ]] && sha256sum "${f}" || echo "absent ${f}"; done; }

# --- install ----------------------------------------------------------------
# install_plugin <marketplace-source>: a local dir or a GitHub owner/repo, added
# and installed the way README tells users; sets WRAPPER[tool] to the installed
# (newest-version) wrapper.
declare -A WRAPPER VAR LABEL
VAR[claude]="CLAUDECODE=1";             LABEL[claude]="Claude Code plugin data"
VAR[codex]="CODEX_THREAD_ID=sgc-test";  LABEL[codex]="Codex plugin data"
install_plugin() {
  local src="$1" t
  iso claude plugin marketplace add "${src}" > "${SCRATCH}/logs/install-claude.log" 2>&1 \
    && iso claude plugin install solid-gemc-claude@solid-gemc-claude --scope user \
       >> "${SCRATCH}/logs/install-claude.log" 2>&1 \
    || fail "Claude Code plugin install failed; see logs/install-claude.log"
  iso codex plugin marketplace add "${src}" > "${SCRATCH}/logs/install-codex.log" 2>&1 \
    && iso codex plugin add solid-gemc-claude@solid-gemc-claude >> "${SCRATCH}/logs/install-codex.log" 2>&1 \
    || fail "Codex plugin install failed; see logs/install-codex.log"
  for t in claude codex; do
    WRAPPER[$t]=$(ls -d "${FAKE_HOME}/.${t}"/plugins/cache/*/solid-gemc-claude/*/bin/solid-gemc-run 2>/dev/null \
      | awk -F/ '{print $(NF-2) "\t" $0}' | sort -V | tail -1 | cut -f2 || true)
    [[ -n "${WRAPPER[$t]}" && -x "${WRAPPER[$t]}" ]] || fail "${t}: no installed wrapper under ${FAKE_HOME}/.${t}/plugins/cache"
  done
  pass "installed from ${src}: claude $(basename "$(dirname "$(dirname "${WRAPPER[claude]}")")"), codex $(basename "$(dirname "$(dirname "${WRAPPER[codex]}")")")"
}

# --- quick shortcuts (quick + basic tests) -------------------------------------
# quick_links <repo>: SG = the built templates/solid_gemc clone; SIF_SRC = the pinned
# .sif from $SGC_SIF or the operator's real plugin data dir (read only). Needs read_consts.
quick_links() {
  local d f
  SG="$1/templates/solid_gemc"
  [[ -x "${SG}/source/2.9/solid_gemc" ]] \
    || fail "no built tree at templates/solid_gemc — run: bin/solid-gemc-run clone templates/solid_gemc && bin/solid-gemc-run build templates/solid_gemc"
  SIF_SRC="${SGC_SIF:-}"
  if [[ -z "${SIF_SRC}" ]]; then
    for d in "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}" "${CODEX_HOME:-${HOME}/.codex}"; do
      f="${d}/plugins/data/${DATA_NAME}/cache/sif/${SIF_NAME}"
      [[ -f "${f}" ]] && { SIF_SRC="${f}"; break; }
    done
  fi
  [[ -n "${SIF_SRC}" && -f "${SIF_SRC}" ]] || fail "no .sif found — set SGC_SIF=/abs/path/${SIF_NAME}"
  SIF_SRC="$(readlink -f "${SIF_SRC}")"
}

# plugin_copy <repo>: PLUGIN_COPY = tracked + untracked-not-ignored files of the
# working tree, so uncommitted changes are tested and gitignored ones
# (templates/solid_gemc, BUILD_LOG.md, *.sif) are not shipped. -P keeps symlinks.
plugin_copy() {
  PLUGIN_COPY="${SCRATCH}/plugin"; mkdir -p "${PLUGIN_COPY}"
  ( cd "$1" && git ls-files -co --exclude-standard --deduplicate | while IFS= read -r f; do
      [[ -e "${f}" || -L "${f}" ]] && cp -P --parents "${f}" "${PLUGIN_COPY}/"; done )
  [[ -x "${PLUGIN_COPY}/bin/solid-gemc-run" ]] || fail "plugin copy lacks bin/solid-gemc-run"
  [[ -e "${PLUGIN_COPY}/templates/solid_gemc" ]] && fail "plugin copy includes templates/solid_gemc"
  pass "plugin copy from the working tree ($(find "${PLUGIN_COPY}" -type f | wc -l) files)"
}

link_sif() { # symlink SIF_SRC into both fake tools' data dirs
  local t
  for t in claude codex; do
    mkdir -p "${FAKE_HOME}/.${t}/plugins/data/${DATA_NAME}/cache/sif"
    ln -s "${SIF_SRC}" "${FAKE_HOME}/.${t}/plugins/data/${DATA_NAME}/cache/sif/${SIF_NAME}"
  done
  pass ".sif linked into both fake data dirs"
}

# --- tier 0 ------------------------------------------------------------------
tier_0() { # plugin-root — unit checks of that root's wrapper + launcher template
  T0_ROOT="$1"
  # Container-free, no network. Verifies the subcommands exist, that the .sif
  # cache follows the detected agent tool, and that the venv is workspace-rooted.
  log "tier 0 — wrapper unit checks on ${T0_ROOT} (no container, no network)"
  for sub in init analyze setup-python paths; do
    "${T0_ROOT}/bin/solid-gemc-run" help | grep -qE "^  ${sub} " \
      || fail "subcommand '${sub}' missing from help"
  done
  pass "init/analyze/setup-python/paths present in help"

  # Run the wrapper with every detection/home var cleared, then the given
  # VAR=value pairs applied: sgclean [VAR=value...] -- <subcommand...>
  sgclean() {
    local -a kv=()
    while [[ "$1" != "--" ]]; do kv+=("$1"); shift; done; shift
    env -u CLAUDECODE -u CODEX_THREAD_ID -u CODEX_CI -u CLAUDE_CONFIG_DIR -u CODEX_HOME \
      "${kv[@]}" "${T0_ROOT}/bin/solid-gemc-run" "$@"
  }
  cache_of() { sgclean "$@" -- paths | awk '/^cache:/{print $2}'; }

  C=$(cache_of CLAUDECODE=1 CLAUDE_CONFIG_DIR=/x/claude)
  [[ "${C}" == "/x/claude/plugins/data/${DATA_NAME}/cache" ]] \
    || fail "Claude Code cache = '${C}'"
  C=$(cache_of CLAUDECODE=1)
  [[ "${C}" == "${HOME}/.claude/plugins/data/${DATA_NAME}/cache" ]] \
    || fail "Claude Code default-home cache = '${C}'"
  pass "Claude Code: cache at \${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/data/${DATA_NAME}/cache"

  for v in CODEX_THREAD_ID=t CODEX_CI=1; do
    C=$(cache_of "${v}" CODEX_HOME=/x/codex)
    [[ "${C}" == "/x/codex/plugins/data/${DATA_NAME}/cache" ]] \
      || fail "Codex cache (${v}) = '${C}'"
  done
  C=$(cache_of CODEX_CI=1)
  [[ "${C}" == "${HOME}/.codex/plugins/data/${DATA_NAME}/cache" ]] \
    || fail "Codex default-home cache = '${C}'"
  pass "Codex: cache at \${CODEX_HOME:-~/.codex}/plugins/data/${DATA_NAME}/cache"

  # No single tool (none or both): an existing .sif in either data dir is used
  # read-only; with none present, paths reports unresolved and pull refuses
  # without downloading. Fake homes keep the real ~/.claude, ~/.codex out of it.
  EH="${SCRATCH}/empty-homes"; FH="${SCRATCH}/fake-homes"
  NOHOME=(CLAUDE_CONFIG_DIR="${EH}/claude" CODEX_HOME="${EH}/codex")
  PATHS=$(sgclean "${NOHOME[@]}" -- paths)
  grep -q '^cache: *(unresolved: no agent tool detected' <<<"${PATHS}" \
    || fail "no-tool paths did not report unresolved cache"
  sgclean "${NOHOME[@]}" -- pull 2>/dev/null && fail "pull succeeded with no agent tool and no .sif"
  BOTH=$(sgclean "${NOHOME[@]}" CLAUDECODE=1 CODEX_CI=1 -- pull 2>&1) \
    && fail "pull succeeded with both agent tools detected and no .sif"
  grep -q 'both Claude Code and Codex detected' <<<"${BOTH}" \
    || fail "pull did not refuse an ambiguous (both tools) environment: ${BOTH}"
  FCX="${FH}/codex/plugins/data/${DATA_NAME}/cache"
  mkdir -p "${FCX}/sif" && : > "${FCX}/sif/${SIF_NAME}"
  C=$(cache_of CLAUDE_CONFIG_DIR="${FH}/claude" CODEX_HOME="${FH}/codex")
  [[ "${C}" == "${FCX}" ]] || fail "no-tool fallback cache = '${C}', expected '${FCX}'"
  INFO=$(sgclean CLAUDE_CONFIG_DIR="${FH}/claude" CODEX_HOME="${FH}/codex" -- info)
  grep -q 'no single agent tool detected, read-only' <<<"${INFO}" \
    || fail "no-tool fallback not labelled read-only in info"
  pass "no single tool: existing .sif used read-only; none present → unresolved, pull refuses"

  # Workspace launcher (templates/workspace-launcher.sh, as rendered by init): picks
  # the newest installed wrapper by version, prefers the detected tool, falls
  # back to the init-time wrapper, else errors.
  LH="${SCRATCH}/launcher"; mkdir -p "${LH}/ws/bin"
  stub() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\necho "%s $*"\n' "$2" > "$1"; chmod +x "$1"; }
  for v in 0.0.5 0.0.10; do
    stub "${LH}/claude/plugins/cache/mkt/solid-gemc-claude/${v}/bin/solid-gemc-run" "claude-${v}"
  done
  stub "${LH}/codex/plugins/cache/other/solid-gemc-claude/0.0.7/bin/solid-gemc-run" "codex-0.0.7"
  stub "${LH}/init-wrapper" "init"
  TPL="$(<"${T0_ROOT}/templates/workspace-launcher.sh")"
  printf '%s\n' "${TPL//@SGC_INIT_WRAPPER@/"${LH}/init-wrapper"}" > "${LH}/ws/bin/solid-gemc-run"
  chmod +x "${LH}/ws/bin/solid-gemc-run"
  launch() {
    local -a kv=()
    while [[ "$1" != "--" ]]; do kv+=("$1"); shift; done; shift
    env -u CLAUDECODE -u CODEX_THREAD_ID -u CODEX_CI "${kv[@]}" "${LH}/ws/bin/solid-gemc-run" "$@"
  }
  L=(CLAUDE_CONFIG_DIR="${LH}/claude" CODEX_HOME="${LH}/codex")
  [[ "$(launch "${L[@]}" -- info)" == "claude-0.0.10 info" ]] \
    || fail "launcher (no tool) did not pick newest Claude install: $(launch "${L[@]}" -- info)"
  [[ "$(launch "${L[@]}" CODEX_CI=1 -- info)" == "codex-0.0.7 info" ]] \
    || fail "launcher (Codex) did not prefer the Codex install"
  [[ "$(launch CLAUDE_CONFIG_DIR="${EH}/claude" CODEX_HOME="${EH}/codex" -- info)" == "init info" ]] \
    || fail "launcher with no install did not fall back to the init-time wrapper"
  mv "${LH}/init-wrapper" "${LH}/init-wrapper.gone"
  launch CLAUDE_CONFIG_DIR="${EH}/claude" CODEX_HOME="${EH}/codex" -- info 2>/dev/null \
    && fail "launcher succeeded with no install and no init-time wrapper"
  pass "workspace launcher: newest version, detected tool first, init-time fallback, else error"

  # init's launcher write, through the real cmd_init. A non-git solid_gemc/ makes
  # init stop at clone (no network, no container); the fake read-only .sif above
  # lets it get past pull. (a) in a fresh dir init writes the rendered launcher;
  # (b) run inside a plugin checkout it must not overwrite the wrapper itself.
  INIT_ENV=(CLAUDE_CONFIG_DIR="${FH}/claude" CODEX_HOME="${FH}/codex")
  IW="${SCRATCH}/init-ws"; mkdir -p "${IW}/solid_gemc"
  ( cd "${IW}" && sgclean "${INIT_ENV[@]}" -- init >/dev/null 2>&1 ) \
    && fail "init unexpectedly passed the clone step in ${IW}"
  [[ -x "${IW}/bin/solid-gemc-run" ]] || fail "init did not write an executable bin/solid-gemc-run"
  grep -qF "\"${T0_ROOT}/bin/solid-gemc-run\"" "${IW}/bin/solid-gemc-run" \
    || fail "init's launcher lacks the init-time wrapper fallback"
  grep -q '@SGC_INIT_WRAPPER@' "${IW}/bin/solid-gemc-run" && fail "launcher placeholder left unsubstituted"
  RC="${SCRATCH}/plugin-checkout"; mkdir -p "${RC}/solid_gemc"
  # Only what init reads: bin/ + top-level template files (not templates/workspace/
  # or the 1.1 GB templates/solid_gemc clone).
  cp -r "${T0_ROOT}/bin" "${T0_ROOT}/requirements.txt" "${RC}/" && mkdir -p "${RC}/templates"
  find "${T0_ROOT}/templates" -maxdepth 1 \( -type f -o -type l \) -exec cp -P {} "${RC}/templates/" \;
  OUT=$( cd "${RC}" && env -u CLAUDECODE -u CODEX_THREAD_ID -u CODEX_CI "${INIT_ENV[@]}" \
    "${RC}/bin/solid-gemc-run" init 2>&1 ) && fail "init unexpectedly passed the clone step in ${RC}"
  cmp -s "${RC}/bin/solid-gemc-run" "${T0_ROOT}/bin/solid-gemc-run" \
    || fail "init inside a plugin checkout overwrote bin/solid-gemc-run"
  grep -q 'skipping workspace launcher' <<<"${OUT}" || fail "init did not log the launcher skip: ${OUT}"
  pass "init: writes the launcher in a workspace, never overwrites the wrapper in a plugin checkout"

  # Venv: with a .solid-gemc-workspace marker it anchors at the marker dir —
  # resolved identically from the root and a deep subdir.
  WST="${SCRATCH}/wstier"; WST_P=$(mkdir -p "${WST}/proj/runs/x" && cd "${WST}" && pwd -P)
  : > "${WST}/.solid-gemc-workspace"
  for from in "${WST}" "${WST}/proj/runs/x"; do
    WV=$( cd "${from}" && sgclean -- paths | awk '/^venv:/{print $2}')
    [[ "${WV}" == "${WST_P}/venv" ]] \
      || fail "workspace venv from ${from} = '${WV}', expected '${WST_P}/venv'"
  done
  pass "venv anchors at the workspace marker root from any subdir"

  # No marker (bare/standalone): venv falls back to \$PWD/venv.
  BARE="${SCRATCH}/bare"; BARE_P=$(mkdir -p "${BARE}" && cd "${BARE}" && pwd -P)
  BV=$( cd "${BARE}" && sgclean -- paths | awk '/^venv:/{print $2}')
  [[ "${BV}" == "${BARE_P}/venv" ]] \
    || fail "no-marker venv = '${BV}', expected '${BARE_P}/venv'"
  pass "no-marker fallback: venv at \$PWD/venv"
}

# --- tier A: installed plugin, no model --------------------------------------
# tier_a <tool> <solid_gemc-source>: "" = real clone + build by init (full test),
# else a dir to symlink as the workspace's solid_gemc (quick test).
tier_a() {
  local t="$1" sg="$2" v="${VAR[$1]}" W="${WRAPPER[$1]}" ws="${SCRATCH}/ws-$1" L out f
  log "tier A (${t}) — installed wrapper + workspace launcher"
  mkdir -p "${ws}"; [[ -n "${sg}" ]] && ln -s "${sg}" "${ws}/solid_gemc"
  L="${ws}/bin/solid-gemc-run"

  # A linked (prebuilt) tree → no scons: the test is for the plugin, not solid_gemc.
  ( cd "${ws}" && iso "${v}" ${sg:+SOLID_GEMC_SKIP_BUILD=1} "${W}" init ) > "${SCRATCH}/logs/A-${t}-init.log" 2>&1 \
    || fail "${t}: init failed; see logs/A-${t}-init.log"
  [[ -f "${ws}/.solid-gemc-workspace" ]] || fail "${t}: init wrote no workspace marker"
  for f in AGENTS.md .gitignore log.md result.md report.html; do
    [[ -f "${ws}/${f}" ]] || fail "${t}: workspace ${f} missing after init"
  done
  if [[ -f "${ws}/CLAUDE.md" ]]; then pass "${t}: init wrote the workspace files incl. CLAUDE.md"
  elif [[ "${t}" == codex ]]; then kfail "codex: no workspace CLAUDE.md (Codex drops the CLAUDE.md→AGENTS.md symlink on install)"
  else fail "${t}: workspace CLAUDE.md missing after init"; fi
  [[ -x "${L}" ]] || fail "${t}: init wrote no executable bin/solid-gemc-run"
  grep -qF "\"${W}\"" "${L}" || fail "${t}: launcher fallback is not the installed wrapper"
  [[ -e "${ws}/cache" ]] && fail "${t}: a cache/ dir appeared in the workspace"
  pass "${t}: launcher written (fallback = installed wrapper), no workspace cache/"

  out=$( cd "${ws}" && iso "${v}" "${L}" info )
  grep -qF "plugin:         $(dirname "$(dirname "${W}")")" <<<"${out}" \
    || fail "${t}: launcher did not run the ${t} install: ${out}"
  grep -qF "cache:          ${FAKE_HOME}/.${t}/plugins/data/${DATA_NAME}/cache  [${LABEL[$t]}]" <<<"${out}" \
    || fail "${t}: cache not in the fake ${t} data dir: ${out}"
  grep -q '\[present\]' <<<"${out}" || fail "${t}: .sif not present: ${out}"
  out=$( cd "${ws}" && iso "${L}" info )
  grep -q 'no single agent tool detected, read-only' <<<"${out}" \
    || fail "${t}: plain-terminal info is not read-only: ${out}"
  pass "${t}: info via launcher → ${t} install + ${t} data dir; plain terminal → read-only"

  # Bind regression: from a deep cwd the workspace root and the solid_gemc
  # tree must be bound explicitly. SoLID_GEMC is passed as the skill does (with
  # a symlinked tree, `pwd -P` inside it leaves the workspace, so the marker
  # can't be found from there).
  local sgv="SoLID_GEMC=${ws}/solid_gemc"
  out=$( cd "${ws}/solid_gemc/analysis/hgc_study" && iso "${v}" "${sgv}" SOLID_GEMC_RUN_DRYRUN=1 "${L}" exec true )
  grep -qxF -- "$(readlink -f "${ws}")" <<<"${out}" || fail "${t}: workspace root not bound: ${out}"
  grep -qxF -- "$(readlink -f "${ws}/solid_gemc")" <<<"${out}" || fail "${t}: solid_gemc tree not bound: ${out}"
  pass "${t}: workspace root + solid_gemc tree bound from a deep cwd"

  # The skill's run loop, by hand: seed a project, prep cherenkov.gcard, run
  # gemc from the upstream dir (cwd-relative detectors), evio2root, analyze.
  local root proj=quick_${t} SRC DEST SOURCE_DIR RUN_DIR
  root=$( iso "${v}" "${L}" paths | awk '/^root:/{print $2}' )
  ( cd "${ws}" && cp -r "${root}/templates/workspace/." "${proj}/" )
  [[ -f "${ws}/${proj}/log.md" ]] || fail "${t}: project not seeded from the installed templates"
  SRC=$(cd "${ws}" && find -L solid_gemc/analysis -mindepth 2 -maxdepth 2 -name cherenkov.gcard | head -1)
  [[ -n "${SRC}" ]] || fail "${t}: cherenkov.gcard not found under solid_gemc/analysis/"
  DEST="${ws}/${proj}/cherenkov.gcard"; SOURCE_DIR="${ws}/$(dirname "${SRC}")"
  cp "${ws}/${SRC}" "${DEST}"
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
  ( cd "${ws}" && iso "${v}" "${L}" validate-gcard "${DEST}" ) >/dev/null || fail "${t}: GCard invalid"
  RUN_DIR="${ws}/${proj}/runs/$(date -u +%Y%m%d-%H%M%S)-quick"
  mkdir -p "${RUN_DIR}" && cp "${DEST}" "${RUN_DIR}/gcard.gcard"
  ( cd "${SOURCE_DIR}" && iso "${v}" "${sgv}" "${L}" exec \
      "solid_gemc '${RUN_DIR}/gcard.gcard' -OUTPUT='evio,${RUN_DIR}/out.evio'" ) > "${RUN_DIR}/log.txt" 2>&1 \
    || fail "${t}: gemc failed; see ${RUN_DIR}/log.txt"
  ( cd "${RUN_DIR}" && iso "${v}" "${sgv}" "${L}" exec "evio2root -INPUTF=out.evio -R=flux" ) >> "${RUN_DIR}/log.txt" 2>&1 \
    || fail "${t}: evio2root failed; see ${RUN_DIR}/log.txt"
  [[ -s "${RUN_DIR}/out.evio" && -s "${RUN_DIR}/out.root" ]] || fail "${t}: out.evio/out.root missing"
  grep -q "Number of events to be simulated set to: 2" "${RUN_DIR}/log.txt" || fail "${t}: gemc did not run N=2"
  pass "${t}: gemc + evio2root (out.root $(stat -c %s "${RUN_DIR}/out.root") bytes)"
  ( cd "${ws}" && iso "${v}" "${L}" analyze "${RUN_DIR}" 4 ) > "${SCRATCH}/logs/A-${t}-analyze.log" 2>&1 \
    || fail "${t}: analyze failed; see logs/A-${t}-analyze.log"
  (( $(ls "${RUN_DIR}"/*.svg 2>/dev/null | wc -l) >= 1 )) || fail "${t}: analyze wrote no SVGs"
  [[ -s "${RUN_DIR}/plots.pdf" ]] || fail "${t}: analyze wrote no plots.pdf"
  grep -q "entries=.*mean=" "${SCRATCH}/logs/A-${t}-analyze.log" || fail "${t}: analyze printed no stats lines"
  [[ -e "${ws}/venv" ]] && fail "${t}: default analyze created a venv"
  pass "${t}: analyze (container ROOT) → SVGs + plots.pdf + stats, no venv"
  ( cd "${ws}" && iso "${v}" "${L}" analyze --python "${RUN_DIR}" 4 ) > "${SCRATCH}/logs/A-${t}-analyze-python.log" 2>&1 \
    || fail "${t}: analyze --python failed; see logs/A-${t}-analyze-python.log"
  (( $(ls "${RUN_DIR}"/*.png 2>/dev/null | wc -l) >= 1 )) || fail "${t}: analyze --python wrote no PNGs"
  [[ -d "${ws}/venv" ]] || fail "${t}: venv not at the workspace root"
  pass "${t}: analyze --python → PNGs, venv at ${ws##*/}/venv"
}
