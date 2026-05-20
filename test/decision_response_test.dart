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
}
