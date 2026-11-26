@Tags(['device'])
library;

import 'dart:async';
import 'dart:convert' show base64;
import 'dart:io'
    show
        ContentType,
        HttpServer,
        HttpStatus,
        InternetAddress,
        Platform,
        SecurityContext;

import 'package:admoai/src/interactive/secure_form_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The device proof of `lib/src/interactive/secure_form_surface.feature`: the same scenarios,
/// by the same titles, on a real web view with real pages over https. (test/secure_form_surface_test.dart
/// binds the feature to the JVM and Dart tests; this file is what a device proves.)
///
/// Needs a device, so `flutter test` over test/ never runs it (tag `device`, plus the directory).
/// CI runs it on an Android emulator (.github/workflows/interactive-instrumented.yml); iOS is
/// run by hand (the iOS section of the B7 Flutter runbook). Both go through
/// `tool/host_app.sh`, which copies this directory into the generated host app:
///
///   tool/host_app.sh build/host_app
///   cd build/host_app && flutter test integration_test/secure_form_surface_test.dart -d emulator-5554
///
/// Android serves the fixtures itself: the debug build of the plugin answers
/// `https://appassets.androidplatform.net/assets/...` (and a second origin,
/// `https://other.appassets.example/assets/...`) from the host app's assets, with no network and
/// no certificate. The plugin's release and profile builds have no such hook. iOS cannot, so it is
/// given a TLS server that serves integration_test/assets/ on two origins:
///
///   --dart-define=FIXTURE_BASE=https://localhost:8443
///   --dart-define=FIXTURE_FOREIGN_BASE=https://localhost:8444
///
/// The two frame scenarios also need, on iOS, the same certificate and key, base64-encoded, so the
/// test can serve two recording origins itself (see [_RecordingOrigin]):
///
///   --dart-define=FIXTURE_TLS_CERT_B64="$(base64 -i cert.pem)"
///   --dart-define=FIXTURE_TLS_KEY_B64="$(base64 -i key.pem)"
const _androidBase =
    'https://appassets.androidplatform.net/assets/flutter_assets/integration_test/assets';
const _androidForeignBase =
    'https://other.appassets.example/assets/flutter_assets/integration_test/assets';
const _base = String.fromEnvironment('FIXTURE_BASE');
const _foreignBase = String.fromEnvironment('FIXTURE_FOREIGN_BASE');
const _tlsCertB64 = String.fromEnvironment('FIXTURE_TLS_CERT_B64');
const _tlsKeyB64 = String.fromEnvironment('FIXTURE_TLS_KEY_B64');

/// `--dart-define=EXPECT_SUPPORTED=false` on a device that cannot host the view (iOS 13).
const _expectSupported =
    bool.fromEnvironment('EXPECT_SUPPORTED', defaultValue: true);

const _instanceId = 'form_instance_01KG000000000000000000N001';
const _channelId = 'chan_example_0000000001';

/// The test-only methods of the Android debug plugin (src/debug FormTestHooks).
const _hooks = MethodChannel('admoai/lead_form');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final surface = PlatformLeadFormSurface.instance;
  late String base;
  late String foreign;
  var counter = 0;

  setUpAll(() async {
    if (Platform.isAndroid) {
      base = _base.isEmpty ? _androidBase : _base;
      foreign = _foreignBase.isEmpty ? _androidForeignBase : _foreignBase;
      await _hooks.invokeMethod<void>('testServeFixtures');
    } else if (Platform.isIOS) {
      if (_base.isEmpty || _foreignBase.isEmpty) {
        fail('iOS cannot serve the fixtures itself. '
            'Why: the form only loads over https. '
            'Fix: serve integration_test/assets/ over TLS on two origins and pass '
            '--dart-define=FIXTURE_BASE=... --dart-define=FIXTURE_FOREIGN_BASE=... '
            '(see the iOS section of the B7 Flutter runbook).');
      }
      base = _base;
      foreign = _foreignBase;
    } else {
      fail('This suite runs on an Android or iOS device only.');
    }
  });

  tearDownAll(() async {
    if (Platform.isAndroid) await _hooks.invokeMethod<void>('testReset');
  });

  /// A test that creates a surface: skipped on a device that cannot host the view
  /// (EXPECT_SUPPORTED=false), where only the support assertion runs.
  void surfaceTest(String name, WidgetTesterCallback body) =>
      testWidgets(name, body, skip: !_expectSupported);

  /// One form view for one test: created like the SDK does, attached like LeadFormView does.
  Future<_Form> open(
    WidgetTester tester, {
    String page = 'form.html',
    String extra = '',
    String? atBase,
    String? foreignBase,
  }) async {
    final id = 'device_form_${++counter}';
    final foreignParam = Uri.encodeComponent(foreignBase ?? foreign);
    final url = Uri.parse(
        '${atBase ?? base}/$page#instanceId=$_instanceId&channel=$_channelId'
        '&foreign=$foreignParam$extra');
    final form = _Form(id, url, surface);
    await surface.create(id, url);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: Platform.isAndroid
              ? AndroidView(
                  viewType: PlatformLeadFormSurface.viewType,
                  creationParams: <String, Object?>{'id': id},
                  creationParamsCodec: const StandardMessageCodec(),
                )
              : UiKitView(
                  viewType: PlatformLeadFormSurface.viewType,
                  creationParams: <String, Object?>{'id': id},
                  creationParamsCodec: const StandardMessageCodec(),
                ),
        ),
      ),
    ));
    addTearDown(() async {
      await form.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
    return form;
  }

  testWidgets(
      'a device that cannot host the view says so, and the SDK does not advertise',
      (tester) async {
    expect(await LeadFormSurface.isSupported(), _expectSupported);
  });

  surfaceTest('the form page at the launch origin reaches the app',
      (tester) async {
    final form = await open(tester);
    await form.waitFor(2);
    expect(form.received, contains('hello'));
  });

  surfaceTest("the form receives the app's messages", (tester) async {
    final form = await open(tester);
    await form.waitFor(2);
    const text = '{"type":"initialize","quote":"\\""}';
    await form.send(text);
    await form.waitFor(3);
    expect(form.received.last, 'echo:$text');
  });

  surfaceTest(
      'the page learns its instance and channel from the launch URL fragment',
      (tester) async {
    final form = await open(tester);
    await form.waitFor(2);
    expect(
        form.received, contains('address:no-query:$_instanceId:$_channelId'));
    if (Platform.isAndroid) {
      expect(
          await _hooks.invokeMethod<String>('testCurrentUrl', {'id': form.id}),
          form.url.toString());
    }
  });

  /// iOS refuses every navigation but the launch URL, frames included, so the frame is never even
  /// requested and nothing in it can reach the app. Android loads the frame and refuses its bridge
  /// messages instead, which is why only Android can wait for the frame's own acknowledgement.
  /// The host page and both frame origins are served by the test, which records every file asked
  /// of them: the host page being fetched over the same TLS setup shows a frame request would
  /// have been seen.
  Future<void> expectFrameNeverRequested(
      WidgetTester tester, String frame) async {
    final host = await _RecordingOrigin.start();
    addTearDown(host.close);
    final other = await _RecordingOrigin.start();
    addTearDown(other.close);
    final form = await open(tester,
        page: 'frame-host.html',
        extra: '&frame=$frame',
        atBase: host.base,
        foreignBase: other.base);
    await host.waitFor('frame-host.html');
    await form.quiet();
    expect(host.requested, ['frame-host.html'],
        reason: 'the frame is never requested from the page origin');
    expect(other.requested, isEmpty,
        reason: 'the frame is never requested from another origin');
    expect(form.received, isEmpty, reason: 'nothing reaches the app');
  }

  surfaceTest('a frame from another origin cannot reach the app',
      (tester) async {
    if (Platform.isIOS) return expectFrameNeverRequested(tester, 'other');
    final form =
        await open(tester, page: 'frame-host.html', extra: '&frame=other');
    await form.waitFor(1);
    await form.quiet();
    expect(form.received, ['frame-loaded']);
  });

  surfaceTest('a frame from the same origin cannot reach the app',
      (tester) async {
    if (Platform.isIOS) return expectFrameNeverRequested(tester, 'same');
    final form =
        await open(tester, page: 'frame-host.html', extra: '&frame=same');
    await form.waitFor(1);
    await form.quiet();
    expect(form.received, ['frame-loaded']);
  });

  surfaceTest('the form cannot navigate away', (tester) async {
    final form = await open(tester);
    await form.waitFor(2);
    if (Platform.isAndroid) {
      await _hooks.invokeMethod<void>('testClearRequests');
    }
    await form.send('navigate');
    await form.quiet();
    // Still the same document: it answers, over a bridge only the form's origin has.
    await form.send('still-here');
    await form.waitFor(3);
    expect(form.received.last, 'echo:still-here');
    if (Platform.isAndroid) {
      expect(
          await _hooks.invokeMethod<String>('testCurrentUrl', {'id': form.id}),
          form.url.toString());
      final requests =
          await _hooks.invokeListMethod<String>('testRequests') ?? <String>[];
      expect(requests.where((r) => r.contains('other.appassets.example')),
          isEmpty);
    }
  });

  surfaceTest('A form submission cannot navigate the form away',
      (tester) async {
    final form = await open(tester, page: 'post.html');
    await form.waitFor(1);
    if (Platform.isAndroid) {
      await _hooks.invokeMethod<void>('testClearRequests');
    }
    await form.quiet();
    if (Platform.isAndroid) {
      // Blocked, and the form fails; the page never changes and the other origin is never asked.
      expect(form.failed, isTrue);
      expect(
          await _hooks.invokeMethod<String>('testCurrentUrl', {'id': form.id}),
          form.url.toString());
      final requests =
          await _hooks.invokeListMethod<String>('testRequests') ?? <String>[];
      expect(requests.where((r) => r.contains('other.appassets.example')),
          isEmpty);
    } else {
      // iOS cancels the navigation: the same document still answers.
      await form.send('still-here');
      await form.waitFor(2);
      expect(form.received.last, 'echo:still-here');
    }
  });

  surfaceTest('the form cannot open windows or popups', (tester) async {
    final form = await open(tester);
    await form.waitFor(2);
    if (Platform.isAndroid) {
      await _hooks.invokeMethod<void>('testClearRequests');
    }
    await form.send('open');
    await form.waitFor(3);
    expect(form.received.last, 'open:null');
    await form.quiet();
    if (Platform.isAndroid) {
      final requests =
          await _hooks.invokeListMethod<String>('testRequests') ?? <String>[];
      expect(requests.where((r) => r.contains('other.appassets.example')),
          isEmpty);
    }
  });

  surfaceTest('files and content providers are out of reach', (tester) async {
    final form = await open(tester);
    await form.waitFor(2);
    await form.send('files');
    await form.waitFor(3);
    expect(form.received.last, 'files:refused,refused,refused');
  });

  surfaceTest('destroying the view removes the bridge', (tester) async {
    final form = await open(tester);
    await form.waitFor(2);
    await form.send('tick');
    await form.waitFor(3);
    await tester.pumpWidget(const SizedBox.shrink());
    // Destroy the surface but keep observing it: the teardown cancels the observer.
    await form.destroy();
    final after = form.received.length;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(form.received.length, after,
        reason: 'no post reaches the app after destroy');
    expect(form.received, contains('tick'));
  });
}

/// iOS only: an https origin on localhost served by the test itself, which records the file name
/// of every request. It serves the frame fixtures from the host app's assets and nothing else.
class _RecordingOrigin {
  _RecordingOrigin._(this._server);

  static const _served = {'frame-host.html', 'frame.html'};

  final HttpServer _server;
  final requested = <String>[];

  String get base => 'https://localhost:${_server.port}';

  static Future<_RecordingOrigin> start() async {
    if (_tlsCertB64.isEmpty || _tlsKeyB64.isEmpty) {
      fail('The iOS frame scenarios cannot serve their pages. '
          'Why: FIXTURE_TLS_CERT_B64 or FIXTURE_TLS_KEY_B64 is missing. '
          'Fix: pass the certificate the simulator trusts and its key, base64-encoded: '
          '--dart-define=FIXTURE_TLS_CERT_B64="\$(base64 -i cert.pem)" '
          '--dart-define=FIXTURE_TLS_KEY_B64="\$(base64 -i key.pem)" '
          '(see the iOS section of the B7 Flutter runbook).');
    }
    final context = SecurityContext()
      ..useCertificateChainBytes(base64.decode(_tlsCertB64))
      ..usePrivateKeyBytes(base64.decode(_tlsKeyB64));
    final server =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    final origin = _RecordingOrigin._(server);
    server.listen((request) async {
      final segments = request.uri.pathSegments;
      final name = segments.isEmpty ? '' : segments.last;
      origin.requested.add(name);
      if (_served.contains(name)) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
            await rootBundle.loadString('integration_test/assets/$name'));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    return origin;
  }

  /// Waits until [name] was requested, or fails after 15 s.
  Future<void> waitFor(String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!requested.contains(name)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for a request for $name; got $requested');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> close() => _server.close(force: true);
}

/// The events of one surface, and what the app can do to it.
class _Form {
  _Form(this.id, this.url, this._surface) {
    _sub = _surface.events.where((e) => e.id == id).listen((e) {
      if (e.kind == SurfaceEventKind.message && e.text != null) {
        received.add(e.text!);
      }
      if (e.kind == SurfaceEventKind.loadFailed) failed = true;
    });
  }

  final String id;
  final Uri url;
  final LeadFormSurface _surface;
  final received = <String>[];
  var failed = false;
  late final StreamSubscription<SurfaceEvent> _sub;
  var _destroyed = false;
  var _closed = false;

  Future<void> send(String text) => _surface.post(id, text);

  /// Waits until at least [count] messages arrived, or fails after 15 s.
  Future<void> waitFor(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (received.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $count message(s); got $received');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Gives a forbidden action time to show up if it was going to.
  Future<void> quiet() => Future<void>.delayed(const Duration(seconds: 2));

  /// Destroys the surface; the observer keeps listening.
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    await _surface.destroy(id);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await destroy();
    await _sub.cancel();
  }
}
