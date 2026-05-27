import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const baseUrl = 'https://mock.api.admoai.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AdMoai sdk;

  setUp(() async {
    const MethodChannel channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getLocalTimezone') {
          return 'UTC';
        }
        return null;
      },
    );

    final config = SDKConfig(baseUrl: baseUrl);
    sdk = await AdMoai.initialize(
      config: config,
    );
  });

  test('testSDKInitialization', () async {
    final config = SDKConfig(
      baseUrl: baseUrl,
      logger: Logger('AdMoaiSDK'),
    );

    final sdk = await AdMoai.initialize(config: config);

    // Verify default configurations
    expect(sdk.config.baseUrl, equals(baseUrl));
    expect(sdk.appConfig, isNotNull);
    expect(sdk.deviceConfig, isNotNull);
    expect(sdk.userConfig, isNotNull);
  });

  test('testAppConfigManagement', () {
    // Test clear
    sdk.clearAppConfig();
    expect(sdk.appConfig.name, isNull);
    expect(sdk.appConfig.version, isNull);
    expect(sdk.appConfig.buildNumber, isNull);
    expect(sdk.appConfig.identifier, isNull);
    expect(sdk.appConfig.language, isNull);

    // Test custom config
    sdk.setAppConfig(
      name: 'TestApp',
      version: '1.0.0',
      buildNumber: '123',
      identifier: 'com.test.app',
      language: 'en',
    );

    expect(sdk.appConfig.name, equals('TestApp'));
    expect(sdk.appConfig.version, equals('1.0.0'));
    expect(sdk.appConfig.buildNumber, equals('123'));
    expect(sdk.appConfig.identifier, equals('com.test.app'));
    expect(sdk.appConfig.language, equals('en'));
  });

  test('testDeviceConfigManagement', () {
    // Test clear
    sdk.clearDeviceConfig();
    expect(sdk.deviceConfig.id, isNull);
    expect(sdk.deviceConfig.model, isNull);
    expect(sdk.deviceConfig.manufacturer, isNull);
    expect(sdk.deviceConfig.os, isNull);
    expect(sdk.deviceConfig.osVersion, isNull);
    expect(sdk.deviceConfig.timezone, isNull);
    expect(sdk.deviceConfig.language, isNull);

    // Test custom config
    sdk.setDeviceConfig(
      id: 'device123',
      model: 'iPhone14,2',
      manufacturer: 'Apple',
      os: 'iOS',
      osVersion: '16.0',
      timezone: 'UTC',
      language: 'en',
    );

    expect(sdk.deviceConfig.id, equals('device123'));
    expect(sdk.deviceConfig.model, equals('iPhone14,2'));
    expect(sdk.deviceConfig.manufacturer, equals('Apple'));
    expect(sdk.deviceConfig.os, equals('iOS'));
    expect(sdk.deviceConfig.osVersion, equals('16.0'));
    expect(sdk.deviceConfig.timezone, equals('UTC'));
    expect(sdk.deviceConfig.language, equals('en'));
  });

  test('testUserConfigManagement', () {
    // Test custom config
    final consent = Consent(gdpr: true);

    sdk.setUserConfig(
      id: 'user123',
      ip: '192.168.1.1',
      timezone: 'America/New_York',
      consent: consent,
    );

    expect(sdk.userConfig.id, equals('user123'));
    expect(sdk.userConfig.ip, equals('192.168.1.1'));
    expect(sdk.userConfig.timezone, equals('America/New_York'));
    expect(sdk.userConfig.consent.gdpr, isTrue);

    // Test clear
    sdk.clearUserConfig();
    expect(sdk.userConfig.id, isNull);
    expect(sdk.userConfig.ip, isNull);
    expect(sdk.userConfig.timezone, isNull);
    expect(sdk.userConfig.consent.gdpr, isFalse);
  });

  group('fireTracking version header', () {
    test('sends X-Decision-Version header when apiVersion is set', () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: mockClient,
      );

      sdk.fireTracking('https://tracking.example.com/event');
      await Future.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(captured!.headers['X-Decision-Version'], equals('2025-11-01'));
    });

    test('omits X-Decision-Version header when apiVersion is not set', () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl),
        httpClient: mockClient,
      );

      sdk.fireTracking('https://tracking.example.com/event');
      await Future.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(captured!.headers.containsKey('X-Decision-Version'), isFalse);
    });
  });

  group('User-Agent header', () {
    test('decision request carries User-Agent: AdMoaiSDK/{sdkVersion}', () {
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl),
      );
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      final httpRequest = sdk.getHttpRequest(request);

      expect(httpRequest.headers!['User-Agent'], startsWith('AdMoaiSDK/'));
      expect(httpRequest.headers!['User-Agent'], contains(sdkVersion));
    });

    test('tracking request carries User-Agent', () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl),
        httpClient: mockClient,
      );

      sdk.fireTracking('https://tracking.example.com/event');
      await Future.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(captured!.headers['user-agent'], startsWith('AdMoaiSDK/'));
    });

    test('sdkVersion constant matches expected v0.3.0', () {
      expect(sdkVersion, equals('0.3.0'));
    });
  });

  group('network timeouts', () {
    test('SDKConfig exposes three timeout knobs with 10s defaults', () {
      final unset = SDKConfig(baseUrl: baseUrl);
      expect(unset.requestTimeout, equals(const Duration(seconds: 10)));
      expect(unset.connectTimeout, equals(const Duration(seconds: 10)));
      expect(unset.receiveTimeout, equals(const Duration(seconds: 10)));
    });

    test('SDKConfig accepts custom timeouts', () {
      final cfg = SDKConfig(
        baseUrl: baseUrl,
        requestTimeout: const Duration(seconds: 15),
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 20),
      );
      expect(cfg.requestTimeout, equals(const Duration(seconds: 15)));
      expect(cfg.connectTimeout, equals(const Duration(seconds: 5)));
      expect(cfg.receiveTimeout, equals(const Duration(seconds: 20)));
    });

    test('custom http.Client is used for decision requests', () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          '{"success": true, "data": []}',
          200,
        );
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl),
        httpClient: mockClient,
      );

      final request = (sdk.createRequestBuilder()..addPlacement(key: 'home'))
          .build();
      await sdk.requestAds(request);

      expect(captured, isNotNull);
      expect(captured!.url.path, equals('/v1/decision'));
    });

    test('custom http.Client is used for tracking requests', () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl),
        httpClient: mockClient,
      );

      sdk.fireTracking('https://tracking.example.com/event');
      await Future.delayed(Duration.zero);

      expect(captured, isNotNull);
    });

    test(
        'decision request throws NetworkError on requestTimeout (TimeoutException)',
        () async {
      final stallingClient = MockClient((request) async {
        await Future.delayed(const Duration(seconds: 5));
        return http.Response('{}', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(
          baseUrl: baseUrl,
          requestTimeout: const Duration(milliseconds: 200),
        ),
        httpClient: stallingClient,
      );

      final request = (sdk.createRequestBuilder()..addPlacement(key: 'home'))
          .build();

      expect(
        () => sdk.requestAds(request),
        throwsA(isA<NetworkError>()),
      );
    });

    test('tracking request is fire-and-forget on timeout (no throw)',
        () async {
      var completed = false;
      final stallingClient = MockClient((request) async {
        await Future.delayed(const Duration(seconds: 5));
        return http.Response('', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(
          baseUrl: baseUrl,
          requestTimeout: const Duration(milliseconds: 100),
        ),
        httpClient: stallingClient,
      );

      sdk.fireTracking('https://tracking.example.com/event');
      // give the timeout time to fire
      await Future.delayed(const Duration(milliseconds: 250));
      completed = true;

      expect(completed, isTrue);
    });

    test('getHttpRequest preview is unaffected by timeout config', () {
      final sdk = AdMoai.forTesting(
        config: SDKConfig(
          baseUrl: baseUrl,
          requestTimeout: const Duration(seconds: 1),
        ),
      );

      final request = (sdk.createRequestBuilder()..addPlacement(key: 'home'))
          .build();
      final httpRequest = sdk.getHttpRequest(request);
      expect(httpRequest.path, equals('/v1/decision'));
      expect(httpRequest.method, equals(HTTPMethod.post));
    });
  });

  group('defaultLanguage and Accept-Language header', () {
    test('SDKConfig exposes defaultLanguage and defaults to null', () {
      final unset = SDKConfig(baseUrl: baseUrl);
      expect(unset.defaultLanguage, isNull);

      final set = SDKConfig(baseUrl: baseUrl, defaultLanguage: 'en-US');
      expect(set.defaultLanguage, equals('en-US'));
    });

    test('decision request carries Accept-Language when defaultLanguage is set',
        () {
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, defaultLanguage: 'en-US'),
      );

      final builder = sdk.createRequestBuilder()..addPlacement(key: 'home');
      final httpRequest = sdk.getHttpRequest(builder.build());

      expect(httpRequest.headers!['Accept-Language'], equals('en-US'));
      expect(httpRequest.headers!['Content-Type'], equals('application/json'));
      expect(httpRequest.headers!['Accept'], equals('application/json'));
    });

    test('decision request omits Accept-Language when defaultLanguage is null',
        () {
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl),
      );

      final builder = sdk.createRequestBuilder()..addPlacement(key: 'home');
      final httpRequest = sdk.getHttpRequest(builder.build());

      expect(httpRequest.headers!.containsKey('Accept-Language'), isFalse);
    });

    test('tracking request carries Accept-Language and X-Decision-Version',
        () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(
          baseUrl: baseUrl,
          apiVersion: '2025-11-01',
          defaultLanguage: 'es-ES',
        ),
        httpClient: mockClient,
      );

      sdk.fireTracking('https://tracking.example.com/event');
      await Future.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(captured!.headers['Accept-Language'], equals('es-ES'));
      expect(captured!.headers['X-Decision-Version'], equals('2025-11-01'));
    });

    test('tracking request omits Accept-Language when defaultLanguage is null',
        () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl),
        httpClient: mockClient,
      );

      sdk.fireTracking('https://tracking.example.com/event');
      await Future.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(captured!.headers.containsKey('Accept-Language'), isFalse);
    });
  });
}
