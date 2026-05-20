import 'package:flutter_test/flutter_test.dart';
import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const baseUrl = 'https://mock.api.admoai.com';

Future<AdMoai> _sdkWithResponse(http.Response Function() responder) async {
  const channel = MethodChannel('flutter_timezone');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => 'UTC');

  final mockClient = MockClient((request) async => responder());

  return AdMoai.forTesting(
    config: SDKConfig(baseUrl: baseUrl),
    httpClient: mockClient,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unexpected HTTP status codes are preserved', () {
    test('401 surfaces as UnexpectedStatusError(401)', () async {
      final sdk = await _sdkWithResponse(
        () => http.Response('', 401),
      );

      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();

      try {
        await sdk.requestAds(request);
        fail('expected UnexpectedStatusError to be thrown');
      } on UnexpectedStatusError catch (e) {
        expect(e.statusCode, equals(401));
      }
    });

    test('418 surfaces as UnexpectedStatusError(418)', () async {
      final sdk = await _sdkWithResponse(
        () => http.Response('', 418),
      );

      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();

      try {
        await sdk.requestAds(request);
        fail('expected UnexpectedStatusError to be thrown');
      } on UnexpectedStatusError catch (e) {
        expect(e.statusCode, equals(418));
      }
    });

    test('451 is catchable as APIError', () async {
      final sdk = await _sdkWithResponse(
        () => http.Response('', 451),
      );

      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();

      try {
        await sdk.requestAds(request);
        fail('expected APIError to be thrown');
      } on APIError catch (e) {
        expect(e, isA<UnexpectedStatusError>());
        expect((e as UnexpectedStatusError).statusCode, equals(451));
      }
    });
  });

  group('5xx range maps to ServerError', () {
    test('502 surfaces as ServerError(502)', () async {
      final sdk = await _sdkWithResponse(
        () => http.Response('', 502),
      );

      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();

      try {
        await sdk.requestAds(request);
        fail('expected ServerError to be thrown');
      } on ServerError catch (e) {
        expect(e.code, equals(502));
      }
    });

    test('503 surfaces as ServerError(503)', () async {
      final sdk = await _sdkWithResponse(
        () => http.Response('', 503),
      );

      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();

      try {
        await sdk.requestAds(request);
        fail('expected ServerError to be thrown');
      } on ServerError catch (e) {
        expect(e.code, equals(503));
      }
    });
  });

  group('Mapped statuses keep their dedicated typed errors', () {
    test('400 still throws ClientError(badRequest)', () async {
      final sdk = await _sdkWithResponse(
        () => http.Response('', 400),
      );
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      try {
        await sdk.requestAds(request);
        fail('expected ClientError');
      } on ClientError catch (e) {
        expect(e.status, equals(HTTPStatus.badRequest));
      }
    });

    test('422 with errors body still throws ValidationError', () async {
      final sdk = await _sdkWithResponse(
        () => http.Response(
          '{"errors": [{"code": 1, "message": "bad"}]}',
          422,
        ),
      );
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      try {
        await sdk.requestAds(request);
        fail('expected ValidationError');
      } on ValidationError catch (e) {
        expect(e.errors.length, equals(1));
        expect(e.errors.first.code, equals(1));
        expect(e.errors.first.message, equals('bad'));
      }
    });

    test('422 with empty body still throws ClientError(unprocessableEntity)',
        () async {
      final sdk = await _sdkWithResponse(
        () => http.Response('', 422),
      );
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      try {
        await sdk.requestAds(request);
        fail('expected ClientError');
      } on ClientError catch (e) {
        expect(e.status, equals(HTTPStatus.unprocessableEntity));
      }
    });
  });
}
