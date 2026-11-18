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

    test(
        '400 with the engine error body exposes code 10009 and its message '
        '(gate OFF, device carrier sent)', () async {
      // The exact body the engine answered in B5-flutter QA item 1.2.
      const body = '{"success":false,"data":null,"errors":[{"code":10009,'
          '"message":"The body contains an unknown field `\\"carrier\\"`"}],'
          '"warnings":null}';
      final sdk = await _sdkWithResponse(() => http.Response(body, 400));
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      try {
        await sdk.requestAds(request);
        fail('expected ClientError');
      } on ClientError catch (e) {
        expect(e.status, equals(HTTPStatus.badRequest));
        expect(e.errors.map((x) => x.code), equals([10009]));
        expect(e.errors.single.message,
            equals('The body contains an unknown field `"carrier"`'));
        expect(e.message, contains('[10009]'));
      }
    });

    test(
        '400 with an empty or non-JSON body has no errors and stays a '
        'ClientError', () async {
      for (final body in ['', 'Bad Request', '[]', '{"errors":"x"}']) {
        final sdk = await _sdkWithResponse(() => http.Response(body, 400));
        final request =
            (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
        try {
          await sdk.requestAds(request);
          fail('expected ClientError for body "$body"');
        } on ClientError catch (e) {
          expect(e.status, equals(HTTPStatus.badRequest));
          expect(e.errors, isEmpty);
          expect(e.message, equals('Client error: 400 - Bad Request'));
        }
      }
    });

    test('a malformed entry is dropped and the valid one kept', () async {
      final sdk = await _sdkWithResponse(() => http.Response(
          '{"errors":[{"code":"x"},{"code":10009,"message":"m"}]}', 400));
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      try {
        await sdk.requestAds(request);
        fail('expected ClientError');
      } on ClientError catch (e) {
        expect(e.errors.map((x) => x.code), equals([10009]));
      }
    });

    test('other mapped 4xx (404, 429) carry the body errors too', () async {
      for (final status in [404, 429]) {
        final sdk = await _sdkWithResponse(() =>
            http.Response('{"errors":[{"code":42,"message":"why"}]}', status));
        final request =
            (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
        try {
          await sdk.requestAds(request);
          fail('expected ClientError for $status');
        } on ClientError catch (e) {
          expect(e.status.code, equals(status));
          expect(e.errors.single.code, equals(42));
        }
      }
    });

    test(
        'an unmapped 4xx (401) keeps UnexpectedStatusError and carries the '
        'body errors', () async {
      final sdk = await _sdkWithResponse(() =>
          http.Response('{"errors":[{"code":7,"message":"no key"}]}', 401));
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      try {
        await sdk.requestAds(request);
        fail('expected UnexpectedStatusError');
      } on UnexpectedStatusError catch (e) {
        expect(e.statusCode, equals(401));
        expect(e.errors.single.code, equals(7));
      }
    });

    test(
        '422 with a malformed entry beside a valid one is a ValidationError '
        'with the valid one', () async {
      final sdk = await _sdkWithResponse(() => http.Response(
          '{"errors":[{"code":null},{"code":10028,"message":"m"}]}', 422));
      final request =
          (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
      try {
        await sdk.requestAds(request);
        fail('expected ValidationError');
      } on ValidationError catch (e) {
        expect(e.errors.single.code, equals(10028));
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
