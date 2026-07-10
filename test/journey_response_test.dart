import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal valid creative JSON that a Journey response wraps a `journey`
/// block around. Mirrors the engine's per-creative shape.
Map<String, dynamic> creativeJson({
  Map<String, dynamic>? journey,
  Object? tracking,
}) {
  return {
    'contents': [
      {'key': 'headline', 'value': 'Hi', 'type': 'text'},
    ],
    'advertiser': {'name': 'Acme'},
    'template': {'key': 'native_banner'},
    'tracking': tracking ??
        {
          'impressions': [
            {'key': 'default', 'url': 'https://t.example/v1/tracking?e=imp'}
          ],
        },
    if (journey != null) 'journey': journey,
  };
}

const fullJourney = {
  'dealId': 'jad_1',
  'instanceId': 'jinst_1',
  'definitionKey': 'ride_v1',
  'stageId': 'stage_1',
  'stageKey': 'in_ride',
  'stageNodeId': 'jsn_1',
  'sessionId': 'sess_123',
  'optStatus': 'in',
  'pricingModel': 'cpt',
  'fallbackBillingMode': 'bill_per_stage',
};

void main() {
  group('CreativeJourney — exact engine keys', () {
    test('parses all journey keys and exposes helpers', () {
      final c = Creative.fromJson(creativeJson(journey: fullJourney));

      expect(c.isJourneyAd(), isTrue);
      expect(c.journey, isNotNull);
      expect(c.journeyDealId, equals('jad_1'));
      expect(c.journeyInstanceId, equals('jinst_1'));
      expect(c.journeyDefinitionKey, equals('ride_v1'));
      expect(c.journeyStageId, equals('stage_1'));
      expect(c.journeyStageKey, equals('in_ride'));
      expect(c.journeyStageNodeId, equals('jsn_1'));
      expect(c.journeySessionId, equals('sess_123'));
      expect(c.journeyOptStatus, equals(JourneyOpt.optIn));
      expect(c.journeyPricingModel, equals('cpt'));
      expect(c.journeyFallbackBillingMode, equals('bill_per_stage'));
    });

    test('optStatus out maps to JourneyOpt.optOut', () {
      final c = Creative.fromJson(
        creativeJson(journey: {...fullJourney, 'optStatus': 'out'}),
      );
      expect(c.journeyOptStatus, equals(JourneyOpt.optOut));
    });
  });

  group('Backward compatibility', () {
    test('normal ad without journey block', () {
      final c = Creative.fromJson(creativeJson());
      expect(c.isJourneyAd(), isFalse);
      expect(c.journey, isNull);
      expect(c.journeyDealId, isNull);
      expect(c.isJourneyCompletion, isFalse);
      // Existing fields still parse.
      expect(c.advertiser.name, equals('Acme'));
      expect(c.template.key, equals('native_banner'));
    });
  });

  group('Tolerant Reader — forward compatibility', () {
    test('future-version journey payload never throws', () {
      final future = {
        ...fullJourney,
        'optStatus': 'paused', // unknown enum value
        'pricingModel': 'cpx', // unknown open-set value
        'brandNewField': {'nested': true}, // unknown extra field
        'anotherNewFlag': 42,
      };
      // Also add an unknown top-level creative field + unknown delivery.
      final json = creativeJson(journey: future)
        ..['delivery'] = 'holographic'
        ..['someFutureCreativeField'] = ['x'];

      late Creative c;
      expect(() => c = Creative.fromJson(json), returnsNormally);
      // Unknown enum degrades to null; open-set string preserved raw.
      expect(c.journeyOptStatus, isNull);
      expect(c.journeyPricingModel, equals('cpx'));
      // Known fields still read correctly.
      expect(c.journeyDealId, equals('jad_1'));
      expect(c.delivery, equals('holographic'));
    });

    test('omitted optional journey fields degrade to null, no throw', () {
      final c = Creative.fromJson(creativeJson(journey: {
        'dealId': 'jad_1',
        'instanceId': 'jinst_1',
        // everything else omitted
      }));
      expect(c.isJourneyAd(), isTrue);
      expect(c.journeyDealId, equals('jad_1'));
      expect(c.journeyStageId, isNull);
      expect(c.journeyOptStatus, isNull);
      expect(c.journeyPricingModel, isNull);
      expect(c.isJourneyCompletion, isFalse);
    });

    test('retyped journey fields degrade to null instead of throwing', () {
      final c = Creative.fromJson(creativeJson(journey: {
        'dealId': 123, // wrong type
        'optStatus': true, // wrong type
        'isCompletion': 'yes', // wrong type
      }));
      expect(c.journeyDealId, isNull);
      expect(c.journeyOptStatus, isNull);
      expect(c.isJourneyCompletion, isFalse);
    });

    test('journey block that is not a map is ignored', () {
      final json = creativeJson()..['journey'] = 'not-an-object';
      final c = Creative.fromJson(json);
      expect(c.isJourneyAd(), isFalse);
    });
  });

  group('Completion flag', () {
    test('final_stage completion serve exposes isJourneyCompletion true', () {
      final c = Creative.fromJson(creativeJson(journey: {
        ...fullJourney,
        'isCompletion': true,
      }));
      expect(c.isJourneyCompletion, isTrue);
    });
  });
}
