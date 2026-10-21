#!/usr/bin/env bash
#
# Formats the package the way CI checks it: `dart format` over the same paths,
# with the language version from pubspec.yaml. Run it before pushing when the
# "Format" step in CI fails.
#
# Usage:
#   tool/format.sh           # rewrite files in place
#   tool/format.sh --check   # what CI runs: list unformatted files, exit 1 if any
#
# CI pins the Flutter version (FLUTTER_VERSION in .github/workflows/ci.yml); a
# much older or newer local SDK can format a few lines differently.
set -euo pipefail

cd "$(dirname "$0")/.."

paths=(lib test tool)

if [[ "${1:-}" == "--check" ]]; then
  dart format --output=none --set-exit-if-changed "${paths[@]}"
else
  dart format "${paths[@]}"
fi
