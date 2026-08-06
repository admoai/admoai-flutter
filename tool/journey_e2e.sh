#!/usr/bin/env bash
#
# Runs the Journey Ads live E2E suite against a locally-running decision-engine
# and exits with the same contract as the Android runner:
#
#   0  pass (a documented SKIP is allowed)
#   1  a scenario FAILED
#   2  preflight aborted — the environment is unusable, not the SDK
#
# `flutter test` only distinguishes pass/fail, so the exit code is taken from the
# machine-readable report the suite writes. That report is also what lets a later
# round diff scenario-by-scenario after an engine change, instead of re-reading
# console output.
#
# Usage:
#   tool/journey_e2e.sh
#   ADMOAI_JOURNEY_E2E_BASE_URL=http://127.0.0.1:8080 tool/journey_e2e.sh
#
# Environment:
#   ADMOAI_JOURNEY_E2E_BASE_URL  default http://127.0.0.1:8080
#   ADMOAI_JOURNEY_E2E_VERSION   default 2025-11-01
#
# Requires the engine reachable on the Journey-capable API version, Statsig
# `is_journey_ads_enabled = true` (default OFF), Redis up, a 32-char TRACKING_KEY,
# mock seeds loaded, and VAST env vars for the video scenarios.

set -uo pipefail

cd "$(dirname "$0")/.."

REPORT="build/journey-e2e/report.json"
RUNNER="test/e2e/journey_e2e_test.dart"

rm -f "$REPORT"

flutter test "$RUNNER" --reporter expanded
test_exit=$?

if [[ ! -f "$REPORT" ]]; then
  echo ""
  echo "FATAL: the suite produced no report at $REPORT."
  echo "       It likely failed to compile or crashed before tearDownAll."
  echo "       flutter test exited $test_exit."
  exit 2
fi

exit_code=$(python3 -c "
import json, sys
report = json.load(open('$REPORT'))
print(report.get('exitCode', 1))
")

# Release gate. A missing fixture SKIPs rather than FAILs by design — an unseeded
# fixture is an environment fact, not a defect — but the wizard-parity group is
# hand-built in the Ad Manager and does not survive `make db-reset`. When it
# vanishes, §K skips, the summary still reads "0 failed", and the run looks green
# while the one seam that catches platform-writes/engine-reads mismatches (adhub
# #2459, #2483 — both of which survived a fully green suite) goes unverified.
#
# Set ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD=1 for release sign-off to turn that into a
# failure. Left off by default so ordinary development runs keep the documented
# SKIP semantics.
if [[ "${ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD:-0}" == "1" && "$exit_code" == "0" ]]; then
  wizard_ok=$(python3 -c "
import json
report = json.load(open('$REPORT'))
k = [s for s in report['scenarios'] if s['id'].startswith('K')]
print('yes' if k and all(s['outcome'] == 'PASS' for s in k) else 'no')
")
  if [[ "$wizard_ok" != "yes" ]]; then
    echo ""
    echo "RELEASE GATE FAILED: the wizard-parity group (§K) is not PASS."
    echo "  ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD=1 is set, so a SKIP here is a failure."
    echo "  The fixture is hand-built and does not survive \`make db-reset\`."
    echo "  Rebuild it in the Ad Manager per test/e2e/fixtures/README.md, then re-run."
    exit 1
  fi
fi

# A crash inside a scenario body is caught and recorded as a FAIL, but a crash in
# the harness itself is not — so a non-zero flutter exit with a clean report still
# has to fail the run rather than be silently reported as green.
if [[ "$exit_code" == "0" && "$test_exit" != "0" ]]; then
  echo ""
  echo "FATAL: report says every scenario passed but flutter test exited"
  echo "       $test_exit — the harness itself failed. Treating as a failure."
  exit 1
fi

exit "$exit_code"
