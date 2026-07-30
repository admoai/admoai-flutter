import 'package:flutter_test/flutter_test.dart';
import 'package:admoai/admoai.dart';
import 'dart:convert';

void main() {
  group('Video Ads Model Tests', () {
    test('testVastDataDeserialization', () {
      final json = {
        'tagUrl': 'https://example.com/vast.xml',
        'xmlBase64': 'PD94bWw+PC94bWw+'
      };

      final vastData = VastData.fromJson(json);

      expect(vastData.tagUrl, equals('https://example.com/vast.xml'));
      expect(vastData.xmlBase64, equals('PD94bWw+PC94bWw+'));
    });

    test('testCreativeWithVideoFields', () {
      final json = {
        'contents': [
          {'key': 'title', 'value': 'Test Ad', 'type': 'text'},
          {'key': 'isSkippable', 'value': true, 'type': 'boolean'},
          {'key': 'skipOffset', 'value': '00:00:05', 'type': 'text'}
        ],
        'advertiser': {
          'name': 'Test Advertiser',
          'legalName': 'Test Legal',
          'logoUrl': 'https://example.com/logo.png'
        },
        'template': {'key': 'video_ad', 'style': 'fullscreen'},
        'tracking': {
          'impressions': [
            {'key': 'default', 'url': 'https://example.com/impression'}
          ],
          'videoEvents': [
            {'key': 'start', 'url': 'https://example.com/video/start'},
            {'key': 'complete', 'url': 'https://example.com/video/complete'}
          ]
        },
        'delivery': 'vast_tag',
        'vast': {
          'tagUrl': 'https://example.com/vast.xml',
          'xmlBase64': null
        }
      };

      final creative = Creative.fromJson(json);

      expect(creative.delivery, equals('vast_tag'));
      expect(creative.vast, isNotNull);
      expect(creative.vast!.tagUrl, equals('https://example.com/vast.xml'));
      expect(creative.tracking.videoEvents, isNotNull);
      expect(creative.tracking.videoEvents!.length, equals(2));
    });

    test('testTrackingWithVideoEvents', () {
      final json = {
        'impressions': [
          {'key': 'default', 'url': 'https://example.com/impression'}
        ],
        'clicks': [
          {'key': 'default', 'url': 'https://example.com/click'}
        ],
        'videoEvents': [
          {'key': 'start', 'url': 'https://example.com/video/start'},
          {'key': 'firstQuartile', 'url': 'https://example.com/video/q1'},
          {'key': 'midpoint', 'url': 'https://example.com/video/mid'},
          {'key': 'thirdQuartile', 'url': 'https://example.com/video/q3'},
          {'key': 'complete', 'url': 'https://example.com/video/complete'}
        ]
      };

      final tracking = Tracking.fromJson(json);

      expect(tracking.videoEvents, isNotNull);
      expect(tracking.videoEvents!.length, equals(5));
      expect(
          tracking.hasTrackingFor(TrackingType.videoEvent, 'start'), isTrue);
      expect(tracking.getVideoEventUrl(key: 'midpoint'),
          equals('https://example.com/video/mid'));
    });
  });

  group('Video Helper Methods Tests', () {
    late Creative vastTagCreative;
    late Creative vastXmlCreative;
    late Creative jsonCreative;

    setUp(() {
      vastTagCreative = Creative(
        contents: [
          Content(key: 'isSkippable', value: true, type: 'boolean'),
          Content(key: 'skipOffset', value: '00:00:05', type: 'text')
        ],
        advertiser: Advertiser(
            name: 'Test', legalName: 'Test Legal', logoUrl: 'https://test.com'),
        template: Template(key: 'video', style: 'fullscreen'),
        tracking: Tracking(impressions: [
          TrackingItem(key: 'default', url: 'https://example.com/impression')
        ]),
        delivery: 'vast_tag',
        vast: VastData(
            tagUrl: 'https://example.com/vast.xml', xmlBase64: null),
      );

      vastXmlCreative = Creative(
        contents: [],
        advertiser: Advertiser(
            name: 'Test', legalName: 'Test Legal', logoUrl: 'https://test.com'),
        template: Template(key: 'video', style: 'fullscreen'),
        tracking: Tracking(impressions: [
          TrackingItem(key: 'default', url: 'https://example.com/impression')
        ]),
        delivery: 'vast_xml',
        vast: VastData(
            tagUrl: null,
            xmlBase64:
                'PFZBU1Q+PE1lZGlhRmlsZSB0eXBlPSJ2aWRlby9tcDQiPnRlc3Q8L01lZGlhRmlsZT48L1ZBU1Q+'),
      );

      jsonCreative = Creative(
        contents: [],
        advertiser: Advertiser(
            name: 'Test', legalName: 'Test Legal', logoUrl: 'https://test.com'),
        template: Template(key: 'video', style: 'fullscreen'),
        tracking: Tracking(impressions: [
          TrackingItem(key: 'default', url: 'https://example.com/impression')
        ]),
        delivery: 'json',
      );
    });

    test('testDeliveryTypeDetection', () {
      expect(vastTagCreative.isVastTagDelivery(), isTrue);
      expect(vastTagCreative.isVastXmlDelivery(), isFalse);
      expect(vastTagCreative.isJsonDelivery(), isFalse);

      expect(vastXmlCreative.isVastTagDelivery(), isFalse);
      expect(vastXmlCreative.isVastXmlDelivery(), isTrue);
      expect(vastXmlCreative.isJsonDelivery(), isFalse);

      expect(jsonCreative.isVastTagDelivery(), isFalse);
      expect(jsonCreative.isVastXmlDelivery(), isFalse);
      expect(jsonCreative.isJsonDelivery(), isTrue);
    });

    test('testGetVastTagUrlWithoutParams', () {
      final url = vastTagCreative.getVastTagUrl();
      expect(url, equals('https://example.com/vast.xml'));
    });

    test('testGetVastTagUrlWithMediaType', () {
      final url = vastTagCreative.getVastTagUrl(mediaType: 'video/mp4');
      expect(url, contains('mediaType=video%2Fmp4'));
      expect(url, startsWith('https://example.com/vast.xml?'));
    });

    test('testGetVastTagUrlWithBothParams', () {
      final url = vastTagCreative.getVastTagUrl(
          mediaType: 'video/mp4', mediaDelivery: 'progressive');
      expect(url, contains('mediaType=video%2Fmp4'));
      expect(url, contains('mediaDelivery=progressive'));
      expect(url, contains('&'));
    });

    test('testGetVastTagUrlWithExistingQueryParams', () {
      final creativeWithParams = Creative(
        contents: [],
        advertiser: Advertiser(
            name: 'Test', legalName: 'Test Legal', logoUrl: 'https://test.com'),
        template: Template(key: 'video', style: 'fullscreen'),
        tracking: Tracking(impressions: [
          TrackingItem(key: 'default', url: 'https://example.com/impression')
        ]),
        delivery: 'vast_tag',
        vast: VastData(
            tagUrl: 'https://example.com/vast.xml?existing=param',
            xmlBase64: null),
      );

      final url = creativeWithParams.getVastTagUrl(mediaType: 'video/mp4');
      expect(url, contains('existing=param'));
      expect(url, contains('&mediaType=video%2Fmp4'));
    });

    test('testGetVastXmlBase64WithoutParams', () {
      final base64 = vastXmlCreative.getVastXmlBase64();
      expect(base64,
          equals('PFZBU1Q+PE1lZGlhRmlsZSB0eXBlPSJ2aWRlby9tcDQiPnRlc3Q8L01lZGlhRmlsZT48L1ZBU1Q+'));
    });

    test('testGetVastXmlBase64WithMediaType', () {
      final base64 =
          vastXmlCreative.getVastXmlBase64(mediaType: 'video/webm');
      expect(base64, isNotNull);

      final decoded = utf8.decode(base64Decode(base64!));
      expect(decoded, contains('type="video/webm"'));
    });

    test('testIsSkippable', () {
      expect(vastTagCreative.isSkippable(), isTrue);
      expect(vastXmlCreative.isSkippable(), isFalse);
    });

    test('testGetSkipOffset', () {
      expect(vastTagCreative.getSkipOffset(), equals('00:00:05'));
      expect(vastXmlCreative.getSkipOffset(), isNull);
    });
  });

  skippabilityParityTests();
}

// ───────────────────────────────────────────────────────────────────────────────
// Cross-SDK parity: skippability resolution.
//
// `isSkippable()` / `getSkipOffset()` matched the content keys `isSkippable` and
// `skipOffset` in camelCase. The platform creates template fields in snake_case,
// and a live journey video serve returns `is_skippable` / `skip_offset` — the only
// such keys in the whole template_fields table. So neither helper could ever match:
// isSkippable() always returned false and getSkipOffset() always returned null.
//
// The tests that covered them used camelCase fixtures, so they encoded the same
// wrong assumption as the code and passed throughout. Same class of defect as adhub
// #2483 (the journey click resolver matched snake_case while the platform wrote
// camelCase) — the same seam, the opposite direction.
//
// Both helpers now prefer the engine-owned metadata fields, which is the only
// source the iOS SDK reads, and accept either casing in the content fallback. The
// identical change is applied to the Android SDK, which had the same mismatch.
// ───────────────────────────────────────────────────────────────────────────────
void skippabilityParityTests() {
  Creative creativeWithContents(List<Map<String, dynamic>> contents,
          {Map<String, dynamic>? metadata}) =>
      Creative.fromJson({
        'contents': contents,
        'advertiser': const <String, dynamic>{},
        'template': const <String, dynamic>{},
        'tracking': const <String, dynamic>{},
        if (metadata != null) 'metadata': metadata,
      });

  Map<String, dynamic> baseMetadata(Map<String, dynamic> extra) => {
        'adId': 'a',
        'creativeId': 'c',
        'templateId': 't',
        'placementId': 'p',
        'priority': 'standard',
        ...extra,
      };

  group('skippability — snake_case content keys (the live engine shape)', () {
    test('is_skippable as an integer 1 is skippable', () {
      final creative = creativeWithContents([
        {'key': 'is_skippable', 'value': 1, 'type': 'integer'},
        {'key': 'skip_offset', 'value': '5', 'type': 'text'},
      ]);

      expect(creative.isSkippable(), isTrue);
      expect(creative.getSkipOffset(), equals('5'));
    });

    test('is_skippable as integer 0 is not skippable', () {
      final creative = creativeWithContents([
        {'key': 'is_skippable', 'value': 0, 'type': 'integer'},
      ]);

      expect(creative.isSkippable(), isFalse);
    });

    test('is_skippable as the string "true" is skippable', () {
      final creative = creativeWithContents([
        {'key': 'is_skippable', 'value': 'true', 'type': 'integer'},
      ]);

      expect(creative.isSkippable(), isTrue);
    });

    test('a non-numeric placeholder value is not skippable, and never throws',
        () {
      // The mock seed fills these fields with placeholder text, so the helper
      // must degrade rather than throw or guess.
      final creative = creativeWithContents([
        {'key': 'is_skippable', 'value': 'is_skippable (demo)', 'type': 'integer'},
        {'key': 'skip_offset', 'value': 'Journey Ad demo', 'type': 'text'},
      ]);

      expect(() => creative.isSkippable(), returnsNormally);
      expect(creative.isSkippable(), isFalse);
      expect(creative.getSkipOffset(), equals('Journey Ad demo'));
    });
  });

  group('skippability — camelCase content keys still work', () {
    test('isSkippable / skipOffset remain supported', () {
      final creative = creativeWithContents([
        // The real template types this field `integer`; Android's ContentType
        // enum has no `boolean` variant, so keep the two suites on one shape.
        {'key': 'isSkippable', 'value': true, 'type': 'integer'},
        {'key': 'skipOffset', 'value': '00:00:05', 'type': 'text'},
      ]);

      expect(creative.isSkippable(), isTrue);
      expect(creative.getSkipOffset(), equals('00:00:05'));
    });
  });

  group('skippability — engine metadata wins over content', () {
    test('metadata.isSkippable takes precedence', () {
      final creative = creativeWithContents(
        [
          {'key': 'is_skippable', 'value': 0, 'type': 'integer'},
        ],
        metadata: baseMetadata({'isSkippable': true}),
      );

      expect(creative.isSkippable(), isTrue);
    });

    test('metadata.skipOffsetSeconds takes precedence', () {
      final creative = creativeWithContents(
        [
          {'key': 'skip_offset', 'value': '99', 'type': 'text'},
        ],
        metadata: baseMetadata({'skipOffsetSeconds': 5}),
      );

      expect(creative.getSkipOffset(), equals('5'));
    });

    test('content is used when metadata omits the fields', () {
      final creative = creativeWithContents(
        [
          {'key': 'is_skippable', 'value': 1, 'type': 'integer'},
          {'key': 'skip_offset', 'value': '7', 'type': 'text'},
        ],
        metadata: baseMetadata(const {}),
      );

      expect(creative.isSkippable(), isTrue);
      expect(creative.getSkipOffset(), equals('7'));
    });
  });

  group('skippability — absent everywhere', () {
    test('no metadata and no content fields', () {
      final creative = creativeWithContents(const []);

      expect(creative.isSkippable(), isFalse);
      expect(creative.getSkipOffset(), isNull);
    });
  });
}
