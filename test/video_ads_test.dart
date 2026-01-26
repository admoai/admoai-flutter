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
}
