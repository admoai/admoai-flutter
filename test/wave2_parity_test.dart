import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

/// Wave 2 cross-SDK parity guards.
///
/// Each group pins one divergence found by walking the engine contract against all three SDKs.
/// Reverting the corresponding fix must make the group fail — a guard that cannot fail is not a
/// guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://mock.api.admoai.com';

  group('F6 — tracking failures must not log the URL', () {
    test('a failed tracking request logs the error type, never the ?e= token', () async {
      final records = <LogRecord>[];
      final logger = Logger('F6Test');
      logger.onRecord.listen(records.add);

      // ClientException stringifies as "ClientException: <message>, uri=<uri>", so interpolating
      // the error object wrote the whole tracking URL — including the opaque serve-time token —
      // into publisher logs. Connection refusals and TLS failures take this path routinely.
      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection refused', request.url);
      });

      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01', logger: logger),
        httpClient: mockClient,
      );

      const secretToken = 'v1.aVerySecretOpaqueServeTimeToken';
      sdk.fireTracking('https://tracking.example.com/v1/tracking?e=$secretToken');
      await Future.delayed(Duration.zero);

      expect(records, isNotEmpty);
      final logged = records.map((r) => r.message).join('\n');
      expect(logged, isNot(contains(secretToken)));
      expect(logged, isNot(contains('tracking.example.com')));
      expect(logged, contains('ClientException'));
    });
  });

  group('F7 — errors and warnings on a 200 response', () {
    Future<APIResponse<DecisionResponse>> respondWith(String body) {
      final mockClient = MockClient((_) async => http.Response(
            body,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: mockClient,
      );
      return sdk.requestAds(
        sdk.createRequestBuilder().addPlacement(key: 'home').build(),
      );
    }

    test('warnings on a 200 are surfaced, not discarded', () async {
      // The engine returns warnings on a 200 in staging — that is where a publisher is meant to
      // find a misconfiguration before production. They were hardcoded to [] here, so Flutter
      // integrators saw none of them while iOS and Android surfaced them.
      final response = await respondWith(jsonEncode({
        'success': true,
        'data': [
          {'placement': 'home', 'creatives': []}
        ],
        'errors': [],
        'warnings': [
          {'code': 20001, 'message': 'placement home has no active ads'}
        ],
      }));

      expect(response.body.warnings, hasLength(1));
      expect(response.body.warnings.first.code, equals(20001));
      expect(
        response.body.warnings.first.message,
        equals('placement home has no active ads'),
      );
    });

    test('errors on a 200 are surfaced', () async {
      final response = await respondWith(jsonEncode({
        'success': true,
        'data': [],
        'errors': [
          {'code': 10001, 'message': 'partial failure'}
        ],
      }));

      expect(response.body.errors, hasLength(1));
      expect(response.body.errors.first.code, equals(10001));
    });

    test('malformed entries are dropped without throwing', () async {
      // Tolerant Reader: one bad entry must not fail the response, consistent with every other
      // list in the parser.
      final response = await respondWith(jsonEncode({
        'success': true,
        'data': [],
        'errors': [
          {'code': 1, 'message': 'ok'},
          'garbage',
          {'code': 'not-an-int', 'message': 'bad'},
          {'message': 'no code'},
        ],
        'warnings': 'not-a-list',
      }));

      expect(response.body.errors, hasLength(1));
      expect(response.body.errors.first.code, equals(1));
      expect(response.body.warnings, isEmpty);
    });

    test('an absent errors/warnings envelope yields empty lists', () async {
      final response = await respondWith(jsonEncode({
        'success': true,
        'data': [
          {'placement': 'home', 'creatives': []}
        ],
      }));

      expect(response.body.errors, isEmpty);
      expect(response.body.warnings, isEmpty);
    });
  });

  group('F8 — structured verificationParameters survive', () {
    VerificationScriptResource? parse(Object? params) {
      final creative = Creative.fromJson({
        'contents': [],
        'advertiser': {},
        'template': {'key': 't'},
        'tracking': {},
        'verificationScriptResources': [
          {
            'vendorKey': 'doubleverify.com-omid',
            'scriptUrl': 'https://verification.example.com/omid.js',
            'verificationParameters': params,
          }
        ],
      });
      return creative.verificationScriptResources?.single;
    }

    test('an object payload is preserved as JSON text', () {
      // It previously went through a string-only cast, so anything structured became null: the
      // resource still decoded and looked usable while the parameters IAS or DoubleVerify need to
      // attribute a measurement were silently gone.
      final resource = parse({'ctx': 12345, 'tag': 'abc'});

      expect(resource, isNotNull);
      expect(resource!.verificationParameters, isNotNull);
      expect(resource.verificationParameters, contains('12345'));
      expect(resource.verificationParameters, contains('abc'));
    });

    test('an array payload is preserved as JSON text', () {
      final resource = parse(['a', 'b']);
      expect(resource!.verificationParameters, contains('a'));
      expect(resource.verificationParameters, contains('b'));
    });

    test('a plain string still passes through verbatim', () {
      final resource = parse('anId=123&advId=456');
      expect(resource!.verificationParameters, equals('anId=123&advId=456'));
    });

    test('an explicit null stays null rather than becoming the string "null"', () {
      // null carries no payload; stringifying it would hand the vendor a fake value.
      final resource = parse(null);
      expect(resource!.verificationParameters, isNull);
    });
  });
}
