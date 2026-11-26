#!/usr/bin/env bash
#
# Generates a throwaway Flutter host app that depends on this package by path, so the
# plugin's native code (Kotlin, Swift) can be compiled and its JVM tests run the way a
# publisher's build would. CI uses it for the native-android and native-ios jobs.
#
# The host app is generated, never tracked: the repository retired its example app (#85)
# because generated symlinks under example/ broke Argo CD for admoai/adhub, which fetches
# this repo as a submodule (admoai/adhub#4585). The default directory is under build/,
# which is gitignored.
#
# Usage:
#   tool/host_app.sh [dir]     # default: build/host_app; an existing dir is recreated
#
# Then, for example:
#   cd build/host_app && flutter build apk --debug
#   cd build/host_app && flutter test integration_test/secure_form_surface_test.dart -d <device>
#   cd build/host_app/android && ./gradlew :admoai:testDebugUnitTest
#   cd build/host_app && flutter build ios --simulator --no-codesign
#   cd build/host_app/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
#     -destination 'platform=iOS Simulator,name=<an installed iPhone>'
#
# The app source is tool/host_app/main.dart (plus lead_gen_qa.dart for the
# Lead Generation QA screen, shown with --dart-define=QA_LEAD_GEN=on). Needs `flutter` on PATH.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
dir="${1:-build/host_app}"

fail() {
  echo "tool/host_app.sh: $1" >&2
  echo "  why: $2" >&2
  echo "  fix: $3" >&2
  exit 1
}

command -v flutter >/dev/null 2>&1 ||
  fail "flutter not found on PATH" \
    "the host app is created and resolved with the Flutter tool" \
    "install Flutter (the version FLUTTER_VERSION pins in .github/workflows/ci.yml) and put it on PATH"

for src in main.dart lead_gen_qa.dart; do
  [[ -f "$root/tool/host_app/$src" ]] ||
    fail "tool/host_app/$src is missing" \
      "it is a source the generated app runs" \
      "restore it with: git checkout -- tool/host_app/$src"
done

# Resolve to an absolute physical path (symlinks resolved, as for root) before
# changing directory, so an alias of the repository cannot pass the guard below.
mkdir -p "$(dirname "$dir")"
dir="$(cd "$(dirname "$dir")" && pwd -P)/$(basename "$dir")"
target="$dir"
[[ -d "$dir" ]] && target="$(cd "$dir" && pwd -P)"

# Refuse to delete the repo or anything that contains it.
case "$root/" in
  "$target"/*) fail "refusing to recreate $dir" \
    "it contains the repository itself" \
    "pass a directory outside the repo, or under build/" ;;
esac

rm -rf "$dir"

flutter create --org com.admoai --project-name admoai_host \
  --platforms android,ios "$dir" >/dev/null ||
  fail "flutter create failed in $dir" \
    "the host app could not be generated" \
    "re-run 'flutter create' there by hand to see its output; check 'flutter doctor'"

# Edit the pubspec rather than 'flutter pub add': it must not resolve before main.dart exists.
cd "$dir"
if ! grep -q '^dependencies:' pubspec.yaml; then
  fail "generated pubspec.yaml has no dependencies: block" \
    "the Flutter template changed shape" \
    "update tool/host_app.sh to add 'admoai: path: $root' to the new layout"
fi
sed -e "/^dependencies:/a\\
\\  admoai:\\
\\    path: $root" pubspec.yaml >pubspec.yaml.new
mv pubspec.yaml.new pubspec.yaml

# The on-device suite (integration_test/) runs from the host app: it needs a device-capable app
# around the plugin, and the repository has none. Its fixture pages ship as the app's assets.
grep -q '^dev_dependencies:' pubspec.yaml && grep -q '^flutter:' pubspec.yaml ||
  fail "generated pubspec.yaml has no dev_dependencies: or flutter: block" \
    "the Flutter template changed shape" \
    "update tool/host_app.sh to add integration_test and the fixture assets to the new layout"
sed -e "/^dev_dependencies:/a\\
\\  integration_test:\\
\\    sdk: flutter" \
  -e "/^flutter:/a\\
\\  assets:\\
\\    - integration_test/assets/" pubspec.yaml >pubspec.yaml.new
mv pubspec.yaml.new pubspec.yaml

cp "$root/tool/host_app/main.dart" lib/main.dart
cp "$root/tool/host_app/lead_gen_qa.dart" lib/
cp -R "$root/integration_test" integration_test
cp "$root/dart_test.yaml" dart_test.yaml
rm -rf test
# The plugin's XCTest (category rule, never a carrier) runs as the generated
# RunnerTests target: `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner`.
cp "$root/tool/host_app/RunnerTests.swift" ios/RunnerTests/RunnerTests.swift

flutter pub get ||
  fail "flutter pub get failed in $dir" \
    "the host app could not resolve the admoai package at $root" \
    "run 'flutter pub get' in $root first and fix any resolution error it prints"

echo "Host app ready in $dir (admoai from $root)"
