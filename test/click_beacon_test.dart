import 'dart:io' as io;

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Feature: a click beacon records the click and nothing else.
///
/// `/v1/tracking` answers a click with `302 Location: <destination>` so a
/// browser can record and land in one hop. `fireClick` is a background beacon,
/// not navigation: the app opens the destination itself, so the SDK must take
/// the first response as final and never request the `Location`. On Android
/// the same bug made every click on a publisher's banner fail — the
/// advertiser's host rejected the beacon's `Accept: application/json` with a
/// 500 — and this package's `http.Client` follows redirects by default too.
void main() {
  /// `flutter_test` can replace `HttpClient` with a stub that answers 400; this
  /// suite needs the real one, because redirect handling lives in it.
  T withRealHttp<T>(T Function() body) =>
      io.HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

  group('fireClick against a real socket, default client', () {
    late io.HttpServer server;
    late List<String> paths;

    setUp(() async {
      paths = [];
      server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        paths.add(request.uri.path);
        final response = request.response;
        if (request.uri.path == '/v1/tracking') {
          response
            ..statusCode = 302
            ..headers.set('location', 'http://127.0.0.1:${server.port}/landing');
        } else {
          // What a content-negotiating landing page answers a JSON request with.
          response
            ..statusCode = 500
            ..write('{"error":"Only HTML requests are supported here"}');
        }
        await response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('a 302 click is sent once and its Location is never requested',
        () async {
      await withRealHttp(() async {
        final sdk = AdMoai.forTesting(
          config: SDKConfig(baseUrl: 'http://127.0.0.1:${server.port}'),
        );
        final clickUrl = 'http://127.0.0.1:${server.port}/v1/tracking?e=click';

        sdk.fireClick(Tracking(clicks: [TrackingItem(key: 'default', url: clickUrl)]));
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(paths, equals(['/v1/tracking']),
            reason: 'the SDK requested the redirect\'s Location');
        sdk.dispose();
      });
    });
  });

  group('fireClick with an injected client', () {
    const clickUrl = 'https://mock.api.admoai.com/v1/tracking?e=click';
    final clicks = Tracking(clicks: [TrackingItem(key: 'default', url: clickUrl)]);

    test('a 302 click asks the client not to follow it, and sends nothing else',
        () async {
      final sent = <http.BaseRequest>[];
      final client = MockClient.streaming((request, _) async {
        sent.add(request);
        return http.StreamedResponse(const Stream.empty(), 302,
            headers: {'location': 'https://shop.advertiser.example/landing'});
      });
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: 'https://mock.api.admoai.com'),
        httpClient: client,
      );

      sdk.fireClick(clicks);
      await Future<void>.delayed(Duration.zero);

      expect(sent.map((r) => r.url.toString()), equals([clickUrl]));
      expect(sent.single.followRedirects, isFalse);
    });

    test('a 2xx click is sent once and nothing else', () async {
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response('', 202);
      });
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: 'https://mock.api.admoai.com'),
        httpClient: client,
      );

      sdk.fireClick(clicks);
      await Future<void>.delayed(Duration.zero);

      expect(sent.map((r) => r.url.toString()), equals([clickUrl]));
    });

    test('a click key with no tracking URL sends nothing', () async {
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response('', 202);
      });
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: 'https://mock.api.admoai.com'),
        httpClient: client,
      );

      sdk.fireClick(clicks, key: 'cta_tap');
      await Future<void>.delayed(Duration.zero);

      expect(sent, isEmpty);
    });
  });
}

class _RealHttpOverrides extends io.HttpOverrides {}
