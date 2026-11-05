import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The shared cross-SDK scenario manifest is vendored from adhub's `@admoai/sdk-scenarios`
/// package (admoai/adhub#4158). Which version, and that the bytes are exactly that version, is
/// CI's "Scenario manifest" job (`.github/scripts/scenarios.sh check`); it replaced the SHA-256
/// this file used to pin, so there is one pin, `test/e2e/MANIFEST_VERSION`, not two. What stays
/// here, offline, is the shape the runner relies on.
void main() {
  final file = File('test/e2e/scenarios.json');

  test('the manifest is structurally valid', () {
    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final scenarios = (root['scenarios'] as List).cast<Map<String, dynamic>>();

    expect(scenarios, isNotEmpty,
        reason: 'the manifest declares at least one scenario');
    final ids =
        scenarios.map((s) => s['id'] as String?).whereType<String>().toList();
    expect(ids.length, equals(scenarios.length),
        reason: 'every scenario has an id');
    expect(ids.toSet().length, equals(ids.length),
        reason: 'scenario ids are unique');
    for (final s in scenarios) {
      expect((s['title'] as String?) ?? '', isNotEmpty,
          reason: '${s['id']} has a title');
      expect(s['request'], isA<Map<String, dynamic>>(),
          reason: '${s['id']} has a request block');
      expect(s['expect'], isA<Map<String, dynamic>>(),
          reason: '${s['id']} has an expect block');
    }
  });

  /// `schemaVersion` 2 added `fixtureScenarios`; the live runner refuses any other version and
  /// fixture_scenarios_test.dart interprets them, so both are pinned here against the vendored copy.
  test('the fixture scenarios are structurally valid', () {
    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(root['schemaVersion'], equals(2),
        reason: 'this SDK vendors a schemaVersion 2 manifest');

    final fixtureScenarios =
        (root['fixtureScenarios'] as List).cast<Map<String, dynamic>>();
    expect(fixtureScenarios, isNotEmpty,
        reason: 'the manifest declares fixture scenarios');
    final ids = fixtureScenarios
        .map((s) => s['id'] as String?)
        .whereType<String>()
        .toList();
    expect(ids.length, equals(fixtureScenarios.length),
        reason: 'every fixture scenario has an id');
    expect(ids.toSet().length, equals(ids.length),
        reason: 'fixture scenario ids are unique');
    for (final s in fixtureScenarios) {
      final id = s['id'];
      expect((s['title'] as String?) ?? '', isNotEmpty,
          reason: '$id has a title');
      final golden = (s['fixture'] as Map<String, dynamic>?)?['golden'];
      expect(golden is String && golden.isNotEmpty, isTrue,
          reason: '$id names a golden file');
      if (golden is String) {
        expect(File('test/e2e/fixtures/golden-wire/$golden.json').existsSync(),
            isTrue,
            reason: '$id: $golden.json is vendored');
      }
      expect(s['expect'], isA<Map<String, dynamic>>(),
          reason: '$id has an expect block');
    }
  });
}
