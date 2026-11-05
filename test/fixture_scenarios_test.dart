import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Shared fixture scenarios (@admoai/sdk-scenarios schemaVersion 2, admoai/adhub#4734)
//
// Feature: A publisher's app reads the standard native formats from a decision response
//   As a publisher's tech team
//   I want the SDK to decode the engine's golden wire files for every standard format
//   So that what my app reads (format, version, template source, contents, slides, trackers)
//   is exactly what the platform promises, in this SDK and in the other two
//
// The scenarios are DATA: `fixtureScenarios` in `test/e2e/scenarios.json`, vendored from adhub
// with the golden decision-wire files they decode. This file is only the interpreter, and it
// is strict in one direction: a manifest key it does not know FAILS, so a newer manifest can
// never pass silently on an SDK that cannot check it.

const _e2eDirectory = 'test/e2e';

typedef _Json = Map<String, dynamic>;

const _metadataKeys = [
  'effectiveStandardFormatKey',
  'effectiveStandardFormatVersion',
  'templateSource',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final loaded = _loadScenarios();
  if (loaded.error != null) {
    // An unreadable manifest is a failing test, never zero tests (which would pass).
    test('the fixture scenarios load', () => fail(loaded.error!));
    return;
  }

  for (final scenario in loaded.scenarios) {
    test('${scenario['id']} ${scenario['title']}', () async {
      await _run(scenario);
    });
  }
}

({List<_Json> scenarios, String? error}) _loadScenarios() {
  try {
    final root =
        jsonDecode(File('$_e2eDirectory/scenarios.json').readAsStringSync());
    final entries = root is Map ? root['fixtureScenarios'] : null;
    if (entries is! List || entries.isEmpty) {
      return (
        scenarios: const [],
        error: 'the manifest has no fixtureScenarios'
      );
    }
    return (scenarios: entries.cast<_Json>(), error: null);
  } catch (e) {
    return (scenarios: const [], error: 'scenarios.json cannot be read: $e');
  }
}

Future<void> _run(_Json scenario) async {
  final id = scenario['id'] as String;
  final fixture = scenario['fixture'] as _Json;
  final golden = fixture['golden'] as String;
  final expected = scenario['expect'] as _Json;

  // The wire, as the golden file has it, then edited.
  final file = File('$_e2eDirectory/fixtures/golden-wire/$golden.json');
  final wire = jsonDecode(file.readAsStringSync()) as _Json;
  _applyEdits(id, (fixture['edits'] as List?)?.cast<_Json>() ?? const [], wire);

  final creative = await _decode(id, wire);

  for (final entry in expected.entries) {
    _check(id, entry.key, entry.value, creative);
  }
}

// MARK: - Decoding

/// Decoded exactly as a real 200 is: through `AdMoai.requestAds`, so the API client's tolerant
/// envelope parse and `Decision.fromJson` / `Creative.fromJson` are the code under test.
Future<Creative> _decode(String id, _Json wire) async {
  final client = MockClient((_) async => http.Response(
        jsonEncode(wire),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ));
  final sdk = AdMoai.forTesting(
    config: SDKConfig(baseUrl: 'https://mock.api.admoai.com'),
    httpClient: client,
  );
  final request =
      (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
  final response = await sdk.requestAds(request);
  final creatives = response.body.data?.firstOrNull?.creatives ?? const [];
  expect(creatives, hasLength(1), reason: '$id: exactly one creative');
  return creatives.first;
}

// MARK: - Edits

/// Applies `fixture.edits` in order. `at` names which object(s) of the decision wire change:
/// the response root, the first creative, its `metadata`, every element of its `contents`, or
/// every element of the `value` array of the content entry keyed `slides`.
void _applyEdits(String id, List<_Json> edits, _Json root) {
  for (final edit in edits) {
    final change = _makeChange(id, edit);
    final target = edit['at'];
    if (target == 'response') {
      change(root);
      continue;
    }
    final creative = _firstCreative(id, root);
    switch (target) {
      case 'creative':
        change(creative);
      case 'metadata':
        final metadata =
            (creative['metadata'] as _Json?) ?? <String, dynamic>{};
        change(metadata);
        creative['metadata'] = metadata;
      case 'content':
        for (final entry in (creative['contents'] as List? ?? const [])) {
          change(entry as _Json);
        }
      case 'slide':
        final contents =
            (creative['contents'] as List? ?? const []).cast<_Json>();
        final slidesEntry =
            contents.where((c) => c['key'] == 'slides').firstOrNull;
        if (slidesEntry == null) {
          fail('$id: edit at slide: the creative has no slides entry');
        }
        for (final slide in (slidesEntry['value'] as List? ?? const [])) {
          change(slide as _Json);
        }
      default:
        fail('$id: unknown edit target at=$target');
    }
  }
}

void Function(_Json) _makeChange(String id, _Json edit) {
  final remove = edit['remove'];
  if (remove is String) return (o) => o.remove(remove);
  final add = edit['add'];
  if (add is String) return (o) => o[add] = edit['value'];
  fail('$id: an edit with neither remove nor add: $edit');
}

/// `data[0].creatives[0]`, the creative every fixture scenario is about.
_Json _firstCreative(String id, _Json root) {
  final data = root['data'];
  final creatives = data is List && data.isNotEmpty && data[0] is Map
      ? (data[0] as _Json)['creatives']
      : null;
  if (creatives is! List || creatives.isEmpty) {
    fail('$id: the golden file has no data[0].creatives[0]');
  }
  return creatives[0] as _Json;
}

// MARK: - Expectations

void _check(String id, String key, dynamic value, Creative creative) {
  switch (key) {
    case 'decodes':
      expect(value, isTrue, reason: '$id: decodes is true');
    case 'metadata':
      _checkMetadata(id, value, creative.metadata);
    case 'templateKey':
      expect(creative.template?.key, equals(value), reason: '$id: templateKey');
    case 'contentKeys':
      final plain = creative.contents
          .map((c) => c.key)
          .toSet()
          .difference({'slides', matchedPointsContentKey});
      expect(plain, equals(_strings(value).toSet()),
          reason: '$id: contentKeys, got ${plain.toList()..sort()}');
    case 'contentKeysAbsent':
      for (final absent in _strings(value)) {
        expect(creative.contents.getContent(absent), isNull,
            reason: '$id: $absent is absent');
      }
    case 'clickKeys':
      expect(_keys(creative.tracking.clicks), equals(_strings(value)),
          reason: '$id: clickKeys');
    case 'customKeys':
      expect(_keys(creative.tracking.custom), equals(_strings(value)),
          reason: '$id: customKeys');
    case 'videoEventKeys':
      expect(_keys(creative.tracking.videoEvents), equals(_strings(value)),
          reason: '$id: videoEventKeys');
    case 'slides':
      _checkSlides(
          id, (value as List?)?.cast<_Json>() ?? const [], creative.slides);
    case 'noSkippableSetting':
      expect(value, isTrue, reason: '$id: noSkippableSetting is true');
      expect(creative.metadata?.isSkippable, isNull,
          reason: '$id: isSkippable is absent');
      expect(creative.metadata?.skipOffsetSeconds, isNull,
          reason: '$id: skipOffsetSeconds is absent');
    case 'matchedPoints':
      expect(creative.matchedPoints.length, equals(value),
          reason: '$id: matchedPoints count');
    default:
      fail('$id: unknown expect key $key');
  }
}

void _checkMetadata(String id, dynamic expected, Metadata? metadata) {
  if (expected is! Map) {
    fail('$id: metadata expectation is not an object');
  }
  for (final entry in expected.entries) {
    switch (entry.key) {
      case 'effectiveStandardFormatKey':
        _expectOptional(
            id, entry.key, metadata?.effectiveStandardFormatKey, entry.value);
      case 'effectiveStandardFormatVersion':
        _expectOptional(id, entry.key, metadata?.effectiveStandardFormatVersion,
            entry.value);
      case 'templateSource':
        _expectOptional(id, entry.key, metadata?.templateSource, entry.value);
      default:
        fail(
            '$id: unknown metadata expect key ${entry.key} (known: $_metadataKeys)');
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

const _slideKeys = [
  'slideId',
  'position',
  'contentKeys',
  'viewKeys',
  'clickKeys'
];

void _checkSlides(String id, List<_Json> expected, List<Slide> slides) {
  expect(slides.length, equals(expected.length),
      reason: '$id: slide count, got ${slides.length}');
  for (var i = 0; i < expected.length && i < slides.length; i++) {
    final want = expected[i];
    final slide = slides[i];
    final label = '$id: slide ${i + 1}';
    for (final key in want.keys.where((k) => !_slideKeys.contains(k))) {
      fail('$label: unknown slide expect key $key');
    }
    expect(slide.slideId, equals(want['slideId']), reason: '$label slideId');
    expect(slide.position, equals(want['position']), reason: '$label position');
    expect(slide.contents.map((c) => c.key).toSet(),
        equals(_strings(want['contentKeys']).toSet()),
        reason: '$label contentKeys');
    expect(_keys(slide.tracking?.views).toSet(),
        equals(_strings(want['viewKeys']).toSet()),
        reason: '$label viewKeys');
    expect(_keys(slide.tracking?.clicks).toSet(),
        equals(_strings(want['clickKeys']).toSet()),
        reason: '$label clickKeys');
  }
}

List<String> _keys(List<TrackingItem>? items) =>
    (items ?? const <TrackingItem>[]).map((t) => t.key).toList();

List<String> _strings(dynamic value) =>
    value is List ? value.whereType<String>().toList() : const [];
