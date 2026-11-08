import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e/manifest_runner.dart';

// The live manifest runner's `expect.creative` interpreter (schemaVersion 4), exercised on a
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

  test('the runner refuses every schemaVersion but 4', () {
    expect(supportedSchemaVersion, equals(4));
  });
}
