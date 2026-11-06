import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

const _baseUrl = 'https://mock.api.admoai.com';

// The wire request every existing integration sends today; unset playgroundToken must keep it.
const _liveBody =
    '{"placements":[{"key":"home"}],"user":{"consent":{"gdpr":false}},"device":{},"app":{}}';
const _liveHeaders = {
  'content-type': 'application/json',
  'accept': 'application/json',
  'user-agent': 'AdMoaiSDK/$sdkVersion',
  'x-decision-version': '2025-11-01',
  'accept-language': 'es',
};

Future<http.Request> _send({String? playgroundToken, Logger? logger}) async {
  http.Request? captured;
  final sdk = AdMoai.forTesting(
    config: playgroundToken == null
        ? SDKConfig(
            baseUrl: _baseUrl,
            apiVersion: '2025-11-01',
            defaultLanguage: 'es',
            logger: logger,
          )
        : SDKConfig(
            baseUrl: _baseUrl,
            apiVersion: '2025-11-01',
            defaultLanguage: 'es',
            playgroundToken: playgroundToken,
            logger: logger,
          ),
    httpClient: MockClient((request) async {
      captured = request;
      return http.Response('{"success":true,"data":[]}', 200);
    }),
  );
  final request =
      (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();
  await sdk.requestAds(request);
  return captured!;
}

Map<String, String> _lower(Map<String, String> h) =>
    h.map((k, v) => MapEntry(k.toLowerCase(), v));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unset playgroundToken sends the live request unchanged', () async {
    final r = await _send();

    expect(r.method, 'POST');
    expect(r.url.toString(), '$_baseUrl/v1/decision');
    expect(_lower(r.headers), equals(_liveHeaders));
    expect(r.body, equals(_liveBody));
  });

  test('empty playgroundToken is treated as unset', () async {
    final r = await _send(playgroundToken: '');

    expect(r.url.toString(), '$_baseUrl/v1/decision');
    expect(_lower(r.headers), equals(_liveHeaders));
    expect(r.body, equals(_liveBody));
  });

  test('playgroundToken routes to the playground endpoint with its header',
      () async {
    final r = await _send(playgroundToken: 'pg_test_123');

    expect(r.method, 'POST');
    expect(r.url.toString(), '$_baseUrl/v1/playground/decision');
    expect(
      _lower(r.headers),
      equals({..._liveHeaders, 'x-playground-token': 'pg_test_123'}),
    );
    expect(r.body, equals(_liveBody));
  });

  test('X-Playground-Reason on a no-ad response is logged', () async {
    final logs = <LogRecord>[];
    final logger = Logger('pg-reason')..onRecord.listen(logs.add);
    final sdk = AdMoai.forTesting(
      config: SDKConfig(
        baseUrl: _baseUrl,
        playgroundToken: 'pg_revoked',
        logger: logger,
      ),
      httpClient: MockClient((_) async => http.Response(
            '{"success":true,"data":[]}',
            200,
            headers: {'x-playground-reason': 'revoked'},
          )),
    );
    final request =
        (sdk.createRequestBuilder()..addPlacement(key: 'home')).build();

    final response = await sdk.requestAds(request);

    expect(response.body.data, isEmpty);
    expect(
      logs.where(
          (l) => l.level == Level.WARNING && l.message.contains('revoked')),
      hasLength(1),
    );
  });

  test('tracking beacons carry no playground header', () async {
    final captured = <http.BaseRequest>[];
    final sdk = AdMoai.forTesting(
      config: SDKConfig(baseUrl: _baseUrl, playgroundToken: 'pg_test_123'),
      httpClient: MockClient((request) async {
        captured.add(request);
        return http.Response('', 200);
      }),
    );

    sdk.fireTracking('https://t.example/v1/tracking?e=x');
    await Future<void>.delayed(Duration.zero);

    expect(captured, hasLength(1));
    expect(captured.single.url.toString(), 'https://t.example/v1/tracking?e=x');
    expect(
        _lower(captured.single.headers), isNot(contains('x-playground-token')));
  });
}
