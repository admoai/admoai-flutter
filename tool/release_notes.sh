#!/usr/bin/env bash
#
# Prints the release notes for one version: its section of CHANGELOG.md, from
# under its `## <version>` heading up to the next `## ` heading, with leading
# blank lines dropped. The GitHub Release for a tag is published with exactly
# this text, so CHANGELOG.md stays the single place release notes are written.
#
# Usage:
#   tool/release_notes.sh 0.6.0            # notes for one version
#   tool/release_notes.sh                  # notes for pubspec.yaml's version
#
# Exits 1, with what to do, when CHANGELOG.md has no non-empty section for it.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:-$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n1)}"
if [[ -z "$version" ]]; then
  echo "release_notes: no version given and none found in pubspec.yaml." >&2
  echo "Fix: pass the version (tool/release_notes.sh 0.6.0) or set 'version:' in pubspec.yaml." >&2
  exit 1
fi

notes="$(awk -v v="$version" '
  index($0, "## " v) == 1 && (length($0) == length(v) + 3 || substr($0, length(v) + 4, 1) == " ") { found = 1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

if [[ -z "${notes//[[:space:]]/}" ]]; then
  echo "release_notes: CHANGELOG.md has no notes for version $version." >&2
  echo "Why: the GitHub Release for v$version is published with that section, and an empty release says nothing to integrators." >&2
  echo "Fix: add a '## $version - YYYY-MM-DD' section with its changes to CHANGELOG.md (the release PR is where it belongs), then re-run." >&2
  exit 1
fi

printf '%s\n' "$notes"
