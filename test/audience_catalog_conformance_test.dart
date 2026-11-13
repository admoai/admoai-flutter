import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

/// The SDK's typed enums must carry exactly the catalog's canonical values, in the catalog's order.
/// The catalog is vendored from adhub (see the fixture's `$comment`); a drift on either side fails
/// here instead of reaching a publisher as a 422.
void main() {
  final catalog =
      jsonDecode(File('test/fixtures/audience_catalog.json').readAsStringSync())
          as Map<String, dynamic>;
  final presets = {
    for (final p in (catalog['presets'] as List).cast<Map<String, dynamic>>())
      p['key'] as String: p,
  };

  final sdk = <String, List<String>>{
    AudienceSignalKey.ageGroup: AgeGroup.values.map((v) => v.value).toList(),
    AudienceSignalKey.gender: Gender.values.map((v) => v.value).toList(),
    AudienceSignalKey.accountType:
        AccountType.values.map((v) => v.value).toList(),
    AudienceSignalKey.subscriptionStatus:
        SubscriptionStatus.values.map((v) => v.value).toList(),
    AudienceSignalKey.accountTenure:
        AccountTenure.values.map((v) => v.value).toList(),
    AudienceSignalKey.tripFrequency30d:
        TripFrequency30d.values.map((v) => v.value).toList(),
    AudienceSignalKey.lastTripRecency:
        LastTripRecency.values.map((v) => v.value).toList(),
  };

  test('the SDK knows exactly the catalog keys', () {
    expect(
      {...sdk.keys, AudienceSignalKey.publisherSegments},
      presets.keys.toSet(),
    );
  });

  for (final entry in sdk.entries) {
    test('${entry.key} enum values equal the catalog values, in order', () {
      final preset = presets[entry.key]!;
      expect(preset['requestShape'], 'string');
      expect(entry.value, (preset['values'] as List).cast<String>());
    });
  }

  test('publisher_segments is a string array with no fixed values', () {
    final preset = presets[AudienceSignalKey.publisherSegments]!;
    expect(preset['requestShape'], 'string_array');
    expect(preset['values'], isEmpty);
  });
}
