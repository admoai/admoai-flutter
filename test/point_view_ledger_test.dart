import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/point_view_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pin views are reported once per decision response — the scenarios of
/// `lib/src/point_view_ledger.feature`, one test per scenario, named after it.
/// Mirrors the iOS suite (`PointViewLedgerTests.swift`).
///
/// There is no Gherkin runner in this package, so `every scenario has a test`
/// holds the binding instead: a scenario added to the feature without a test
/// here, or a test whose scenario was renamed away, fails the build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scenarios = <String>{};

  /// A test that implements the feature scenario of the same title.
  void scenario(String title, Future<void> Function() body) {
    scenarios.add(title);
    test(title, body);
  }

  (AdMoai, List<http.Request>) sdkWithCapture() {
    final captured = <http.Request>[];
    final client = MockClient((request) async {
      captured.add(request);
      return http.Response('', 200);
    });
    final sdk = AdMoai.forTesting(
      config: SDKConfig(
        baseUrl: 'https://mock.api.admoai.com',
        apiVersion: '2025-11-01',
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

  String url(String response, String event, int pin) =>
      'https://t.example/$response/$event/p$pin';

  /// The points of `[from, to)` as decision response [response] would carry
  /// them. The view URL embeds the response the way the engine's per-event
  /// token does: the same pin in two responses has two different view URLs.
  List<MatchedPoint> points(int from, int to, {required String response}) =>
      Creative.fromJson({
        'contents': [
          {
            'key': 'matched_points',
            'type': 'matched_points',
            'value': [
              for (var i = from; i < to; i++)
                {
                  'id': 'p$i',
                  'name': 'P$i',
                  'latitude': 1,
                  'longitude': 1,
                  'distance': i,
                  'tracking': {
                    'views': [
                      {'key': 'default', 'url': url(response, 'view', i)}
                    ],
                    'taps': [
                      {'key': 'default', 'url': url(response, 'tap', i)}
                    ],
                    'clicks': [
                      {'key': 'default', 'url': url(response, 'click', i)}
                    ],
                  },
                },
            ],
          }
        ],
        'advertiser': {'name': 'Cabify'},
        'tracking': <String, dynamic>{},
      }).matchedPoints;

  Set<String> viewUrls(int from, int to, {required String response}) =>
      {for (var i = from; i < to; i++) url(response, 'view', i)};

  List<String> fired(List<http.Request> captured) =>
      captured.map((r) => r.url.toString()).toList();

  test('every scenario has a test', () {
    final titles = File('lib/src/point_view_ledger.feature')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('Scenario:'))
        .map((l) => l.substring('Scenario:'.length).trim())
        .toSet();

    expect(titles, isNotEmpty);
    expect(titles, equals(scenarios));
  });

  scenario("the first render fires every pin's view URLs", () async {
    final (sdk, captured) = sdkWithCapture();

    sdk.trackPointViews(points(0, 50, response: 'r'));
    await settle();

    expect(captured, hasLength(50), reason: 'exactly one GET per view URL');
    expect(fired(captured).toSet(), viewUrls(0, 50, response: 'r'));
  });

  scenario('a re-render of the same response fires nothing', () async {
    final (sdk, captured) = sdkWithCapture();
    final r = points(0, 50, response: 'r');
    sdk.trackPointViews(r);
    await settle();
    captured.clear();

    sdk.trackPointViews(r);
    await settle();

    expect(captured, isEmpty);
  });

  scenario('a re-render with new pins fires only the new ones', () async {
    // A..J is [0, 10), F..T is [5, 20), K..T is [10, 20).
    final (sdk, captured) = sdkWithCapture();
    final r = points(0, 20, response: 'r');
    sdk.trackPointViews(r.sublist(0, 10));
    await settle();
    captured.clear();

    sdk.trackPointViews(r.sublist(5, 20));
    await settle();

    expect(captured, hasLength(10));
    expect(fired(captured).toSet(), viewUrls(10, 20, response: 'r'));
  });

  scenario('a new decision response starts fresh', () async {
    final (sdk, captured) = sdkWithCapture();
    final r1 = points(0, 1, response: 'r1');
    final r2 = points(0, 1, response: 'r2');
    expect(r1.single.id, r2.single.id,
        reason: 'the same location in both responses');
    sdk.trackPointViews(r1);
    await settle();
    captured.clear();

    sdk.trackPointViews(r2);
    await settle();

    expect(fired(captured), [url('r2', 'view', 0)]);
  });

  scenario('memory is bounded', () async {
    final ledger = PointViewLedger();
    expect(ledger.capacity, 500);

    for (var response = 0; response < 100; response++) {
      for (var pin = 0; pin < 50; pin++) {
        ledger.claim('https://t/r$response/view/p$pin');
      }
    }

    expect(ledger.length, 500, reason: 'the ten most recent full responses');
    expect(ledger.claim('https://t/r99/view/p0'), isFalse,
        reason: 'the newest response is remembered');
    expect(ledger.claim('https://t/r90/view/p49'), isFalse,
        reason: 'so is the tenth newest');
    expect(ledger.claim('https://t/r89/view/p49'), isTrue,
        reason: 'the eleventh is forgotten and fires');
    expect(ledger.length, 500);
  });

  /// A pin re-rendered keeps its place: the next eviction takes the pin nobody
  /// has shown for longest, not the one the user is looking at.
  test('a rendered pin is not the next evicted', () {
    final ledger = PointViewLedger(capacity: 2)
      ..claim('a')
      ..claim('b')
      ..claim('a')
      ..claim('c');

    expect(ledger.claim('a'), isFalse);
    expect(ledger.claim('b'), isTrue);
  });

  /// Every `AdMoai` instance keeps its own record, the way it keeps its own
  /// Journey session: a fresh instance has reported nothing.
  test('a new SDK instance has reported nothing', () async {
    final r = points(0, 1, response: 'r');
    final (first, firstCaptured) = sdkWithCapture();
    first.trackPointViews(r);
    final (second, secondCaptured) = sdkWithCapture();
    second.trackPointViews(r);
    await settle();

    expect(fired(firstCaptured), [url('r', 'view', 0)]);
    expect(fired(secondCaptured), [url('r', 'view', 0)]);
  });

  scenario('single-point tracking follows the same rule', () async {
    final (sdk, captured) = sdkWithCapture();
    final point = points(0, 1, response: 'r').single;
    sdk.trackPointView(point);
    await settle();
    captured.clear();

    sdk.trackPointView(point);
    sdk.trackPointViews([point]);
    await settle();

    expect(captured, isEmpty);
  });

  scenario('taps and clicks are not deduplicated by this mechanism', () async {
    final (sdk, captured) = sdkWithCapture();
    final point = points(0, 1, response: 'r').single;
    sdk.trackPointView(point);
    await settle();
    captured.clear();

    sdk
      ..trackPointTap(point)
      ..trackPointTap(point)
      ..trackPointClick(point)
      ..trackPointClick(point);
    await settle();

    expect(fired(captured).where((u) => u == url('r', 'tap', 0)), hasLength(2));
    expect(
        fired(captured).where((u) => u == url('r', 'click', 0)), hasLength(2));
    expect(captured, hasLength(4));
  });
}
