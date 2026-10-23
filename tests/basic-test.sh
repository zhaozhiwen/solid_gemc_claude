#!/usr/bin/env bash
# tests/basic-test.sh — basic test: real Claude Code and Codex sessions driven by
# subagents, with the quick test's shortcuts (working-tree plugin copy, linked
# .sif and prebuilt templates/solid_gemc; init skips scons). Same setup / verify /
# cleanup flow as the full test; the two subagents run in parallel. See tests/README.md.
SGC_TEST_MODE=basic exec "$(dirname "$0")/full-test.sh" "$@"
