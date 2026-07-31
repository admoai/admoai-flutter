import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wave 3 cross-SDK parity guards (F10–F18).
///
/// Each group pins one divergence found by walking the engine contract against all three SDKs.
/// Reverting the corresponding fix must make its group fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdMoai sdk;

  setUp(() {
    sdk = AdMoai.forTesting(
      config: SDKConfig(baseUrl: 'https://mock.api.admoai.com', apiVersion: '2025-11-01'),
    );
  });

  group('F10 — a request with no placements fails locally', () {
    test('build() throws instead of producing an empty-placements request', () {
      // The engine answers this with a 422 every time, so spending a network round-trip to learn
      // it is waste. Android throws AdMoaiConfigurationException from build(); this matches.
      expect(sdk.createRequestBuilder().build, throwsA(isA<ArgumentError>()));
    });

    test('a request with a placement still builds', () {
      final request = sdk.createRequestBuilder().addPlacement(key: 'home').build();
      expect(request.placements.single.key, equals('home'));
    });
  });

  group('F11 — bulk destination setter validates minConfidence', () {
    test('setDestinationTargeting rejects an out-of-range value', () {
      // addDestinationTargeting already validated; the bulk setter did not, so the same bad value
      // threw on iOS and Android and was silently sent from Flutter.
      expect(
        () => sdk.createRequestBuilder().setDestinationTargeting([
          Destination(latitude: 0, longitude: 0, minConfidence: 1.5),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('boundary values 0.0 and 1.0 are accepted', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setDestinationTargeting([
            Destination(latitude: 1, longitude: 2, minConfidence: 0.0),
            Destination(latitude: 3, longitude: 4, minConfidence: 1.0),
          ])
          .build();
      expect(request.targeting?.destination?.length, equals(2));
    });
  });

  group('F12 — geo targeting deduplicates', () {
    test('a repeated geoname appears once, in first-seen order', () {
      // Location, destination and custom were already deduped; geo was not, so identical input
      // produced a different body on Android (which dedupes) than here. Geo is ANY, so duplicates
      // never changed a decision — but the payload should not differ by platform.
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .addGeoTargeting(5128581)
          .addGeoTargeting(2643743)
          .addGeoTargeting(5128581)
          .build();

      expect(request.targeting?.geo, equals([5128581, 2643743]));
    });
  });

  group('F14 — template is nullable', () {
    test('an absent template block yields null, not an empty-keyed Template', () {
      // Was non-nullable and defaulted to Template(key: ''), so `creative.template == null` —
      // the natural guard, and the one that works on iOS and Android — never fired, and a
      // publisher rendered against an empty key instead.
      final creative = Creative.fromJson({
        'contents': [],
        'advertiser': {},
        'tracking': {},
      });
      expect(creative.template, isNull);
    });

    test('a present template still parses', () {
      final creative = Creative.fromJson({
        'contents': [],
        'advertiser': {},
        'tracking': {},
        'template': {'key': 'wide', 'style': 'imageLeft'},
      });
      expect(creative.template?.key, equals('wide'));
      expect(creative.template?.style, equals('imageLeft'));
    });
  });

  group('F17 — priority is a typed enum', () {
    Metadata parse(Object? priority) => Metadata.fromJson({
          'adId': 'a',
          'creativeId': 'c',
          'templateId': 't',
          'placementId': 'p',
          if (priority != null) 'priority': priority,
        });

    test('known tiers decode to their enum case', () {
      expect(parse('sponsorship').priority, equals(Priority.sponsorship));
      expect(parse('standard').priority, equals(Priority.standard));
      expect(parse('house').priority, equals(Priority.house));
    });

    test('an unknown or absent tier decodes to unknown, never throwing', () {
      // iOS and Android both fall back to an `unknown` case; Flutter exposed a raw String, so
      // branching on priority meant hardcoding literals here only.
      expect(parse('platinum').priority, equals(Priority.unknown));
      expect(parse(null).priority, equals(Priority.unknown));
      expect(parse(42).priority, equals(Priority.unknown));
    });
  });

  group('F18 — optStatus parsing tolerates case and whitespace', () {
    test('case and surrounding whitespace are normalized', () {
      // Android trims and lowercases; Flutter matched exactly, so "In" parsed on one platform and
      // null on another. Today's engine only emits lowercase, so this is defensive — but a read
      // path that disagrees across SDKs is a parity seam either way.
      expect(JourneyOpt.fromWire('in'), equals(JourneyOpt.optIn));
      expect(JourneyOpt.fromWire('IN'), equals(JourneyOpt.optIn));
      expect(JourneyOpt.fromWire('  Out  '), equals(JourneyOpt.optOut));
    });

    test('an unknown value stays null and does not drop the Journey block', () {
      expect(JourneyOpt.fromWire('sideways'), isNull);
      expect(JourneyOpt.fromWire(null), isNull);

      final creative = Creative.fromJson({
        'contents': [],
        'advertiser': {},
        'tracking': {},
        'journey': {'dealId': 'jad_1', 'instanceId': 'jinst_1', 'optStatus': 'sideways'},
      });
      expect(creative.journeyOptStatus, isNull);
      expect(creative.journeyDealId, equals('jad_1'));
    });
  });
}
