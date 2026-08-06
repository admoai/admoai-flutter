import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared cross-SDK E2E scenario manifest is mirrored byte-identically into all three SDK
/// repos. This pins its SHA-256 so an edit to one copy fails that repo's build until the constant
/// is updated — and because the SAME constant appears in all three repos, three matching hashes is
/// mechanical proof the copies agree. Divergence is otherwise invisible: it was exactly how the
/// hand-written suites drifted (Android's K1 asserted less than iOS's and Flutter's).
///
/// If this fails after you intentionally changed the manifest: update the copy in ALL THREE repos,
/// then update this constant in all three. Cross-repo enforcement in CI belongs in adhub, the only
/// place that can see all three at once.
const expectedManifestSha256 =
    '5b7c2b3d261d68b5b4e52091d0b00ac7ec1bd09cf950f482ce968e1e1a34d2ca';

void main() {
  final file = File('test/e2e/scenarios.json');

  test('the manifest matches the cross-SDK hash', () {
    final digest = sha256.convert(file.readAsBytesSync()).toString();
    expect(digest, equals(expectedManifestSha256),
        reason: 'scenarios.json changed. Mirror the edit into admoai-ios and admoai-android, '
            'then update expectedManifestSha256 in all three repos.');
  });

  test('the manifest is structurally valid', () {
    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final scenarios = (root['scenarios'] as List).cast<Map<String, dynamic>>();

    expect(scenarios, isNotEmpty, reason: 'the manifest declares at least one scenario');
    final ids = scenarios.map((s) => s['id'] as String?).whereType<String>().toList();
    expect(ids.length, equals(scenarios.length), reason: 'every scenario has an id');
    expect(ids.toSet().length, equals(ids.length), reason: 'scenario ids are unique');
    for (final s in scenarios) {
      expect((s['title'] as String?) ?? '', isNotEmpty, reason: '${s['id']} has a title');
      expect(s['request'], isA<Map<String, dynamic>>(), reason: '${s['id']} has a request block');
      expect(s['expect'], isA<Map<String, dynamic>>(), reason: '${s['id']} has an expect block');
    }
  });
}
