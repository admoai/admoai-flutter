import 'package:admoai/admoai.dart';
import 'package:admoai/src/third_party_tracker_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

/// Third-party Event Trackers — tolerant model + credential-isolated fan-out
/// (mission E06).
///
/// Spec: adhub `features/third-party-trackers/specs/E06-sdk.md` — the parity
/// matrix (§A model, §B impression fan-out, §C click fan-out, §D dedupe+limit,
/// §E dispatcher isolation, §F sanitized logging). Test names reference matrix
/// numbers. Mirrors the iOS reference suite (`ThirdPartyTrackerTests.swift`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ThirdPartyTracker tracker({
    String id = 'tpt_01ARZ3NDEKTSV4RRFFQ69G5FAV',
    String eventType = 'impression',
    String? matchType,
    String? eventKey,
    String url = 'https://agency.example/imp',
  }) =>
      ThirdPartyTracker(
        trackerId: id,
        eventType: eventType,
        matchType: matchType,
        eventKey: eventKey,
        url: url,
      );

  /// Canonical impression + clicks on "default"/"cta_tap" plus [trackers].
  Tracking trackingWith(List<ThirdPartyTracker>? trackers) => Tracking(
        impressions: [
          TrackingItem(key: 'default', url: 'https://mock.api.admoai.com/v1/t/imp'),
        ],
        clicks: [
          TrackingItem(key: 'default', url: 'https://mock.api.admoai.com/v1/t/click'),
          TrackingItem(key: 'cta_tap', url: 'https://mock.api.admoai.com/v1/t/click-cta'),
        ],
        thirdPartyTrackers: trackers,
      );

  /// A capturing MockClient plus the SDK wired to it (canonical + dispatcher).
  Future<(AdMoai, List<http.Request>)> sdkWithCapture() async {
    final captured = <http.Request>[];
    final client = MockClient((request) async {
      captured.add(request);
      return http.Response('', 200);
    });
    final sdk = AdMoai.forTesting(
      config: SDKConfig(
        baseUrl: 'https://mock.api.admoai.com',
        apiVersion: '2025-11-01',
        defaultLanguage: 'en',
      ),
      httpClient: client,
    );
    return (sdk, captured);
  }

  /// The unawaited fire-and-forget futures need event-loop turns to complete.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> agencyUrls(List<http.Request> captured) => captured
      .where((r) => r.url.host.endsWith('agency.example'))
      .map((r) => r.url.toString())
      .toList();

  group('§A model / decoding', () {
    test('A1 A2 - absent or null field decodes to null; helpers unaffected', () {
      final absent = Tracking.fromJson({
        'impressions': [
          {'key': 'default', 'url': 'https://t/imp'}
        ]
      });
      expect(absent.thirdPartyTrackers, isNull);
      expect(absent.getImpressionUrl(), 'https://t/imp');

      final explicitNull = Tracking.fromJson({'thirdPartyTrackers': null});
      expect(explicitNull.thirdPartyTrackers, isNull);
    });

    test('A3 A12 - impression entry decodes verbatim (macros, query order)', () {
      const rawUrl = 'https://Agency.example/Track?b=2&a=1&cb=%%CACHEBUSTER%%&x=a%20b';
      final tracking = Tracking.fromJson({
        'thirdPartyTrackers': [
          {
            'trackerId': 'tpt_01ARZ3NDEKTSV4RRFFQ69G5FAV',
            'eventType': 'impression',
            'url': rawUrl,
          }
        ]
      });
      final entry = tracking.thirdPartyTrackers!.single;
      expect(entry.trackerId, 'tpt_01ARZ3NDEKTSV4RRFFQ69G5FAV');
      expect(entry.eventType, 'impression');
      expect(entry.matchType, isNull);
      expect(entry.eventKey, isNull);
      expect(entry.url, rawUrl);
    });

    test('A4 A5 - any and specific click entries decode', () {
      final tracking = Tracking.fromJson({
        'thirdPartyTrackers': [
          {
            'trackerId': 'tpt_A',
            'eventType': 'click',
            'matchType': 'any',
            'url': 'https://a.example/c',
          },
          {
            'trackerId': 'tpt_B',
            'eventType': 'click',
            'matchType': 'specific',
            'eventKey': 'cta_tap',
            'url': 'https://a.example/s',
          },
        ]
      });
      final entries = tracking.thirdPartyTrackers!;
      expect(entries[0].matchType, 'any');
      expect(entries[0].eventKey, isNull);
      expect(entries[1].matchType, 'specific');
      expect(entries[1].eventKey, 'cta_tap');
    });

    test('A6 - unknown extra fields are ignored', () {
      final tracking = Tracking.fromJson({
        'thirdPartyTrackers': [
          {
            'trackerId': 'tpt_C',
            'eventType': 'impression',
            'url': 'https://a.example/i',
            'futureField': {'nested': true},
          }
        ]
      });
      expect(tracking.thirdPartyTrackers, hasLength(1));
    });

    test('A7 A11 - malformed entries drop individually; siblings survive', () {
      final tracking = Tracking.fromJson({
        'thirdPartyTrackers': [
          {'trackerId': 'tpt_NO_URL', 'eventType': 'impression'},
          'not-an-object',
          {
            'trackerId': 'tpt_OK',
            'eventType': 'impression',
            'url': 'https://a.example/i',
          },
        ]
      });
      expect(
        tracking.thirdPartyTrackers!.map((e) => e.trackerId).toList(),
        ['tpt_OK'],
      );
    });

    test('A11 - a malformed block never fails the whole tracking decode', () {
      final tracking = Tracking.fromJson({
        'thirdPartyTrackers': 'garbage',
        'clicks': [
          {'key': 'default', 'url': 'https://t/c'}
        ],
      });
      expect(tracking.thirdPartyTrackers, isNull);
      expect(tracking.getClickUrl(), 'https://t/c');
    });
  });

  group('§A semantic validation + §F sanitized reasons', () {
    test('A8 - non-HTTPS urls are rejected', () {
      for (final url in [
        'http://agency.example/imp',
        'ftp://agency.example/imp',
        'javascript:alert(1)',
        'agency.example/imp',
        '',
      ]) {
        expect(
          ThirdPartyTrackerDispatcher.rejectionReason(tracker(url: url)),
          isNotNull,
          reason: 'expected rejection for $url',
        );
      }
    });

    test('A9 A10 - unknown types and keyless specific clicks are rejected', () {
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(tracker(eventType: 'conversion')),
        isNotNull,
      );
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(
            tracker(eventType: 'click', matchType: 'fuzzy')),
        isNotNull,
      );
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(tracker(eventType: 'click')),
        isNotNull,
      );
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(
            tracker(eventType: 'click', matchType: 'specific')),
        isNotNull,
      );
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(
            tracker(eventType: 'click', matchType: 'specific', eventKey: '')),
        isNotNull,
      );
    });

    test('valid shapes pass validation', () {
      expect(ThirdPartyTrackerDispatcher.rejectionReason(tracker()), isNull);
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(
            tracker(eventType: 'click', matchType: 'any', url: 'https://a.example/c')),
        isNull,
      );
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(tracker(
          eventType: 'click',
          matchType: 'specific',
          eventKey: 'cta_tap',
          url: 'https://a.example/s',
        )),
        isNull,
      );
    });

    test(
        'A12 E30 - a URL the parser cannot round-trip verbatim (raw macro) is '
        'rejected, never fired mutated', () {
      // %%CACHEBUSTER%% is an invalid percent-sequence: Dart's Uri re-escapes
      // it, so firing it would corrupt what the agency counts. It must be
      // discarded at validation instead.
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(
            tracker(url: 'https://agency.example/imp?cb=%%CACHEBUSTER%%')),
        isNotNull,
      );
      // A clean RFC-3986 URL round-trips and passes.
      expect(
        ThirdPartyTrackerDispatcher.rejectionReason(
            tracker(url: 'https://agency.example/imp?b=2&a=1&ord=12345')),
        isNull,
      );
    });

    test('F35 - rejection reasons never contain the URL', () {
      const poisonUrl = 'http://leak.example/secret?campaign=X';
      final invalid = [
        tracker(url: poisonUrl),
        tracker(eventType: 'conversion', url: poisonUrl),
        tracker(eventType: 'click', matchType: 'fuzzy', url: poisonUrl),
        tracker(eventType: 'click', matchType: 'specific', url: poisonUrl),
      ];
      for (final entry in invalid) {
        final reason = ThirdPartyTrackerDispatcher.rejectionReason(entry)!;
        expect(reason.contains('leak.example'), isFalse);
        expect(reason.contains('secret'), isFalse);
      }
    });
  });

  group('matching', () {
    test('C18-C20 C22 - event types never cross-match; keys match per matchType',
        () {
      final imp = tracker();
      final anyClick =
          tracker(eventType: 'click', matchType: 'any', url: 'https://a.example/c');
      final specific = tracker(
        eventType: 'click',
        matchType: 'specific',
        eventKey: 'cta_tap',
        url: 'https://a.example/s',
      );

      expect(
          ThirdPartyTrackerDispatcher.matches(imp, const ThirdPartyImpressionEvent()),
          isTrue);
      expect(
          ThirdPartyTrackerDispatcher.matches(imp, const ThirdPartyClickEvent('default')),
          isFalse);
      expect(
          ThirdPartyTrackerDispatcher.matches(
              anyClick, const ThirdPartyImpressionEvent()),
          isFalse);
      expect(
          ThirdPartyTrackerDispatcher.matches(
              anyClick, const ThirdPartyClickEvent('default')),
          isTrue);
      expect(
          ThirdPartyTrackerDispatcher.matches(
              specific, const ThirdPartyClickEvent('cta_tap')),
          isTrue);
      expect(
          ThirdPartyTrackerDispatcher.matches(
              specific, const ThirdPartyClickEvent('other')),
          isFalse);
    });
  });

  group('§B/§C/§D/§E fan-out through the network', () {
    test('B13 E30 - impression fires canonical plus tracker GET verbatim',
        () async {
      final (sdk, captured) = await sdkWithCapture();
      const rawUrl = 'https://agency.example/imp?b=2&a=1&ord=12345';
      sdk.fireImpression(trackingWith([tracker(url: rawUrl)]));
      await settle();

      final agency = agencyUrls(captured);
      expect(agency, [rawUrl]);
      final trackerReq =
          captured.singleWhere((r) => r.url.host.endsWith('agency.example'));
      expect(trackerReq.method, 'GET');
      expect(captured.where((r) => r.url.host == 'mock.api.admoai.com'),
          hasLength(1));
    });

    test('B14 C22 - only impression trackers fire on fireImpression', () async {
      final (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith([
        tracker(id: 'tpt_1', url: 'https://agency.example/i1'),
        tracker(id: 'tpt_2', url: 'https://agency.example/i2'),
        tracker(
            id: 'tpt_3',
            eventType: 'click',
            matchType: 'any',
            url: 'https://agency.example/c1'),
      ]));
      await settle();
      expect(agencyUrls(captured)..sort(),
          ['https://agency.example/i1', 'https://agency.example/i2']);
    });

    test('B15 - two invocations fire the tracker twice', () async {
      final (sdk, captured) = await sdkWithCapture();
      final info = trackingWith([tracker(url: 'https://agency.example/imp')]);
      sdk.fireImpression(info);
      sdk.fireImpression(info);
      await settle();
      expect(agencyUrls(captured), hasLength(2));
    });

    test('B16 C21 - a key without a canonical URL fires nothing at all',
        () async {
      final (sdk, captured) = await sdkWithCapture();
      final info = trackingWith([
        tracker(url: 'https://agency.example/imp'),
        tracker(
            id: 'tpt_2',
            eventType: 'click',
            matchType: 'any',
            url: 'https://agency.example/c'),
      ]);
      sdk.fireImpression(info, key: 'nonexistent');
      sdk.fireClick(info, key: 'nonexistent');
      await settle();
      expect(captured, isEmpty);
    });

    test('B17 - no trackers means canonical only', () async {
      final (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith(null));
      await settle();
      expect(captured, hasLength(1));
      expect(captured.single.url.host, 'mock.api.admoai.com');
    });

    test('C18-C20 - any-click fires on every valid key; specific on its key',
        () async {
      final (sdk, captured) = await sdkWithCapture();
      final info = trackingWith([
        tracker(
            id: 'tpt_any',
            eventType: 'click',
            matchType: 'any',
            url: 'https://agency.example/any'),
        tracker(
            id: 'tpt_spec',
            eventType: 'click',
            matchType: 'specific',
            eventKey: 'cta_tap',
            url: 'https://agency.example/spec'),
      ]);

      sdk.fireClick(info); // "default": any fires, specific does not
      await settle();
      expect(agencyUrls(captured), ['https://agency.example/any']);

      captured.clear();
      sdk.fireClick(info, key: 'cta_tap'); // both fire
      await settle();
      expect(agencyUrls(captured)..sort(),
          ['https://agency.example/any', 'https://agency.example/spec']);
    });

    test('D23 - byte-identical URLs dedupe within one invocation', () async {
      final (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith([
        tracker(id: 'tpt_1', url: 'https://agency.example/same'),
        tracker(id: 'tpt_2', url: 'https://agency.example/same'),
        tracker(id: 'tpt_3', url: 'https://agency.example/same?x=1'),
      ]));
      await settle();
      expect(agencyUrls(captured)..sort(),
          ['https://agency.example/same', 'https://agency.example/same?x=1']);
    });

    test('D24 - the same URL across event types fires once per event',
        () async {
      final (sdk, captured) = await sdkWithCapture();
      final info = trackingWith([
        tracker(id: 'tpt_1', url: 'https://agency.example/shared'),
        tracker(
            id: 'tpt_2',
            eventType: 'click',
            matchType: 'any',
            url: 'https://agency.example/shared'),
      ]);
      sdk.fireImpression(info);
      sdk.fireClick(info);
      await settle();
      expect(agencyUrls(captured), hasLength(2));
    });

    test('D25 D26 D27 - the limit counts valid entries only', () async {
      List<ThirdPartyTracker> entries(int count, {int invalidExtra = 0}) => [
            for (var i = 0; i < count; i++)
              tracker(id: 'tpt_$i', url: 'https://agency.example/t$i'),
            for (var i = 0; i < invalidExtra; i++)
              tracker(id: 'tpt_bad', url: 'http://insecure.example/x'),
          ];

      // 10 valid → all fire.
      var (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith(entries(10)));
      await settle();
      expect(agencyUrls(captured), hasLength(10));

      // 11 valid → none fire (canonical still does).
      (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith(entries(11)));
      await settle();
      expect(agencyUrls(captured), isEmpty);
      expect(captured.where((r) => r.url.host == 'mock.api.admoai.com'),
          hasLength(1));

      // 9 valid + 2 invalid (11 raw) → the 9 fire, invalid never dispatch.
      (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith(entries(9, invalidExtra: 2)));
      await settle();
      expect(agencyUrls(captured), hasLength(9));
      expect(captured.where((r) => r.url.host == 'insecure.example'), isEmpty);
    });

    test('E28 - tracker requests carry no Admoai identity; canonical does',
        () async {
      final (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith([tracker(url: 'https://agency.example/imp')]));
      await settle();

      final trackerReq =
          captured.singleWhere((r) => r.url.host.endsWith('agency.example'));
      expect(trackerReq.headers['X-Decision-Version'], isNull);
      expect(trackerReq.headers['X-Tracking-Version'], isNull);
      expect(trackerReq.headers['Accept-Language'], isNull);
      expect(trackerReq.headers['Authorization'], isNull);
      expect(trackerReq.headers['User-Agent'] ?? '',
          isNot(contains('AdMoaiSDK')));

      final canonicalReq =
          captured.singleWhere((r) => r.url.host == 'mock.api.admoai.com');
      expect(canonicalReq.headers['X-Tracking-Version'], '2025-11-01');
      expect(canonicalReq.headers['Accept-Language'], 'en');
      expect(canonicalReq.headers['User-Agent'], contains('AdMoaiSDK'));
    });

    test(
        'A12 E30 wire - a macro tracker is discarded end-to-end while a clean '
        'sibling fires', () async {
      final (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith([
        tracker(id: 'tpt_macro', url: 'https://agency.example/imp?cb=%%CACHEBUSTER%%'),
        tracker(id: 'tpt_ok', url: 'https://agency.example/clean'),
      ]));
      await settle();
      expect(agencyUrls(captured), ['https://agency.example/clean']);
    });

    test('E29 - a Set-Cookie from a tracker is not persisted or re-sent',
        () async {
      final captured = <http.Request>[];
      final client = MockClient((request) async {
        captured.add(request);
        return http.Response('', 200,
            headers: {'set-cookie': 'session=abc123; Path=/'});
      });
      final dispatcher =
          ThirdPartyTrackerDispatcher(logger: Logger('test'), httpClient: client);
      dispatcher.dispatch([tracker(url: 'https://agency.example/imp')],
          const ThirdPartyImpressionEvent());
      await settle();
      dispatcher.dispatch([tracker(url: 'https://agency.example/imp')],
          const ThirdPartyImpressionEvent());
      await settle();
      expect(captured, hasLength(2));
      expect(captured[1].headers['cookie'], isNull);
      expect(captured[1].headers['Cookie'], isNull);
      dispatcher.close();
    });

    test('E32 - tracker requests carry no conditional-cache headers', () async {
      final (sdk, captured) = await sdkWithCapture();
      sdk.fireImpression(trackingWith([tracker(url: 'https://agency.example/imp')]));
      await settle();
      final trackerReq =
          captured.singleWhere((r) => r.url.host.endsWith('agency.example'));
      expect(trackerReq.headers['If-None-Match'], isNull);
      expect(trackerReq.headers['If-Modified-Since'], isNull);
    });

    test(
        'E33 - a client that THROWS for one tracker never escapes and never '
        'stops siblings', () async {
      final captured = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/boom') {
          throw http.ClientException('refused', request.url);
        }
        captured.add(request.url.toString());
        return http.Response('', 200);
      });
      final dispatcher =
          ThirdPartyTrackerDispatcher(logger: Logger('test'), httpClient: client);
      dispatcher.dispatch([
        tracker(id: 'tpt_1', url: 'https://agency.example/boom'),
        tracker(id: 'tpt_2', url: 'https://agency.example/ok'),
      ], const ThirdPartyImpressionEvent());
      await settle();
      expect(captured, ['https://agency.example/ok']);
      dispatcher.close();
    });

    test('D26 F35 - the over-limit warn fires once and never contains a URL',
        () async {
      final logged = <String>[];
      hierarchicalLoggingEnabled = true;
      final logger = Logger('tpt-limit-sink')..level = Level.ALL;
      final sub = logger.onRecord.listen((r) => logged.add(r.message));
      final dispatcher = ThirdPartyTrackerDispatcher(
        logger: logger,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      dispatcher.dispatch(
        [for (var i = 0; i < 11; i++) tracker(id: 'tpt_$i', url: 'https://agency.example/t$i')],
        const ThirdPartyImpressionEvent(),
      );
      await settle();
      await sub.cancel();
      final warns = logged.where((m) => m.contains('exceed the limit')).toList();
      expect(warns, hasLength(1));
      for (final message in logged) {
        expect(message.contains('agency.example'), isFalse);
      }
      dispatcher.close();
    });

    test('E31 - a 3xx from a tracker is terminal (followRedirects disabled)',
        () async {
      http.BaseRequest? sent;
      final client = MockClient.streaming((request, bodyStream) async {
        sent = request;
        return http.StreamedResponse(const Stream.empty(), 302, headers: {
          'location': 'https://redirect-target.example/next',
        });
      });
      final dispatcher =
          ThirdPartyTrackerDispatcher(logger: Logger('test'), httpClient: client);
      dispatcher.dispatch(
          [tracker(url: 'https://agency.example/imp')],
          const ThirdPartyImpressionEvent());
      await settle();
      expect(sent, isNotNull);
      expect(sent!.followRedirects, isFalse,
          reason: 'the dispatcher must mark redirects terminal');
      dispatcher.close();
    });

    test('E33 E34 - a failing tracker is never retried and never affects siblings',
        () async {
      final captured = <http.Request>[];
      final client = MockClient((request) async {
        captured.add(request);
        return http.Response('', 500);
      });
      final dispatcher =
          ThirdPartyTrackerDispatcher(logger: Logger('test'), httpClient: client);
      dispatcher.dispatch([
        tracker(id: 'tpt_1', url: 'https://agency.example/a'),
        tracker(id: 'tpt_2', url: 'https://agency.example/b'),
      ], const ThirdPartyImpressionEvent());
      await settle();
      expect(captured, hasLength(2));
      dispatcher.close();
    });

    test('F36 - discard logs reference trackerId only, never the URL', () async {
      final logged = <String>[];
      hierarchicalLoggingEnabled = true;
      final logger = Logger('tpt-test-sink')..level = Level.ALL;
      final sub = logger.onRecord.listen((r) => logged.add(r.message));
      final dispatcher = ThirdPartyTrackerDispatcher(
        logger: logger,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      dispatcher.dispatch(
        [tracker(id: 'tpt_bad', url: 'http://insecure.example/secret?campaign=X')],
        const ThirdPartyImpressionEvent(),
      );
      await settle();
      await sub.cancel();
      expect(logged, isNotEmpty);
      for (final message in logged) {
        expect(message, contains('tpt_bad'));
        expect(message.contains('insecure.example'), isFalse);
        expect(message.contains('secret'), isFalse);
      }
      dispatcher.close();
    });
  });
}
