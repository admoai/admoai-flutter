import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/dispatch_recording_client.dart';

// Carousel slide tracking — the helpers a publisher's app calls per slide.
//
// Feature: A Carousel's slides report their own views and clicks
//   As a publisher's tech team
//   I want one call per slide view and per slide click
//   So that each slide is counted once per served response and every tap is billed once
//
// The shared cross-SDK scenarios (F16-F20) run in `fixture_scenarios_test.dart`; these tests
// pin the same rules on hand-built creatives, plus the edges the manifest does not name.
// Mirrors the iOS suite (`SlideTrackingTests.swift`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> slideJson(int n,
      {bool views = true, bool clicks = true}) {
    return {
      'slideId': 'slide_$n',
      'position': n,
      'contents': <dynamic>[],
      'tracking': {
        if (views)
          'views': [
            {'key': 'slide_view', 'url': 'https://t/slide$n/view'}
          ],
        if (clicks)
          'clicks': [
            {'key': 'default', 'url': 'https://t/slide$n/click'}
          ],
      },
    };
  }

  Creative creative(List<Map<String, dynamic>> slides) => Creative.fromJson({
        'contents': [
          {'key': 'slides', 'type': 'slides', 'value': slides}
        ],
        'advertiser': {'name': 'Acme'},
        'tracking': {
          'thirdPartyTrackers': [
            {
              'trackerId': 'any',
              'eventType': 'click',
              'matchType': 'any',
              'url': 'https://agency.example/any'
            },
            {
              'trackerId': 'default',
              'eventType': 'click',
              'matchType': 'specific',
              'eventKey': 'default',
              'url': 'https://agency.example/default'
            },
            {
              'trackerId': 'other',
              'eventType': 'click',
              'matchType': 'specific',
              'eventKey': 'save',
              'url': 'https://agency.example/other'
            },
            {
              'trackerId': 'imp',
              'eventType': 'impression',
              'url': 'https://agency.example/imp'
            },
          ],
        },
      });

  (AdMoai, DispatchRecordingClient, List<String>) sdkWithCapture() {
    final received = <String>[];
    final client = DispatchRecordingClient(MockClient((request) async {
      received.add(request.url.toString());
      return http.Response('', 200);
    }));
    final sdk = AdMoai.forTesting(
      config: SDKConfig(
        baseUrl: 'https://mock.api.admoai.com',
        apiVersion: '2025-11-01',
      ),
      httpClient: client,
    );
    return (sdk, client, received);
  }

  /// The unawaited fire-and-forget futures need event-loop turns to complete.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a slide view is sent once per response', () async {
    final c = creative([slideJson(1)]);
    final (sdk, client, received) = sdkWithCapture();

    sdk.trackSlideView(c.slides[0]);
    sdk.trackSlideView(c.slides[0]);
    await settle();

    expect(client.dispatched, ['https://t/slide1/view']);
    expect(received, ['https://t/slide1/view']);
  });

  test('bulk views send each slide once', () async {
    final c = creative([slideJson(1), slideJson(2), slideJson(3)]);
    final (sdk, client, _) = sdkWithCapture();

    sdk.trackSlideViews(c.slides);
    sdk.trackSlideViews(c.slides.sublist(1));
    await settle();

    expect(client.dispatched, [
      'https://t/slide1/view',
      'https://t/slide2/view',
      'https://t/slide3/view',
    ]);
  });

  test('a click before the view sends the view, then the click', () async {
    final c = creative([slideJson(1)]);
    final (sdk, client, _) = sdkWithCapture();

    sdk.trackSlideClick(c.slides[0], c);
    await settle();

    // Dispatch order is the contract; arrival order at the mock is the client's.
    expect(client.dispatched.where((u) => u.startsWith('https://t/')),
        ['https://t/slide1/view', 'https://t/slide1/click']);
    expect(client.dispatched, hasLength(4), reason: 'view, click, 2 fan-out');
  });

  test('a click after the view sends only the click', () async {
    final c = creative([slideJson(1)]);
    final (sdk, client, _) = sdkWithCapture();
    sdk.trackSlideView(c.slides[0]);
    await settle();
    client.dispatched.clear();

    sdk.trackSlideView(c.slides[0]);
    sdk.trackSlideClick(c.slides[0], c);
    await settle();

    expect(client.dispatched.where((u) => u.startsWith('https://t/')),
        ['https://t/slide1/click']);
    expect(client.dispatched, hasLength(3), reason: 'click + 2 fan-out');
  });

  test('a tap on a slide without a click tracker still counts its view',
      () async {
    final c = creative([slideJson(1, clicks: false)]);
    final (sdk, client, _) = sdkWithCapture();

    sdk.trackSlideClick(c.slides[0], c);
    sdk.trackSlideClick(c.slides[0], c);
    await settle();

    expect(client.dispatched, ['https://t/slide1/view'],
        reason: 'the tap proves the slide was seen; no click, no fan-out');
  });

  test('every click fans out the applicable third-party trackers once',
      () async {
    final c = creative([slideJson(1)]);
    final (sdk, client, _) = sdkWithCapture();

    sdk.trackSlideClick(c.slides[0], c);
    sdk.trackSlideClick(c.slides[0], c);
    await settle();

    expect(client.dispatched, hasLength(7),
        reason: 'view, 2 clicks, 4 fan-out');
    final thirdParty = client.dispatched
        .where((u) => u.startsWith('https://agency.example/'))
        .toList()
      ..sort();
    expect(thirdParty, [
      'https://agency.example/any',
      'https://agency.example/any',
      'https://agency.example/default',
      'https://agency.example/default',
    ]);
  });

  test('a slide view never fans out third-party trackers', () async {
    final c = creative([slideJson(1), slideJson(2)]);
    final (sdk, client, _) = sdkWithCapture();

    sdk.trackSlideViews(c.slides);
    await settle();

    expect(client.dispatched, hasLength(2));
    expect(client.dispatched.every((u) => u.startsWith('https://t/')), isTrue);
  });

  test('a slide without tracking is a no-op', () async {
    final c = creative([
      {'slideId': 'slide_1', 'position': 1, 'contents': <dynamic>[]},
      slideJson(2, views: false, clicks: false),
    ]);
    final (sdk, client, _) = sdkWithCapture();

    sdk.trackSlideViews(c.slides);
    sdk.trackSlideClick(c.slides[0], c);
    sdk.trackSlideClick(c.slides[1], c);
    await settle();

    expect(client.dispatched, isEmpty,
        reason: 'no tracker at all: nothing to send, and no fan-out');
  });

  test('slide and pin views keep independent ledgers', () async {
    // The same URL is a pin view and a slide view: claiming it as one must not claim it as
    // the other.
    final c = Creative.fromJson({
      'contents': [
        {
          'key': 'slides',
          'type': 'slides',
          'value': [
            {
              'slideId': 'slide_1',
              'position': 1,
              'contents': <dynamic>[],
              'tracking': {
                'views': [
                  {'key': 'slide_view', 'url': 'https://t/shared'}
                ],
              },
            }
          ],
        },
        {
          'key': 'matched_points',
          'type': 'matched_points',
          'value': [
            {
              'id': 'p1',
              'name': 'P1',
              'latitude': 1,
              'longitude': 1,
              'distance': 1,
              'tracking': {
                'views': [
                  {'key': 'default', 'url': 'https://t/shared'}
                ],
              },
            }
          ],
        },
      ],
      'advertiser': {'name': 'Acme'},
      'tracking': <String, dynamic>{},
    });
    final (sdk, client, _) = sdkWithCapture();

    sdk.trackPointView(c.matchedPoints[0]);
    sdk.trackSlideView(c.slides[0]);
    sdk.trackPointView(c.matchedPoints[0]);
    sdk.trackSlideView(c.slides[0]);
    await settle();

    expect(client.dispatched, ['https://t/shared', 'https://t/shared'],
        reason: 'once as a pin, once as a slide');
  });

  /// The Carousel has no creative-level click: `fireClick` records nothing for it, and the
  /// third-party trackers do not fan out for a click the creative cannot record.
  test('fireClick on a creative without a click sends nothing', () async {
    final c = creative([slideJson(1)]);
    final (sdk, client, _) = sdkWithCapture();

    sdk.fireClick(c.tracking);
    await settle();

    expect(client.dispatched, isEmpty);
  });
}
