import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

// The `expect.creative` keys that the fixture scenarios (offline) and the live scenarios (against
// an engine) share, with the exact same semantics, so the two interpreters cannot drift: one
// implementation, two callers (test/fixture_scenarios_test.dart, test/e2e/manifest_runner.dart).

/// The `metadata` keys the manifest may name that this SDK can read.
const supportedMetadataKeys = [
  'effectiveStandardFormatKey',
  'effectiveStandardFormatVersion',
  'templateSource',
  'assetContext',
];

/// `metadata`: for each listed key the served value equals the expected one; JSON null expects
/// the key to be absent. A key this SDK cannot read FAILS, never passes by being skipped.
void checkMetadataExpectation(String id, dynamic expected, Metadata? metadata) {
  if (expected is! Map) {
    fail('$id: metadata expectation is not an object');
  }
  for (final entry in expected.entries) {
    switch (entry.key) {
      case 'effectiveStandardFormatKey':
        _expectOptional(
          id,
          entry.key,
          metadata?.effectiveStandardFormatKey,
          entry.value,
        );
      case 'effectiveStandardFormatVersion':
        _expectOptional(
          id,
          entry.key,
          metadata?.effectiveStandardFormatVersion,
          entry.value,
        );
      case 'templateSource':
        _expectOptional(id, entry.key, metadata?.templateSource, entry.value);
      case 'assetContext':
        _expectOptional(id, entry.key, metadata?.assetContext, entry.value);
      default:
        fail(
          '$id: unknown metadata expect key ${entry.key} '
          '(known: $supportedMetadataKeys)',
        );
    }
  }
}

/// JSON null expects the property to be `null`; anything else must equal it.
void _expectOptional<T>(String id, String key, T? actual, dynamic expected) {
  if (expected == null) {
    expect(actual, isNull, reason: '$id: metadata.$key is absent, got $actual');
  } else if (expected is T) {
    expect(actual, equals(expected), reason: '$id: metadata.$key, got $actual');
  } else {
    fail('$id: metadata.$key expectation $expected has the wrong type');
  }
}

/// `templateKey`: the served `template.key`.
void checkTemplateKey(String id, dynamic expected, Creative creative) {
  expect(creative.template?.key, equals(expected), reason: '$id: templateKey');
}

/// `contentKeys`: the exact, unordered set of plain content keys (slides and the matched-points
/// entry are not plain contents).
void checkContentKeys(String id, dynamic expected, Creative creative) {
  final plain = creative.contents.map((c) => c.key).toSet().difference({
    'slides',
    matchedPointsContentKey,
  });
  expect(
    plain,
    equals(stringList(expected).toSet()),
    reason: '$id: contentKeys, got ${plain.toList()..sort()}',
  );
}

/// `styleIn`: the served `template.style` is one of the listed styles.
void checkStyleIn(String id, dynamic expected, Creative creative) {
  final allowed = stringList(expected);
  if (allowed.isEmpty) {
    fail('$id: styleIn is an empty list');
  }
  expect(
    allowed,
    contains(creative.template?.style),
    reason: '$id: styleIn, got ${creative.template?.style}',
  );
}

/// `journeyStageKey`: the served creative's `journey.stageKey`.
void checkJourneyStageKey(String id, dynamic expected, Creative creative) {
  expect(
    creative.journey?.stageKey,
    equals(expected),
    reason: '$id: journeyStageKey',
  );
}

List<String> stringList(dynamic value) {
  if (value is! List) {
    fail('expected a list of strings, got $value');
  }
  return value.cast<String>();
}
