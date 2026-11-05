import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

// Carousel slides and standard-format metadata, beyond the shared manifest
//
// Feature: A publisher's app reads a Carousel's slides and the standard format metadata
//   As a publisher's tech team
//   I want slides in server order and a decode that a malformed slide cannot break
//   So that one bad slide costs one slide, never the creative or the ad
//
// The shared fixture scenarios (fixture_scenarios_test.dart) pin the golden wire; these pin
// the tolerance rules the golden files do not exercise. Mirrors iOS SlidesDecodingTests.swift.

Creative creative({required String contents, String metadata = '{}'}) {
  final json = '''
{"success": true, "data": [{"placement": "home", "creatives": [{
    "contents": $contents, "metadata": $metadata, "advertiser": {}, "tracking": {}
}]}]}''';
  final data = jsonDecode(json)['data'] as List;
  return Decision.fromJson(data.first as Map<String, dynamic>).creatives!.first;
}

String slide(String id, int position) => '''
{"slideId": "$id", "position": $position,
 "contents": [{"key": "image", "value": "https://cdn.example/$id.png", "type": "image"}],
 "tracking": {"views": [{"key": "slide_view", "url": "https://t.example/v/$id"}],
              "clicks": [{"key": "default", "url": "https://t.example/c/$id"}]}}''';

String slides(List<String> entries) =>
    '[{"key": "slides", "type": "slides", "value": [${entries.join(',')}]}]';

void main() {
  test('a malformed slide is dropped and the order is kept', () {
    final bad = [
      '{"position": 2, "contents": []}', // no slideId
      '{"slideId": "s_bad", "position": "2"}', // mistyped position
      '{"slideId": 7, "position": 2}', // mistyped slideId
      '42', // not an object
    ];
    final result = creative(
      contents: slides([
        slide('a', 1),
        bad[0],
        slide('b', 2),
        bad[1],
        bad[2],
        bad[3],
        slide('c', 3),
      ]),
    );
    expect(result.slides.map((s) => s.slideId), ['a', 'b', 'c']);
    expect(result.slides.map((s) => s.position), [1, 2, 3]);
  });

  test('position out of order on the wire keeps the wire order', () {
    final result = creative(
      contents:
          slides([slide('third', 3), slide('first', 1), slide('second', 2)]),
    );
    expect(result.slides.map((s) => s.slideId), ['third', 'first', 'second']);
    expect(result.slides.map((s) => s.position), [3, 1, 2]);
  });

  test('a malformed slide content entry is dropped on its own', () {
    const entry = '''
{"slideId": "a", "position": 1, "contents": [
    {"key": "image", "value": "https://cdn.example/a.png", "type": "image"},
    "not an object",
    {"key": "headline", "value": "Hi", "type": "text"}
], "tracking": "nope"}''';
    final result = creative(contents: slides([entry]));
    expect(result.slides, hasLength(1));
    expect(
        result.slides.first.contents.map((c) => c.key), ['image', 'headline']);
    expect(result.slides.first.tracking, isNull,
        reason: 'a malformed tracking block is absent, not a failure');
  });

  test('the slides entry stays in contents', () {
    final result = creative(contents: slides([slide('a', 1)]));
    expect(result.contents.getContent('slides'), isNotNull);
    expect(result.slides, hasLength(1));
  });

  test('a non-carousel creative has no slides', () {
    final plain = creative(
        contents: '[{"key": "headline", "value": "Hi", "type": "text"}]');
    expect(plain.slides, isEmpty);
    final malformed = creative(
        contents: '[{"key": "slides", "type": "slides", "value": "nope"}]');
    expect(malformed.slides, isEmpty,
        reason:
            'a slides entry that is not a list yields no slides and no failure');
  });

  test('the standard format version accepts a number and nothing else', () {
    int? version(String literal) => creative(
          contents: '[]',
          metadata: '{"effectiveStandardFormatVersion": $literal}',
        ).metadata?.effectiveStandardFormatVersion;
    expect(version('1'), 1);
    expect(version('1.0'), 1);
    expect(version('"1"'), isNull);
    expect(version('null'), isNull);
  });

  test('template source is open-set and wrong types are absent', () {
    final known = creative(
        contents: '[]', metadata: '{"templateSource": "based_on_standard"}');
    expect(known.metadata?.templateSource, 'based_on_standard');
    final future = creative(
        contents: '[]', metadata: '{"templateSource": "from_the_future"}');
    expect(future.metadata?.templateSource, 'from_the_future',
        reason: 'an unknown value is kept verbatim');
    final mistyped = creative(
      contents: '[]',
      metadata: '{"templateSource": 3, "effectiveStandardFormatKey": false}',
    );
    expect(mistyped.metadata?.templateSource, isNull);
    expect(mistyped.metadata?.effectiveStandardFormatKey, isNull);
  });
}
