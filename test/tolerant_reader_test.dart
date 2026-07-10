import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

const baseUrl = 'https://mock.api.admoai.com';

Map<String, dynamic> journeyCreative(Map<String, dynamic> journey) => {
      'contents': [
        {'key': 'h', 'value': 'x', 'type': 'text'}
      ],
      'advertiser': {'name': 'Acme'},
      'template': {'key': 'native'},
      'tracking': {
        'impressions': [
          {'key': 'default', 'url': 'https://t/x'}
        ]
      },
      'journey': journey,
    };

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

  group('Forward compatibility (Tolerant Reader) — full envelope', () {
    Future<APIResponse<DecisionResponse>> parseBody(String body) async {
      final mockClient = MockClient((request) async => http.Response(body, 200));
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: mockClient,
      );
      return sdk.requestAds(
        sdk.createRequestBuilder().addPlacement(key: 'p').build(),
      );
    }

    test('future-version response with unknown fields parses without throwing',
        () async {
      final body = jsonEncode({
        'success': true,
        // Unknown top-level envelope field from a future version.
        'meta': {'served_by': 'future-node', 'experiment': 7},
        'data': [
          {
            'placement': 'in_ride',
            // Unknown decision-level field.
            'debug': {'trace': 'abc'},
            'creatives': [
              journeyCreative({
                'dealId': 'jad_1',
                'optStatus': 'suspended', // unknown enum
                'pricingModel': 'cpx', // unknown open-set
                'futureFlag': true, // unknown field
              })
                ..['unknownCreativeField'] = [1, 2, 3]
                ..['delivery'] = 'holographic',
            ],
          }
        ],
        'errors': [],
        'warnings': [],
      });

      // Awaiting directly: if parsing threw on the unknown fields, the test
      // fails here — proving the Tolerant Reader "never throws" guarantee.
      final response = await parseBody(body);

      final creative = response.body.data!.first.creatives!.first;
      expect(creative.isJourneyAd(), isTrue);
      expect(creative.journeyDealId, equals('jad_1'));
      expect(creative.journeyOptStatus, isNull); // unknown enum -> null
      expect(creative.journeyPricingModel, equals('cpx')); // raw preserved
      expect(creative.delivery, equals('holographic'));
    });
  });

  group('Deprecation-aware logging (X-API-Deprecated)', () {
    Future<AdMoai> sdkWithHeaders(
        Map<String, String> headers, Logger logger) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': true, 'data': [], 'errors': [], 'warnings': []}),
          200,
          headers: headers,
        );
      });
      return AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01', logger: logger),
        httpClient: mockClient,
      );
    }

    test('logs a single warning with sunset when deprecated', () async {
      final records = <LogRecord>[];
      final logger = Logger('tr-dep')
        ..level = Level.ALL
        ..onRecord.listen(records.add);

      final sdk = await sdkWithHeaders({
        'x-api-deprecated': 'true',
        'sunset': 'Wed, 01 Jul 2026 00:00:00 GMT',
      }, logger);

      await sdk.requestAds(
        sdk.createRequestBuilder().addPlacement(key: 'p').build(),
      );

      final warnings = records.where((r) => r.level >= Level.WARNING).toList();
      expect(warnings.length, equals(1));
      expect(warnings.first.message, contains('deprecated'));
      expect(warnings.first.message, contains('01 Jul 2026'));
    });

    test('no warning when header absent', () async {
      final records = <LogRecord>[];
      final logger = Logger('tr-nodep')
        ..level = Level.ALL
        ..onRecord.listen(records.add);

      final sdk = await sdkWithHeaders({}, logger);
      await sdk.requestAds(
        sdk.createRequestBuilder().addPlacement(key: 'p').build(),
      );

      expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
    });
  });
}
