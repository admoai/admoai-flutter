import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

// Cross-SDK parity regression guards.
//
// Each group here pins a behaviour where this SDK was found to diverge from the
// Android reference implementation during the Journey Ads parity review. They
// are deliberately kept together rather than spread across the topical suites:
// the value of a parity guard is that it names the divergence it prevents from
// coming back.
//
// Fully offline — MockClient only, no network.

const baseUrl = 'https://mock.api.admoai.com';

Creative creativeWith({
  Object? journey = _absent,
  Map<String, dynamic>? tracking,
}) {
  return Creative.fromJson({
    'contents': [
      {'key': 'headline', 'value': 'x', 'type': 'text'}
    ],
    'advertiser': {'name': 'Acme'},
    'template': {'key': 'native'},
    'tracking': tracking ??
        {
          'impressions': [
            {'key': 'default', 'url': 'https://t.example/v1/tracking?e=imp'}
          ],
        },
    if (journey != _absent) 'journey': journey,
  });
}

const _absent = Object();

/// Collects log records so a test can assert on the SDK's warnings.
({Logger logger, List<LogRecord> records}) capturingLogger(String name) {
  final records = <LogRecord>[];
  final logger = Logger(name)
    ..level = Level.ALL
    ..onRecord.listen(records.add);
  return (logger: logger, records: records);
}

Iterable<LogRecord> warningsMatching(List<LogRecord> records, String needle) =>
    records.where(
        (r) => r.level >= Level.WARNING && r.message.contains(needle));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  hierarchicalLoggingEnabled = true;

  setUp(() {
    const MethodChannel channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getLocalTimezone') return 'UTC';
      return null;
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // D1 — isJourneyAd() must key off a real server-issued identifier.
  //
  // The Tolerant Reader decodes `"journey": {}` into a non-null CreativeJourney
  // with every field null. A `journey != null` check reports such a creative as
  // a Journey serve while every accessor returns null, so a normal ad becomes
  // indistinguishable from a Journey ad — breaking the P2 contract ("on a normal
  // ad, all journey metadata is null/false"). Android guards this explicitly.
  // ───────────────────────────────────────────────────────────────────────────
  group('D1: isJourneyAd requires a real dealId or instanceId', () {
    test('empty journey block is NOT a journey ad', () {
      final creative = creativeWith(journey: <String, dynamic>{});

      expect(creative.isJourneyAd(), isFalse);
      // And the P2 contract holds across the whole accessor set.
      expect(creative.journeyDealId, isNull);
      expect(creative.journeyInstanceId, isNull);
      expect(creative.journeyDefinitionKey, isNull);
      expect(creative.journeyStageId, isNull);
      expect(creative.journeyStageKey, isNull);
      expect(creative.journeyStageNodeId, isNull);
      expect(creative.journeySessionId, isNull);
      expect(creative.journeyOptStatus, isNull);
      expect(creative.journeyPricingModel, isNull);
      expect(creative.journeyFallbackBillingMode, isNull);
      expect(creative.isJourneyCompletion, isFalse);
      expect(creative.hasCompletionUrl, isFalse);
    });

    test('journey block with every field retyped is NOT a journey ad', () {
      final creative = creativeWith(journey: {
        'dealId': 42,
        'instanceId': false,
        'definitionKey': <String>[],
        'stageKey': {'nested': true},
      });

      expect(creative.isJourneyAd(), isFalse);
      expect(creative.journeyDealId, isNull);
      expect(creative.journeyInstanceId, isNull);
    });

    test('blank-string identifiers are NOT a journey ad', () {
      final creative =
          creativeWith(journey: {'dealId': '   ', 'instanceId': ''});

      expect(creative.isJourneyAd(), isFalse);
    });

    test('a dealId alone is enough to be a journey ad', () {
      expect(creativeWith(journey: {'dealId': 'jad_1'}).isJourneyAd(), isTrue);
    });

    test('an instanceId alone is enough to be a journey ad', () {
      expect(
        creativeWith(journey: {'instanceId': 'jinst_1'}).isJourneyAd(),
        isTrue,
      );
    });

    test('no journey block at all is NOT a journey ad', () {
      expect(creativeWith().isJourneyAd(), isFalse);
    });

    test('a journey block that is not a map is NOT a journey ad', () {
      expect(creativeWith(journey: 'nope').isJourneyAd(), isFalse);
    });

    test('a real journey serve is a journey ad with metadata intact', () {
      final creative = creativeWith(journey: {
        'dealId': 'jad_01K',
        'instanceId': 'jinst_01K',
        'definitionKey': 'ride_hailing_journey',
        'stageKey': 'pre_ride',
        'optStatus': 'in',
        'pricingModel': 'cpt',
        'fallbackBillingMode': 'bill_per_stage',
      });

      expect(creative.isJourneyAd(), isTrue);
      expect(creative.journeyDefinitionKey, equals('ride_hailing_journey'));
      expect(creative.journeyStageKey, equals('pre_ride'));
      expect(creative.journeyOptStatus, equals(JourneyOpt.optIn));
      expect(creative.journeyPricingModel, equals('cpt'));
      expect(creative.journeyFallbackBillingMode, equals('bill_per_stage'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // D2 — firing a completion without an apiVersion is billing-critical.
  //
  // /v1/tracking version-routes on X-Tracking-Version (derived from apiVersion).
  // With none, the callback hits the legacy handler and the completion is not
  // recorded, so CPT revenue is silently lost while the fire looks successful.
  // ───────────────────────────────────────────────────────────────────────────
  group('D2: fireCompletion warns when apiVersion is null', () {
    Tracking completionTracking() => Tracking.fromJson({
          'completions': [
            {'key': 'journey_complete', 'url': 'https://t.example/v1/tracking?e=cmp'}
          ],
        });

    test('warns and still fires when apiVersion is null', () async {
      final log = capturingLogger('d2-null-version');
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, logger: log.logger),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      sdk.fireCompletion(completionTracking(), key: 'journey_complete');
      await Future.delayed(Duration.zero);

      // The beacon is still fired — the publisher asked for it, and a
      // best-effort attempt beats dropping it silently.
      expect(fired, equals(['https://t.example/v1/tracking?e=cmp']));
      expect(warningsMatching(log.records, 'may not record'), isNotEmpty);
    });

    test('does not warn when apiVersion is set', () async {
      final log = capturingLogger('d2-with-version');
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(
            baseUrl: baseUrl, apiVersion: '2025-11-01', logger: log.logger),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      sdk.fireCompletion(completionTracking(), key: 'journey_complete');
      await Future.delayed(Duration.zero);

      expect(fired, hasLength(1));
      expect(log.records.where((r) => r.level >= Level.WARNING), isEmpty);
    });

    test('no completions at all stays quiet (final_stage deals)', () async {
      final log = capturingLogger('d2-no-completions');
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, logger: log.logger),
        httpClient: MockClient((r) async => http.Response('', 200)),
      );

      sdk.fireCompletion(Tracking.fromJson({}), key: 'journey_complete');
      await Future.delayed(Duration.zero);

      expect(log.records.where((r) => r.level >= Level.WARNING), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // D3 — Journey context with no apiVersion is silently ignored by the engine.
  //
  // The engine version-routes on X-Decision-Version; without it, sessionId and
  // journeyOpt are dropped and normal ads are served with no error. The failure
  // is invisible, so the SDK warns. Android does this in its request-prepare
  // step; the equivalent here covers both request entry points.
  // ───────────────────────────────────────────────────────────────────────────
  group('D3: journey context without apiVersion warns', () {
    const okBody = '{"success":true,"data":[]}';
    const needle = 'Journey will be ignored';

    AdMoai sdkWith(Logger logger, {String? apiVersion}) => AdMoai.forTesting(
          config: SDKConfig(
              baseUrl: baseUrl, apiVersion: apiVersion, logger: logger),
          httpClient: MockClient((r) async => http.Response(okBody, 200)),
        );

    test('requestAds with a sessionId warns', () async {
      final log = capturingLogger('d3-requestads');
      final sdk = sdkWith(log.logger);

      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setSessionId('trip_abc')
          .build();
      await sdk.requestAds(request);

      expect(warningsMatching(log.records, needle), isNotEmpty);
    });

    test('getHttpRequest with journeyOpt only warns', () {
      final log = capturingLogger('d3-gethttp');
      final sdk = sdkWith(log.logger);

      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setJourneyOpt(JourneyOpt.optOut)
          .build();
      sdk.getHttpRequest(request);

      expect(warningsMatching(log.records, needle), isNotEmpty);
    });

    test('no warning when apiVersion is set', () async {
      final log = capturingLogger('d3-versioned');
      final sdk = sdkWith(log.logger, apiVersion: '2025-11-01');

      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setSessionId('trip_abc')
          .setJourneyOpt(JourneyOpt.optIn)
          .build();
      await sdk.requestAds(request);

      expect(warningsMatching(log.records, needle), isEmpty);
    });

    test('no warning for a request carrying no journey context', () async {
      final log = capturingLogger('d3-no-journey');
      final sdk = sdkWith(log.logger);

      final request =
          sdk.createRequestBuilder().addPlacement(key: 'home').build();
      await sdk.requestAds(request);

      expect(warningsMatching(log.records, needle), isEmpty);
    });

    test('a blank sessionId is not journey context, so it does not warn',
        () async {
      final log = capturingLogger('d3-blank-session');
      final sdk = sdkWith(log.logger);

      // Blank-after-trim never reaches the wire, so there is no journey context
      // to be ignored. (setSessionId separately warns that it disables Journey.)
      final request = DecisionRequest(
        placements: [Placement(key: 'home')],
        sessionId: '   ',
      );
      await sdk.requestAds(request);

      expect(warningsMatching(log.records, needle), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // D4 — the tracking-URL guard must require an absolute http(s) URL with a
  // host. `hasScheme` alone admitted mailto:/file:/ftp: and hostless strings.
  // ───────────────────────────────────────────────────────────────────────────
  group('D4: fireTracking requires an absolute http(s) URL with a host', () {
    test('rejects non-http(s) schemes and hostless URLs', () async {
      final log = capturingLogger('d4-reject');
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, logger: log.logger),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      const rejected = [
        'mailto:ops@admoai.com',
        'file:///etc/passwd',
        'ftp://files.example/v1/tracking?e=tok',
        'javascript:alert(1)',
        'https://', // scheme but no host
        'http:///v1/tracking?e=tok', // empty authority
        '/v1/tracking?e=tok', // relative
        '::::',
        '',
      ];
      for (final url in rejected) {
        expect(() => sdk.fireTracking(url), returnsNormally, reason: url);
      }
      await Future.delayed(Duration.zero);

      expect(fired, isEmpty);
      expect(
        log.records.where((r) => r.level >= Level.WARNING),
        hasLength(rejected.length),
      );
    });

    test('accepts http and https with a host', () async {
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      // http is accepted deliberately: the local engine serves plaintext.
      sdk.fireTracking('http://127.0.0.1:8080/v1/tracking?e=tok');
      sdk.fireTracking('https://track.admoai.com/v1/tracking?e=tok');
      await Future.delayed(Duration.zero);

      expect(fired, hasLength(2));
    });

    test('the rejection warning never leaks the URL (it carries a PII token)',
        () async {
      final log = capturingLogger('d4-pii');
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, logger: log.logger),
        httpClient: MockClient((r) async => http.Response('', 200)),
      );

      const secret = 'mailto:ops@admoai.com?e=SUPERSECRETTOKEN';
      sdk.fireTracking(secret);

      final warnings =
          log.records.where((r) => r.level >= Level.WARNING).toList();
      expect(warnings, hasLength(1));
      expect(warnings.single.message, isNot(contains('SUPERSECRETTOKEN')));
      expect(warnings.single.message, isNot(contains(secret)));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // D5 — firing goes through Uri, so pin what that does to a beacon.
  //
  // Engine-minted `?e=` tokens are base64url (unreserved characters only), which
  // Dart's Uri round-trips byte-for-byte. The one transformation Uri does apply
  // is uppercasing percent-escape hex digits — RFC 3986 calls that a
  // semantically equivalent normalization, and it cannot reach a token that
  // contains no '%'. These tests pin both halves so a future change to the token
  // format cannot quietly start mutating beacons.
  // ───────────────────────────────────────────────────────────────────────────
  group('D5: Uri-based firing preserves engine tokens byte-for-byte', () {
    // Shape taken from a live engine serve: base64url alphabet, no padding.
    const realToken =
        'CVUyo_WnIxmqjUBnD6vutlsgtzEopdm5P1pI-1XXpYZ_UqrjTO8ELYLQWJ5nM0pdlddo'
        'sJq0QXeZjwFx776ffRxz9RyERl4vRS8sZQvRvOW-ShBP5';
    const realUrl = 'https://127.0.0.1:8080/v1/tracking?e=$realToken';

    test('an engine-shaped token fires byte-identical', () async {
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      sdk.fireTracking(realUrl);
      await Future.delayed(Duration.zero);

      expect(fired, equals([realUrl]));
    });

    test('a retry re-fires the identical string', () async {
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 500);
        }),
      );

      sdk.fireTracking(realUrl);
      await Future.delayed(Duration.zero);
      sdk.fireTracking(realUrl);
      await Future.delayed(Duration.zero);

      expect(fired, equals([realUrl, realUrl]));
      expect(fired[0], equals(fired[1]));
    });

    test('engine tokens use the base64url alphabet, so no escape to normalize',
        () {
      // The guard that makes the normalization below unreachable in practice.
      expect(realToken, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(realUrl, isNot(contains('%')));
    });

    test('percent-escape hex is uppercased (RFC 3986 equivalent), value intact',
        () async {
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      const lower = 'https://t.example/v1/tracking?e=aB9%2fXyz%3d';
      sdk.fireTracking(lower);
      await Future.delayed(Duration.zero);

      // Documented, deliberate: hex digits are uppercased...
      expect(fired.single, equals('https://t.example/v1/tracking?e=aB9%2FXyz%3D'));
      // ...and the token's decoded value is unchanged, which is what the engine
      // reads. Nothing is added, dropped, or reordered.
      expect(
        Uri.parse(fired.single).queryParameters['e'],
        equals(Uri.parse(lower).queryParameters['e']),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // R1 — the version header is a hard gate: without it the engine silently
  // ignores journey fields. Asserted on the live request path, not just the
  // tracking path.
  // ───────────────────────────────────────────────────────────────────────────
  group('R1: a journey decision request carries X-Decision-Version', () {
    test('header is present on the wire alongside the journey fields', () async {
      http.Request? captured;
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async {
          captured = r;
          return http.Response('{"success":true,"data":[]}', 200);
        }),
      );

      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'vehicleSelection')
          .setSessionId('trip_abc')
          .setJourneyOpt(JourneyOpt.optIn)
          .build();
      await sdk.requestAds(request);

      expect(captured, isNotNull);
      expect(captured!.headers['X-Decision-Version'], equals('2025-11-01'));
      expect(captured!.body, contains('"sessionId":"trip_abc"'));
      expect(captured!.body, contains('"journeyOpt":"in"'));
    });

    test('getHttpRequest exposes the same header for inspection', () {
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async => http.Response('', 200)),
      );

      final http0 = sdk.getHttpRequest(sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setSessionId('trip_abc')
          .build());

      expect(http0.headers?['X-Decision-Version'], equals('2025-11-01'));
      expect(http0.path, equals('/v1/decision'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Naming parity: fireCustomEvent is canonical, fireCustom forwards to it.
  // ───────────────────────────────────────────────────────────────────────────
  group('fireCustomEvent / fireCustom parity', () {
    Tracking customTracking() => Tracking.fromJson({
          'custom': [
            {'key': 'companionOpened', 'url': 'https://t.example/v1/tracking?e=c'}
          ],
        });

    test('both names fire the same URL', () async {
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      sdk.fireCustomEvent(customTracking(), 'companionOpened');
      await Future.delayed(Duration.zero);
      // ignore: deprecated_member_use_from_same_package
      sdk.fireCustom(customTracking(), 'companionOpened');
      await Future.delayed(Duration.zero);

      expect(fired, hasLength(2));
      expect(fired[0], equals(fired[1]));
    });

    test('an unknown custom key fires nothing', () async {
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      sdk.fireCustomEvent(customTracking(), 'nope');
      await Future.delayed(Duration.zero);

      expect(fired, isEmpty);
    });
  });
}
