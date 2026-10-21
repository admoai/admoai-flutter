#!/usr/bin/env bash
#
# The package's public API baseline, api/admoai.api.txt (see tool/api_render.py).
#
# Usage:
#   tool/api.sh           regenerate it — run after an intended API change and commit it
#   tool/api.sh --check   what CI runs: fail when the code's API differs from the baseline,
#                         and classify the difference against the merge base
#
# The gate is the committed file, so every API change is a diff a reviewer reads in the PR.
# The classification (which changes are breaking) comes from `dart-apitool diff` between
# the merge base with origin/main and this checkout; dart-apitool cannot read an extract
# back, so it compares two package directories. It is informative and never the gate.
#
# Requires dart-apitool on PATH: `dart pub global activate dart_apitool 0.23.2`
# (CI pins the same version).
set -euo pipefail

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
cleanup() {
  [[ -d "$tmp/base" ]] && git worktree remove --force "$tmp/base" >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT

dart-apitool extract --input . --output "$tmp/raw.json" >/dev/null
python3 tool/api_render.py "$tmp/raw.json" "$tmp/admoai.api.txt"
count="$(grep -vc '^#' "$tmp/admoai.api.txt")"

if [[ "${1:-}" != "--check" ]]; then
  mkdir -p api
  cp "$tmp/admoai.api.txt" api/admoai.api.txt
  echo "api/admoai.api.txt regenerated: $count public symbols"
  exit 0
fi

if diff -u api/admoai.api.txt "$tmp/admoai.api.txt" > "$tmp/api.diff"; then
  echo "✓ the public API matches api/admoai.api.txt ($count symbols)"
  exit 0
fi

echo "✗ the public API changed and api/admoai.api.txt was not regenerated:"
echo
cat "$tmp/api.diff"
echo
if base="$(git merge-base HEAD origin/main 2>/dev/null)"; then
  git worktree add --quiet --detach "$tmp/base" "$base"
  dart-apitool diff --old "$tmp/base" --new . --version-check-mode none \
    --report-format markdown --report-file-path "$tmp/report.md" >/dev/null 2>&1 || true
fi
if [[ -s "$tmp/report.md" ]]; then
  echo "Classification against the merge base (${base:0:7}):"
  cat "$tmp/report.md"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$tmp/report.md" >> "$GITHUB_STEP_SUMMARY"
else
  echo "(no classification: origin/main is not available to compare against)"
fi
echo
echo "Fix: run tool/api.sh and commit api/admoai.api.txt. If any line was removed or changed,"
echo "the change is breaking: see README, \"When the API check fails\"."
exit 1
