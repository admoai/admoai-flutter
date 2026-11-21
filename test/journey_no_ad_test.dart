import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const baseUrl = 'https://mock.api.admoai.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const MethodChannel channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getLocalTimezone') return 'UTC';
      return null;
    });
  });

  group('No-ad shapes are treated uniformly', () {
    test('creatives: [] (takeover protection) is a clean no-ad', () {
      final decision =
          Decision.fromJson({'placement': 'in_ride', 'creatives': []});
      expect(decision.hasCreative, isFalse);
      expect(decision.isNoAd, isTrue);
      expect(decision.creatives, isEmpty);
    });

    test('creatives: null (no-fill) is a clean no-ad', () {
      final decision =
          Decision.fromJson({'placement': 'home', 'creatives': null});
      expect(decision.hasCreative, isFalse);
      expect(decision.isNoAd, isTrue);
      expect(decision.creatives, isNull);
    });

    test('creatives absent entirely is a clean no-ad', () {
      final decision = Decision.fromJson({'placement': 'home'});
      expect(decision.isNoAd, isTrue);
    });

    test('a real creative is not a no-ad', () {
      final decision = Decision.fromJson({
        'placement': 'home',
        'creatives': [
          {
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
          }
        ],
      });
      expect(decision.hasCreative, isTrue);
      expect(decision.isNoAd, isFalse);
    });
  });

  group('End-to-end no-ad response parses safely and fires nothing', () {
    Future<AdMoai> sdkReturning(String body, List<String> fired) async {
      final mockClient = MockClient((request) async {
        fired.add(request.url.toString());
        return http.Response(body, 200);
      });
      return AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: mockClient,
      );
    }

    test('data: [] yields empty decisions, no tracking auto-fired', () async {
      final fired = <String>[];
      final sdk = await sdkReturning(
        jsonEncode({'success': true, 'data': [], 'errors': [], 'warnings': []}),
        fired,
      );

      final response = await sdk.requestAds(
        sdk.createRequestBuilder().addPlacement(key: 'home').build(),
      );

      expect(response.body.data, isEmpty);
      // Exactly one HTTP call = the decision request. The SDK auto-fires no
      // tracking and provides no substitute ad.
      expect(fired.length, equals(1));
    });

    test('takeover creatives: [] yields a no-ad decision, no auto-fire',
        () async {
      final fired = <String>[];
      final sdk = await sdkReturning(
        jsonEncode({
          'success': true,
          'data': [
            {'placement': 'in_ride', 'creatives': []}
          ],
          'errors': [],
          'warnings': [],
        }),
        fired,
      );

      final response = await sdk.requestAds(
        sdk.createRequestBuilder().addPlacement(key: 'in_ride').build(),
      );

      final decision = response.body.data!.first;
      expect(decision.isNoAd, isTrue);
      expect(fired.length, equals(1));
    });
  });

  // Design invariant (enforced by API design + review, not runtime): the SDK
  // exposes no fallback/substitute-ad method. On a no-ad response the caller
  // simply gets an empty decision; there is deliberately no API to replace it
  // with a local, cached, or competing ad, preserving single-brand takeover
  // protection. See the AdMoai public surface — no setFallbackAd / useCachedAd
  // / substituteAd exists.
}
