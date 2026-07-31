import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

/// #41 — the whole response shell is a Tolerant Reader: missing, extra, and
/// retyped fields never throw; malformed list entries are dropped; currently
/// non-null fields fall back to safe defaults ('' / empty) rather than
/// widening the public API to nullable.
void main() {
  group('Creative shell tolerance', () {
    test('missing advertiser / template / tracking / contents → defaults', () {
      late Creative c;
      expect(() {
        c = Creative.fromJson({}); // nothing at all
      }, returnsNormally);

      expect(c.contents, isEmpty);
      expect(c.advertiser.name, isNull);
      expect(c.template, isNull); // absent/malformed template is null, matching iOS and Android
      expect(c.tracking.impressions, isNull);
      expect(c.metadata, isNull);
      expect(c.vast, isNull);
      expect(c.verificationScriptResources, isNull);
      expect(c.isJourneyAd(), isFalse);
    });

    test('retyped blocks (advertiser/template/tracking as non-map) → defaults',
        () {
      late Creative c;
      expect(() {
        c = Creative.fromJson({
          'advertiser': 'nope',
          'template': 42,
          'tracking': ['not', 'a', 'map'],
          'contents': 'not-a-list',
          'metadata': 7,
          'vast': 'x',
        });
      }, returnsNormally);
      expect(c.contents, isEmpty);
      expect(c.template, isNull); // absent/malformed template is null, matching iOS and Android
      expect(c.metadata, isNull);
      expect(c.vast, isNull);
    });

    test('malformed content entries are dropped', () {
      final c = Creative.fromJson({
        'contents': [
          {'key': 'headline', 'value': 'Hi', 'type': 'text'}, // valid
          {'key': 'no_type', 'value': 'x'}, // missing type → dropped
          {'type': 'text'}, // missing key → dropped
          {'key': 1, 'type': 2}, // retyped → dropped
          'not-a-map', // → dropped
          42, // → dropped
        ],
        'advertiser': {'name': 'Acme'},
        'template': {'key': 'native'},
        'tracking': {},
      });
      expect(c.contents.length, equals(1));
      expect(c.contents.getContent('headline')?.value, equals('Hi'));
    });

    test('malformed verification entries are dropped', () {
      final c = Creative.fromJson({
        'contents': [],
        'advertiser': {},
        'template': {'key': 't'},
        'tracking': {},
        'verificationScriptResources': [
          {'vendorKey': 'ias', 'scriptUrl': 'https://ias/x.js'}, // valid
          {'vendorKey': 'no_url'}, // missing scriptUrl → dropped
          {'scriptUrl': 'https://x'}, // missing vendorKey → dropped
          'nope', // → dropped
        ],
      });
      expect(c.verificationScriptResources!.length, equals(1));
      expect(c.verificationScriptResources!.first.vendorKey, equals('ias'));
    });
  });

  group('Metadata tolerance', () {
    test('missing required id fields default to empty string (non-breaking)',
        () {
      late Metadata m;
      expect(() => m = Metadata.fromJson({}), returnsNormally);
      expect(m.adId, equals(''));
      expect(m.creativeId, equals(''));
      expect(m.templateId, equals(''));
      expect(m.placementId, equals(''));
      expect(m.priority, equals(Priority.unknown));
      expect(m.advertiserId, isNull);
      expect(m.duration, isNull);
    });

    test('retyped fields degrade without throwing', () {
      late Metadata m;
      expect(() {
        m = Metadata.fromJson({
          'adId': 123, // retyped → ''
          'duration': '15', // retyped string → null
          'isSkippable': 'yes', // retyped → null
          'aspectRatio': 5, // retyped → null
        });
      }, returnsNormally);
      expect(m.adId, equals(''));
      expect(m.duration, isNull);
      expect(m.isSkippable, isNull);
      expect(m.aspectRatio, isNull);
    });

    test('duration accepts num and coerces to int', () {
      final m = Metadata.fromJson({'duration': 15000.0});
      expect(m.duration, equals(15000));
    });
  });

  group('Decision tolerance', () {
    test('missing placement → empty string, not a throw', () {
      final d = Decision.fromJson({'creatives': null});
      expect(d.placement, equals(''));
      expect(d.isNoAd, isTrue);
    });

    test('creatives not a list → null (no throw)', () {
      final d = Decision.fromJson({'placement': 'p', 'creatives': 'nope'});
      expect(d.creatives, isNull);
    });

    test('non-object creative entries are skipped', () {
      final d = Decision.fromJson({
        'placement': 'p',
        'creatives': [
          'not-a-map',
          42,
          {
            'contents': [],
            'advertiser': {},
            'template': {'key': 't'},
            'tracking': {},
          },
        ],
      });
      expect(d.creatives!.length, equals(1));
    });
  });

  group('Advertiser / Template / VastData retype safety', () {
    test('retyped advertiser/template/vast fields → null / default', () {
      final adv = Advertiser.fromJson({'id': 1, 'name': true});
      expect(adv.id, isNull);
      expect(adv.name, isNull);

      final tpl = Template.fromJson({'key': 9, 'style': 3});
      expect(tpl.key, equals(''));
      expect(tpl.style, isNull);

      final vast = VastData.fromJson({'tagUrl': 1, 'xmlBase64': 2});
      expect(vast.tagUrl, isNull);
      expect(vast.xmlBase64, isNull);
    });
  });
}
