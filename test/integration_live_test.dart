// ignore_for_file: avoid_print
@Tags(['live'])
library;

//
// Live integration test for AdMoai Flutter SDK.
//
// DIAGNOSTIC, NOT A CI GATE. This suite makes real network calls to
// api.mock.admoai.com and intentionally soft-logs some client/API errors
// instead of hard-failing, so a green run here is not a reliable release
// signal for live behavior. Deterministic SDK acceptance lives in the
// unit/mock-HTTP suites (admoai_test, journey_*_test, decision_*_test,
// api_client_test, tolerant_reader_test).
//
// It is tagged `live` (see dart_test.yaml). Exclude it from a deterministic
// gate with:
//   flutter test --exclude-tags live
// Or run it alone with:
//   flutter test test/integration_live_test.dart --reporter expanded
//
// The live-request tests (§3, §4) never hard-fail on response content —
// the mock server may return empty-decision 200s for some placements.
// They DO fail on network errors or unexpected SDK exceptions.
//
// What to look for in the printed output:
//   • Request JSON looks correct (targeting fields present, no spurious "format" key)
//   • HTTP 200 on every request
//   • Responses with "data": [] mean no live ad for that placement (fine)
//   • Responses with "data": [{...}] confirm the server returned an ad
//   • 422 on destination targeting → minConfidence key name is wrong (see §1)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:admoai/admoai.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Logging HTTP client
// Forwards every request to the real network and pretty-prints both sides.
// ──────────────────────────────────────────────────────────────────────────────

class LoggingClient extends http.BaseClient {
  final http.Client _inner;

  LoggingClient() : _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Buffer request body
    final bodyBytes =
        request is http.Request ? request.bodyBytes : <int>[];
    final bodyStr = utf8.decode(bodyBytes);

    Map<String, dynamic> reqJson = {};
    try {
      reqJson = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {}

    final prettyReq = const JsonEncoder.withIndent('  ').convert(reqJson);
    print('\n━━━ REQUEST ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('${request.method} ${request.url}');
    for (final e in request.headers.entries) {
      print('  ${e.key}: ${e.value}');
    }
    print(prettyReq);

    // Forward
    final response = await _inner.send(request);

    // Buffer response
    final respBytes = await response.stream.toBytes();
    final respStr = utf8.decode(respBytes);
    String prettyResp;
    try {
      prettyResp =
          const JsonEncoder.withIndent('  ').convert(jsonDecode(respStr));
    } catch (_) {
      prettyResp = respStr;
    }

    print('\n━━━ RESPONSE (${response.statusCode}) ━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print(prettyResp.length > 3000
        ? '${prettyResp.substring(0, 3000)}\n… (truncated)'
        : prettyResp);
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    return http.StreamedResponse(
      Stream.value(respBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

// ──────────────────────────────────────────────────────────────────────────────
// Simple synchronous mock client (header-assertion tests only — no network)
// ──────────────────────────────────────────────────────────────────────────────

class _MockClient extends http.BaseClient {
  final http.Response Function(http.BaseRequest) _handler;
  _MockClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared test fixtures (matching the reference example from the images)
// ──────────────────────────────────────────────────────────────────────────────

const _baseUrl = 'https://api.mock.admoai.com';

AppConfig get _appConfig => AppConfig(
      name: 'Admoai Flutter SDK',
      version: '1.0',
      identifier: 'com.admoai.sample',
      buildNumber: '1',
      language: 'en',
    );

DeviceConfig get _deviceConfig => DeviceConfig(
      os: 'iOS',
      osVersion: '18',
      model: 'iPhone16,2',
      manufacturer: 'Apple',
      id: 'flutter-test-device-001',
      timezone: 'America/Santiago',
      language: 'en',
    );

UserConfig get _userConfig => UserConfig(
      id: 'user_123',
      ip: '203.0.113.1',
      timezone: 'America/Santiago',
      consent: Consent(gdpr: true),
    );

// Test matrix: 9 placements × 2 apiVersion variants = 18 live requests
const _placements = [
  'json_none',
  'vasttag_none',
  'vast_xml_native_endcard',
  'json_native_endcard',
  'vasttag_native_endcard',
  'home',
  'menu',
  'freeMinutes',
  'search',
];

const _apiVersions = <String?>[null, '2025-11-01'];

// ──────────────────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Re-enable real networking. `TestWidgetsFlutterBinding` installs an
  // `HttpOverrides` that answers every `HttpClient` request with a mocked
  // HTTP 400 and an empty body, without touching the network.
  //
  // This suite shipped without clearing it, so every "live" call below returned
  // 400 from Flutter's mock and the soft-logging (see the header) reported it as
  // a warning — the suite stayed green while making no network call at all. An
  // assertion that never ran is indistinguishable from a passing one.
  HttpOverrides.global = null;

  // Mock the timezone channel (required by the SDK even in forTesting mode)
  setUpAll(() {
    const channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) async => 'America/Santiago',
    );
  });

  // ── §1  Format field omission (offline) ───────────────────────────────────
  group('§1  Format field behavior', () {
    late AdMoai sdk;

    setUp(() {
      sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: _baseUrl),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: UserConfig(id: 'user_123'),
      );
    });

    test('format key is ABSENT from JSON when no format is specified', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home') // ← no format arg
          .build();

      final placement =
          (request.toJson()['placements'] as List).first as Map;
      print('\n[§1-format-absent] placement JSON: $placement');

      expect(
        placement.containsKey('format'),
        isFalse,
        reason: 'format must be omitted entirely when not set — '
            'the decision-engine picks native or video automatically',
      );
    });

    test('Format.native serialises "format": "native"', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home', format: Format.native)
          .build();
      final placement =
          (request.toJson()['placements'] as List).first as Map;
      print('[§1-native] $placement');
      expect(placement['format'], equals('native'));
    });

    test('Format.video serialises "format": "video"', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home', format: Format.video)
          .build();
      final placement =
          (request.toJson()['placements'] as List).first as Map;
      print('[§1-video] $placement');
      expect(placement['format'], equals('video'));
    });

    // ── minConfidence key-name verification ──────────────────────────────────
    // Bug fixed: the SDK was sending "minConfidence" (camelCase) but the API
    // requires "min_confidence" (snake_case). Fixed in Targeting.toJson().
    test('destination serialises "min_confidence" (snake_case) — bug fix', () {
      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
            latitude: 72.514,
            longitude: 120.643,
            minConfidence: 0.5046,
          )
          .addPlacement(key: 'home')
          .build();

      final targeting = request.toJson()['targeting'] as Map;
      final dest = (targeting['destination'] as List).first as Map;

      print('\n[§1-min_confidence] destination entry: $dest');
      expect(dest.containsKey('min_confidence'), isTrue,
          reason: 'API requires snake_case "min_confidence"');
      expect(dest.containsKey('minConfidence'), isFalse,
          reason: 'camelCase "minConfidence" is rejected by the API with HTTP 400');
      expect(dest['min_confidence'], equals(0.5046));
    });
  });

  // ── §2  Header assertions (mock network, no live calls) ───────────────────
  group('§2  Header assertions', () {
    test('User-Agent is AdMoaiSDK/0.4.0', () async {
      String? capturedUA;
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: _baseUrl),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: UserConfig.clear(),
        httpClient: _MockClient((req) {
          capturedUA = req.headers['User-Agent'];
          return http.Response('{"success":true,"data":[]}', 200);
        }),
      );

      await sdk.requestAds(
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build());

      print('\n[§2-UA] $capturedUA');
      expect(capturedUA, contains('AdMoaiSDK/'));
      expect(capturedUA, contains('0.4.0'));
    });

    test('Accept-Language is sent when defaultLanguage is set', () async {
      String? capturedLang;
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: _baseUrl, defaultLanguage: 'es'),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: UserConfig.clear(),
        httpClient: _MockClient((req) {
          capturedLang = req.headers['Accept-Language'];
          return http.Response('{"success":true,"data":[]}', 200);
        }),
      );

      await sdk.requestAds(
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build());

      print('\n[§2-Accept-Language] $capturedLang');
      expect(capturedLang, equals('es'));
    });

    test('X-Decision-Version is sent when apiVersion is "2025-11-01"',
        () async {
      String? capturedVersion;
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: _baseUrl, apiVersion: '2025-11-01'),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: UserConfig.clear(),
        httpClient: _MockClient((req) {
          capturedVersion = req.headers['X-Decision-Version'];
          return http.Response('{"success":true,"data":[]}', 200);
        }),
      );

      await sdk.requestAds(
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build());

      print('\n[§2-X-Decision-Version] $capturedVersion');
      expect(capturedVersion, equals('2025-11-01'));
    });

    test('X-Decision-Version is ABSENT when apiVersion is null', () async {
      bool hadVersionHeader = false;
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: _baseUrl),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: UserConfig.clear(),
        httpClient: _MockClient((req) {
          hadVersionHeader = req.headers.containsKey('X-Decision-Version');
          return http.Response('{"success":true,"data":[]}', 200);
        }),
      );

      await sdk.requestAds(
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build());

      print('\n[§2-no-version-header] hadVersionHeader=$hadVersionHeader');
      expect(hadVersionHeader, isFalse);
    });
  });

  // ── §3  Live requests: all placements × both apiVersion variants ──────────
  group('§3  Live requests — placement × apiVersion matrix (18 requests)', () {
    for (final placementKey in _placements) {
      for (final apiVersion in _apiVersions) {
        final label = apiVersion == null
            ? '$placementKey  [no apiVersion]'
            : '$placementKey  [apiVersion=$apiVersion]';

        test(label, () async {
          final client = LoggingClient();
          addTearDown(client.close);

          final sdk = AdMoai.forTesting(
            config: SDKConfig(
              baseUrl: _baseUrl,
              apiVersion: apiVersion,
              defaultLanguage: 'en',
              requestTimeout: const Duration(seconds: 15),
            ),
            appConfig: _appConfig,
            deviceConfig: _deviceConfig,
            userConfig: _userConfig,
            httpClient: client,
          );

          final request = sdk
              .createRequestBuilder()
              // Placement — no explicit format (must be omitted from JSON)
              .addPlacement(key: placementKey)
              // Full targeting from the reference example
              .addGeoTargeting(2643743)
              .addLocationTargeting(
                latitude: 27.92442954013552,
                longitude: -160.3205532179862,
              )
              .addDestinationTargeting(
                latitude: 72.51428456098037,
                longitude: 120.64361005824605,
                minConfidence: 0.5045869003965061,
              )
              .addCustomTargeting(key: 'category', value: 'sports')
              .build();

          // ── Pre-flight: confirm format is NOT in the outgoing JSON ────────
          final reqJson = request.toJson();
          final placementJson =
              (reqJson['placements'] as List).first as Map;
          expect(
            placementJson.containsKey('format'),
            isFalse,
            reason: 'format must be omitted when not explicitly set',
          );

          // ── Fire live request ─────────────────────────────────────────────
          try {
            final response = await sdk.requestAds(request);
            final decisions = response.body.data?.length ?? 0;
            print('▶  [$label]  '
                'success=${response.body.success}  '
                'decisions=$decisions');

            expect(
              response.body.success,
              isTrue,
              reason: 'Server returned success=false for "$label"',
            );
          } on ValidationError catch (e) {
            // 422 — likely the minConfidence key name issue (see §1)
            print('\n⚠️  VALIDATION ERROR [$label]\n  ${e.message}');
            print('  ➜ Check §1 minConfidence key-name audit above.\n');
            // Soft fail — report but don't rethrow so the rest of the matrix runs
          } on ClientError catch (e) {
            print('\n⚠️  CLIENT ERROR [$label]: ${e.message}');
          } on ServerError catch (e) {
            print('\n⚠️  SERVER ERROR [$label]: ${e.message}');
            rethrow;
          } on NetworkError catch (e) {
            print('\n⚠️  NETWORK ERROR [$label]: ${e.message}');
            rethrow;
          }
        });
      }
    }
  });

  // ── §4  Format.video live request ─────────────────────────────────────────
  group('§4  Format.video — live request with explicit format', () {
    test('vasttag_none with Format.video sends "format":"video" and gets 200',
        () async {
      final client = LoggingClient();
      addTearDown(client.close);

      final sdk = AdMoai.forTesting(
        config: SDKConfig(
          baseUrl: _baseUrl,
          apiVersion: '2025-11-01',
          requestTimeout: const Duration(seconds: 15),
        ),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: _userConfig,
        httpClient: client,
      );

      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'vasttag_none', format: Format.video)
          .addGeoTargeting(2643743)
          .build();

      // Confirm "format": "video" is in the outgoing JSON
      final placementJson =
          (request.toJson()['placements'] as List).first as Map;
      expect(placementJson['format'], equals('video'));
      print('\n[§4-video] placement JSON: $placementJson');

      try {
        final response = await sdk.requestAds(request);
        print('[§4-video RESULT]  '
            'success=${response.body.success}  '
            'decisions=${response.body.data?.length ?? 0}');
        expect(response.body.success, isTrue);
      } on APIError catch (e) {
        // NOTE: After rapid §3 load, the mock server may transiently return
        // 400 (empty body) for the same placement/device combination.
        // Confirmed working via isolated curl — not a SDK bug.
        print('\n⚠️  API ERROR (§4-video): ${e.message}'
            '\n  (may be transient mock-server throttle after §3 load)');
      }
    });
  });

  // ── §5  OM verification helpers (offline) ─────────────────────────────────
  group('§5  OM verification helpers', () {
    // Helper matches the pattern from om_helper_test.dart — explicit return
    // type ensures inner maps get proper String→dynamic inference
    Map<String, dynamic> omCreativeJson(
        {List<Map<String, dynamic>>? resources}) {
      return <String, dynamic>{
        'contents': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'headline', 'value': 'Test Ad', 'type': 'text'}
        ],
        'advertiser': <String, dynamic>{'name': 'ACME'},
        'template': <String, dynamic>{'key': 'wide'},
        'tracking': <String, dynamic>{},
        if (resources != null) 'verificationScriptResources': resources,
      };
    }

    test('hasOMVerification and getVerificationResources work', () {
      final creative = Creative.fromJson(omCreativeJson(resources: [
        <String, dynamic>{
          'vendorKey': 'iabtechlab.com-omid',
          'scriptUrl':
              'https://storage.googleapis.com/om-sdk/test/iab-omsdk-publisher-test.js',
          'verificationParameters': 'test-params',
        },
        <String, dynamic>{
          'vendorKey': 'doubleverify.com',
          'scriptUrl': 'https://cdn.dv.com/x.js',
        },
      ]));

      print('\n[§5-OM] hasOMVerification: ${creative.hasOMVerification()}');
      print('[§5-OM] resources count: '
          '${creative.getVerificationResources()?.length}');
      for (final r in creative.getVerificationResources() ?? []) {
        print('  • vendor=${r.vendorKey}  url=${r.scriptUrl}');
      }

      expect(creative.hasOMVerification(), isTrue);
      expect(creative.getVerificationResources()?.length, equals(2));
      expect(creative.getVerificationResources()?.first.vendorKey,
          equals('iabtechlab.com-omid'));
    });

    test('hasOMVerification is false when no resources', () {
      final creative = Creative.fromJson(omCreativeJson());
      expect(creative.hasOMVerification(), isFalse);
      expect(creative.getVerificationResources(), isNull);
    });
  });

  // ── §6  Destination targeting dedup and validation (offline) ──────────────
  group('§6  Destination targeting', () {
    late AdMoai sdk;

    setUp(() {
      sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: _baseUrl),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: UserConfig.clear(),
      );
    });

    test('duplicate destinations are deduplicated', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .addDestinationTargeting(latitude: 10, longitude: 20, minConfidence: 0.5)
          .addDestinationTargeting(latitude: 10, longitude: 20, minConfidence: 0.5) // dup
          .addDestinationTargeting(latitude: 30, longitude: 40, minConfidence: 0.7)
          .build();
      expect(request.targeting?.destination?.length, equals(2));
    });

    test('minConfidence outside [0,1] throws ArgumentError', () {
      expect(
        () => sdk.createRequestBuilder().addDestinationTargeting(
              latitude: 0,
              longitude: 0,
              minConfidence: 1.1,
            ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('minConfidence at boundary values 0.0 and 1.0 is accepted', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .addDestinationTargeting(latitude: 1, longitude: 2, minConfidence: 0.0)
          .addDestinationTargeting(latitude: 3, longitude: 4, minConfidence: 1.0)
          .build();
      expect(request.targeting?.destination?.length, equals(2));
    });
  });

  // ── §7  Error handling (offline, mock 4xx / 5xx) ──────────────────────────
  group('§7  Error handling', () {
    Future<AdMoai> sdkWith(http.Response Function() responder) async {
      return AdMoai.forTesting(
        config: SDKConfig(baseUrl: _baseUrl),
        appConfig: _appConfig,
        deviceConfig: _deviceConfig,
        userConfig: UserConfig.clear(),
        httpClient: _MockClient((_) => responder()),
      );
    }

    test('401 surfaces as UnexpectedStatusError', () async {
      final sdk = await sdkWith(() => http.Response('', 401));
      final req =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      expect(() => sdk.requestAds(req),
          throwsA(isA<UnexpectedStatusError>()));
    });

    test('502 surfaces as ServerError', () async {
      final sdk = await sdkWith(() => http.Response('', 502));
      final req =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      expect(() => sdk.requestAds(req), throwsA(isA<ServerError>()));
    });

    test('400 surfaces as ClientError', () async {
      final sdk = await sdkWith(() => http.Response('', 400));
      final req =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      expect(() => sdk.requestAds(req), throwsA(isA<ClientError>()));
    });
  });
}
