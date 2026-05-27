import 'package:flutter_test/flutter_test.dart';
import 'package:admoai/admoai.dart';

void main() {
  group('Metadata video fields and nullability', () {
    test('parses all video metadata fields when present', () {
      final json = {
        'adId': 'ad_1',
        'creativeId': 'cr_1',
        'advertiserId': 'adv_1',
        'templateId': 't_1',
        'placementId': 'p_1',
        'priority': 'standard',
        'language': 'en',
        'duration': 15000,
        'aspectRatio': '16:9',
        'isSkippable': true,
        'format': 'video',
        'style': 'fullscreen',
      };

      final metadata = Metadata.fromJson(json);
      expect(metadata.duration, equals(15000));
      expect(metadata.aspectRatio, equals('16:9'));
      expect(metadata.isSkippable, isTrue);
      expect(metadata.format, equals('video'));
      expect(metadata.style, equals('fullscreen'));
    });

    test('video metadata fields are null when absent (backward compatible)',
        () {
      final json = {
        'adId': 'ad_1',
        'creativeId': 'cr_1',
        'advertiserId': 'adv_1',
        'templateId': 't_1',
        'placementId': 'p_1',
        'priority': 'standard',
        'language': 'en',
      };

      final metadata = Metadata.fromJson(json);
      expect(metadata.duration, isNull);
      expect(metadata.aspectRatio, isNull);
      expect(metadata.isSkippable, isNull);
      expect(metadata.format, isNull);
      expect(metadata.style, isNull);
    });

    test('Metadata.advertiserId is nullable', () {
      final json = {
        'adId': 'ad_1',
        'creativeId': 'cr_1',
        'templateId': 't_1',
        'placementId': 'p_1',
        'priority': 'standard',
      };

      final metadata = Metadata.fromJson(json);
      expect(metadata.advertiserId, isNull);
    });

    test('Metadata.language is nullable', () {
      final json = {
        'adId': 'ad_1',
        'creativeId': 'cr_1',
        'advertiserId': 'adv_1',
        'templateId': 't_1',
        'placementId': 'p_1',
        'priority': 'standard',
      };

      final metadata = Metadata.fromJson(json);
      expect(metadata.language, isNull);
    });

    test('isSkippable is a true bool', () {
      final json = {
        'adId': 'ad_1',
        'creativeId': 'cr_1',
        'advertiserId': 'adv_1',
        'templateId': 't_1',
        'placementId': 'p_1',
        'priority': 'standard',
        'language': 'en',
        'isSkippable': false,
      };

      final metadata = Metadata.fromJson(json);
      expect(metadata.isSkippable, isA<bool>());
      expect(metadata.isSkippable, isFalse);
    });
  });

  group('Advertiser.id', () {
    test('Advertiser.id parses when present', () {
      final json = {
        'id': 'adv_123',
        'name': 'ACME',
        'legalName': 'ACME Ltd',
        'logoUrl': 'https://example.com/logo.png',
      };
      final advertiser = Advertiser.fromJson(json);
      expect(advertiser.id, equals('adv_123'));
      expect(advertiser.name, equals('ACME'));
    });

    test('Advertiser.id is null when absent', () {
      final json = {
        'name': 'ACME',
        'legalName': 'ACME Ltd',
        'logoUrl': 'https://example.com/logo.png',
      };
      final advertiser = Advertiser.fromJson(json);
      expect(advertiser.id, isNull);
      expect(advertiser.name, equals('ACME'));
    });
  });

  group('Advertiser nullability (crash-bug fix)', () {
    test('Advertiser parses with only name set (no legalName/logoUrl)', () {
      final advertiser = Advertiser.fromJson({'name': 'ACME'});
      expect(advertiser.name, equals('ACME'));
      expect(advertiser.legalName, isNull);
      expect(advertiser.logoUrl, isNull);
    });

    test('Advertiser parses with empty object', () {
      final advertiser = Advertiser.fromJson({});
      expect(advertiser.id, isNull);
      expect(advertiser.name, isNull);
      expect(advertiser.legalName, isNull);
      expect(advertiser.logoUrl, isNull);
    });
  });

  group('Template.style nullability (crash-bug fix)', () {
    test('Template parses with only key', () {
      final template = Template.fromJson({'key': 'wide'});
      expect(template.key, equals('wide'));
      expect(template.style, isNull);
    });

    test('Template parses with key and style', () {
      final template = Template.fromJson({'key': 'wide', 'style': 'imageLeft'});
      expect(template.key, equals('wide'));
      expect(template.style, equals('imageLeft'));
    });
  });

  group('Tracking.impressions nullability (crash-bug fix)', () {
    test('Tracking parses without impressions', () {
      final tracking = Tracking.fromJson({
        'clicks': [
          {'key': 'default', 'url': 'https://example.com/click'}
        ]
      });
      expect(tracking.impressions, isNull);
      expect(tracking.clicks?.length, equals(1));
    });

    test('hasTrackingFor handles null impressions gracefully', () {
      final tracking = Tracking.fromJson({});
      expect(
          tracking.hasTrackingFor(TrackingType.impression, 'default'), isFalse);
      expect(tracking.hasTrackingFor(TrackingType.click, 'default'), isFalse);
      expect(tracking.hasTrackingFor(TrackingType.custom, 'k'), isFalse);
      expect(tracking.hasTrackingFor(TrackingType.videoEvent, 'start'), isFalse);
    });

    test('Tracking with empty object does not throw', () {
      expect(() => Tracking.fromJson({}), returnsNormally);
    });
  });

  group('Content/Tracking lookup helpers return null instead of throwing', () {
    test('getContent returns null for unknown key', () {
      final contents = [
        Content(key: 'headline', value: 'a', type: 'text'),
        Content(key: 'body', value: 'b', type: 'text'),
      ];
      expect(contents.getContent('cta'), isNull);
    });

    test('getContent returns the entry when present', () {
      final contents = [
        Content(key: 'headline', value: 'a', type: 'text'),
      ];
      final found = contents.getContent('headline');
      expect(found, isNotNull);
      expect(found!.value, equals('a'));
    });

    test('getImpressionUrl returns null for unknown key', () {
      final tracking = Tracking.fromJson({
        'impressions': [
          {'key': 'default', 'url': 'https://example.com/imp'}
        ]
      });
      expect(tracking.getImpressionUrl(key: 'viewable'), isNull);
      expect(tracking.getImpressionUrl(key: 'default'),
          equals('https://example.com/imp'));
    });

    test('getClickUrl returns null for unknown key', () {
      final tracking = Tracking.fromJson({
        'clicks': [
          {'key': 'default', 'url': 'https://example.com/click'}
        ]
      });
      expect(tracking.getClickUrl(key: 'cta'), isNull);
    });

    test('getCustomUrl returns null for unknown key', () {
      final tracking = Tracking.fromJson({
        'custom': [
          {'key': 'foo', 'url': 'https://example.com/foo'}
        ]
      });
      expect(tracking.getCustomUrl(key: 'bar'), isNull);
    });

    test('getVideoEventUrl returns null for unknown key', () {
      final tracking = Tracking.fromJson({
        'videoEvents': [
          {'key': 'start', 'url': 'https://example.com/start'}
        ]
      });
      expect(tracking.getVideoEventUrl(key: 'midpoint'), isNull);
    });

    test('all URL helpers return null when their list is null', () {
      final tracking = Tracking.fromJson({});
      expect(tracking.getImpressionUrl(key: 'default'), isNull);
      expect(tracking.getClickUrl(key: 'default'), isNull);
      expect(tracking.getCustomUrl(key: 'foo'), isNull);
      expect(tracking.getVideoEventUrl(key: 'start'), isNull);
    });
  });
}
