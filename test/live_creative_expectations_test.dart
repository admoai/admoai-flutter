import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'e2e/journey_e2e_harness.dart';
import 'e2e/manifest_runner.dart';

// The live manifest runner's `expect.creative` interpreter (schemaVersion 4 and 5), exercised on a
// creative decoded from a literal wire object: no engine, so the pass AND fail path of every
// new key is proven offline. The live proof is test/e2e/journey_e2e_test.dart.

Creative _creative({bool journey = true}) => Creative.fromJson({
      'contents': [
        {'key': 'headline', 'type': 'text', 'value': 'Hi'},
        {'key': 'destination_url', 'type': 'url', 'value': 'https://x.example'},
        {'key': 'slides', 'type': 'json', 'value': <String, dynamic>{}},
      ],
      'advertiser': {'name': 'A'},
      'template': {'key': 'card', 'style': 'tall'},
      'tracking': <String, dynamic>{},
      'metadata': {
        'adId': 'ad_1',
        'creativeId': 'c_1',
        'templateId': 't_1',
        'placementId': 'p_1',
        'priority': 'standard',
        'effectiveStandardFormatKey': 'card',
        'effectiveStandardFormatVersion': 1,
      },
      if (journey) 'journey': {'stageKey': 'checkout', 'dealId': 'deal_1'},
    });

void _passes(Map<String, dynamic> expectation, {Creative? creative}) =>
    assertCreative(creative ?? _creative(), expectation, []);

void _fails(Map<String, dynamic> expectation, {Creative? creative}) => expect(
      () => assertCreative(creative ?? _creative(), expectation, []),
      throwsA(anything),
    );

void main() {
  test('metadata: exact value per key, null means absent', () {
    _passes({
      'metadata': {
        'effectiveStandardFormatKey': 'card',
        'effectiveStandardFormatVersion': 1,
        'templateSource': null,
      },
    });
    _fails({
      'metadata': {'effectiveStandardFormatKey': 'carousel'},
    });
    _fails({
      'metadata': {'templateSource': 'admoai_standard'},
    });
    _fails({
      'metadata': {'effectiveStandardFormatKey': null},
    });
  });

  test('metadata: assetContext is exact, null means absent', () {
    _passes({
      'metadata': {'assetContext': null},
    });
    _fails({
      'metadata': {'assetContext': 'vehicle_marker'},
    });
  });

  test('metadata: a key this SDK does not know fails loudly', () {
    _fails({
      'metadata': {'somethingNew': null},
    });
  });

  test('templateKey: the served template.key', () {
    _passes({'templateKey': 'card'});
    _fails({'templateKey': 'carousel'});
  });

  test('contentKeys: the exact set, order and slides ignored', () {
    _passes({
      'contentKeys': ['destination_url', 'headline'],
    });
    _fails({
      'contentKeys': ['headline'],
    });
    _fails({
      'contentKeys': ['headline', 'destination_url', 'image'],
    });
  });

  test('styleIn: the served template.style is one of the list', () {
    _passes({
      'styleIn': ['short', 'tall'],
    });
    _fails({
      'styleIn': ['short'],
    });
  });

  test('journeyStageKey: the served journey.stageKey, journey ads only', () {
    _passes({'journey': true, 'journeyStageKey': 'checkout'});
    _fails({'journey': true, 'journeyStageKey': 'welcome'});
    _fails({'journeyStageKey': 'checkout'});
    _fails({
      'journey': true,
      'journeyStageKey': 'checkout',
    }, creative: _creative(journey: false));
  });

  test('an expect.creative key the runner does not execute fails', () {
    _fails({'templateKeyy': 'card'});
    _fails({'templateKey': 'card', 'somethingFromSchemaVersion5': true});
  });

  test('the runner refuses every schemaVersion but 5', () {
    expect(supportedSchemaVersion, equals(5));
  });

  test('a scenario key the runner does not execute is known or fails', () {
    expect(knownScenarioKeys, contains('slideTracking'));
    expect(knownScenarioKeys, isNot(contains('somethingFromSchemaVersion6')));
  });

  group('slides and clickKeys (Carousel)', () {
    Map<String, dynamic> slide(int n,
            {List<String> clicks = const ['default']}) =>
        {
          'slideId': 'slide_$n',
          'position': n,
          'contents': [
            {'key': 'image', 'type': 'image', 'value': 'https://i/$n.png'},
          ],
          'tracking': {
            'views': [
              {'key': 'slide_view', 'url': 'https://t/$n/view'},
            ],
            'clicks': [
              for (final k in clicks) {'key': k, 'url': 'https://t/$n/$k'},
            ],
          },
        };

    Creative carousel({List<Map<String, dynamic>>? slides}) =>
        Creative.fromJson({
          'contents': [
            {
              'key': 'slides',
              'type': 'slides',
              'value': slides ?? [slide(1), slide(2)],
            },
          ],
          'advertiser': {'name': 'A'},
          'tracking': <String, dynamic>{},
        });

    Map<String, dynamic> want(int n,
            {List<String> clicks = const ['default']}) =>
        {
          'slideId': 'slide_$n',
          'position': n,
          'contentKeys': ['image'],
          'viewKeys': ['slide_view'],
          'clickKeys': clicks,
        };

    test('slides: the ordered exact list passes', () {
      _passes({
        'slides': [want(1), want(2)],
        'clickKeys': <String>[],
      }, creative: carousel());
    });

    test('slides: wrong order fails', () {
      _fails({
        'slides': [want(2), want(1)],
      }, creative: carousel());
    });

    test('slides: a missing slide fails', () {
      _fails({
        'slides': [want(1)],
      }, creative: carousel());
      _fails({
        'slides': [want(1), want(2), want(3)],
      }, creative: carousel());
    });

    test('slides: an extra click key on a slide fails', () {
      _fails({
        'slides': [want(1), want(2)],
      },
          creative: carousel(slides: [
            slide(1),
            slide(2, clicks: ['default', 'extra'])
          ]));
    });

    test('slides: an unknown slide expect key fails', () {
      _fails({
        'slides': [
          {...want(1), 'somethingNew': true},
          want(2),
        ],
      }, creative: carousel());
    });

    test('clickKeys: the exact creative-level set', () {
      final withClick = Creative.fromJson({
        'contents': <dynamic>[],
        'advertiser': {'name': 'A'},
        'tracking': {
          'clicks': [
            {'key': 'default', 'url': 'https://t/c'},
          ],
        },
      });
      _passes({
        'clickKeys': ['default']
      }, creative: withClick);
      _fails({'clickKeys': <String>[]}, creative: withClick);
      _fails({
        'clickKeys': ['default']
      }, creative: carousel());
    });
  });

  group('live slideTracking', () {
    final wire = {
      'contents': [
        {
          'key': 'slides',
          'type': 'slides',
          'value': [
            for (final n in [1, 2])
              {
                'slideId': 'slide_$n',
                'position': n,
                'contents': <dynamic>[],
                'tracking': {
                  'views': [
                    {'key': 'slide_view', 'url': 'https://t.example/$n/view'},
                  ],
                  'clicks': [
                    {'key': 'default', 'url': 'https://t.example/$n/click'},
                  ],
                },
              },
          ],
        },
      ],
      'advertiser': {'name': 'A'},
      'tracking': <String, dynamic>{},
    };

    Future<void> run(
      Map<String, dynamic> block, {
      int status = 200,
    }) async {
      final client = RecordingClient(
        MockClient((_) async => http.Response('', status)),
      );
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: 'https://mock.api.admoai.com'),
        httpClient: client,
      );
      await runSlideTracking(
        block,
        sdk,
        client,
        Creative.fromJson(wire),
        [],
        quietPeriod: const Duration(milliseconds: 20),
        deadline: const Duration(milliseconds: 500),
      );
    }

    Map<String, dynamic> block(
      List<Map<String, dynamic>> steps,
      List<Map<String, dynamic>> beacons, {
      bool accepts = true,
    }) =>
        {
          'steps': steps,
          'expect': {
            'beacons': beacons,
            if (accepts) 'engineAcceptsEveryBeacon': true,
          },
        };

    final view2 = {'slide': 2, 'view': 'slide_view'};
    final click2 = {'slide': 2, 'click': 'default'};

    test('a click before its view sends the view, then the click', () async {
      await run(block([
        {'slideClick': 2},
      ], [
        view2,
        click2
      ]));
    });

    test('a view repeated sends one beacon; fireClick sends nothing', () async {
      await run(block([
        {'slideView': 2},
        {'slideView': 2},
      ], [
        view2
      ]));
      await run(block([
        {'fireClick': null},
      ], []));
    });

    test('the click repeats on every click', () async {
      await run(block([
        {'slideView': 2},
        {'slideClick': 2},
        {'slideClick': 2},
      ], [
        view2,
        click2,
        click2
      ]));
    });

    test('a beacon order mismatch fails', () {
      expect(
        run(block([
          {'slideClick': 2},
        ], [
          click2,
          view2
        ])),
        throwsA(anything),
      );
    });

    test('a missing or extra beacon fails', () {
      expect(
        run(block([
          {'slideClick': 2},
        ], [
          view2
        ])),
        throwsA(anything),
      );
      expect(
        run(block([
          {'slideView': 2},
        ], [
          view2,
          click2
        ])),
        throwsA(anything),
      );
    });

    test('a rejected beacon fails engineAcceptsEveryBeacon only', () async {
      final steps = [
        {'slideView': 2},
      ];
      expect(run(block(steps, [view2]), status: 500), throwsA(anything));
      await run(block(steps, [view2], accepts: false), status: 500);
    });

    test('an unknown step, key, or a third-party expectation fails', () {
      expect(
          run(block([
            {'swipe': 1}
          ], [])),
          throwsA(anything));
      expect(
        run({
          'steps': [
            {'slideView': 1}
          ],
          'expect': {
            'beacons': [
              {'slide': 1, 'view': 'slide_view'}
            ],
            'thirdPartyBeacons': ['x']
          },
        }),
        throwsA(anything),
      );
    });

    test('a slide beyond the served ones fails', () {
      expect(
          run(block([
            {'slideView': 3}
          ], [])),
          throwsA(anything));
    });
  });
}
