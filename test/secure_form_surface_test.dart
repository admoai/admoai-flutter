import 'dart:async';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/interactive/lead_form_controller.dart'
    show buildLeadFormController, leadFormSurfaceReady;
import 'package:admoai/src/interactive/secure_form_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Binds `lib/src/interactive/secure_form_surface.feature` to the places its
/// scenarios are proven. The web view is native code, so most scenarios run in
/// the plugin's JVM tests (Robolectric, over a fake message listener); this file
/// holds each one to a Kotlin test of the same name, and runs the Dart-side
/// scenario and the channel adapter itself.
///
/// What no automated suite proves, said plainly: a real web page over HTTPS
/// (an iframe posting, a navigation attempt, a popup) on a real Android WebView
/// or iOS WKWebView. That needs a device and a TLS origin, and no CI job runs
/// one. iOS has no native test in CI at all; its rules (origin match, message
/// gate, the injected bridge script) were checked by hand off-device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = PlatformLeadFormSurface.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final scenarios = <String, String>{
    'the form page at the launch origin reaches the app': 'kotlin',
    "the form receives the app's messages": 'kotlin',
    'the page learns its instance and channel from the launch URL fragment':
        'kotlin',
    'a frame from another origin cannot reach the app': 'kotlin',
    'a frame from the same origin cannot reach the app': 'kotlin',
    'the form cannot navigate away': 'kotlin',
    'the form cannot open windows or popups': 'kotlin',
    'files and content providers are out of reach': 'kotlin',
    'the form view is locked down': 'kotlin',
    'destroying the view removes the bridge': 'kotlin',
    'a device that cannot host the view says so, and the SDK does not advertise':
        'dart',
  };

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    LeadFormSurface.resetSupportForTesting();
  });

  test('every scenario is bound to where it is proven', () {
    final titles = File('lib/src/interactive/secure_form_surface.feature')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('Scenario:'))
        .map((l) => l.substring('Scenario:'.length).trim())
        .toSet();
    expect(titles, isNotEmpty);
    expect(titles, equals(scenarios.keys.toSet()));

    final kotlin = File(
            'android/src/test/kotlin/com/admoai/flutter/leadform/SecureFormWebViewTest.kt')
        .readAsStringSync();
    for (final e in scenarios.entries.where((e) => e.value == 'kotlin')) {
      expect(kotlin, contains('fun `${e.key}`()'),
          reason: 'no Robolectric test named "${e.key}"');
    }
  });

  test(
      'a device that cannot host the view says so, and the SDK does not advertise',
      () async {
    for (final answer in <Object? Function()>[
      () => false,
      () => throw PlatformException(code: 'unsupported'),
      () => throw MissingPluginException(),
      () => null,
    ]) {
      LeadFormSurface.resetSupportForTesting();
      messenger.setMockMethodCallHandler(channel, (_) async => answer());
      expect(LeadFormSurface.isSupportedCached, isFalse);
      expect(await LeadFormSurface.isSupported(), isFalse);
      expect(LeadFormSurface.isSupportedCached, isFalse);
    }
    // No plugin at all (any other platform): not supported.
    LeadFormSurface.resetSupportForTesting();
    messenger.setMockMethodCallHandler(channel, null);
    expect(await LeadFormSurface.isSupported(), isFalse);
  });

  test('support is asked once and then cached', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return true;
    });

    expect(await LeadFormSurface.isSupported(), isTrue);
    expect(await LeadFormSurface.isSupported(), isTrue);

    expect(calls, 1);
    expect(LeadFormSurface.isSupportedCached, isTrue);
  });

  group('the channel adapter', () {
    final surface = PlatformLeadFormSurface.instance;

    test('create, post and destroy carry only what the native side needs',
        () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (c) async {
        calls.add(c);
        return null;
      });

      await surface.create(
          'lead_form_1', Uri.parse('https://forms.example.com/x#a=b'));
      await surface.post('lead_form_1', '{"type":"activate"}');
      await surface.destroy('lead_form_1');

      expect(calls.map((c) => c.method), ['create', 'post', 'destroy']);
      expect(calls[0].arguments,
          {'id': 'lead_form_1', 'url': 'https://forms.example.com/x#a=b'});
      expect(calls[1].arguments,
          {'id': 'lead_form_1', 'text': '{"type":"activate"}'});
      expect(calls[2].arguments, {'id': 'lead_form_1'});
    });

    Future<void> fromNative(Map<Object?, Object?>? args) async {
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('event', args)),
        (_) {},
      );
    }

    test('native events become surface events; anything malformed is dropped',
        () async {
      final seen = <SurfaceEvent>[];
      final sub = surface.events.listen(seen.add);

      await fromNative({'id': 'a', 'kind': 'message', 'text': 'hello'});
      await fromNative({'id': 'a', 'kind': 'renderGone'});
      await fromNative({'id': 'b', 'kind': 'loadFailed'});
      await fromNative({'id': 'a', 'kind': 'message'});
      await fromNative({'id': 'a', 'kind': 'message', 'text': 5});
      await fromNative({'id': 'a', 'kind': 'unknown'});
      await fromNative({'kind': 'message', 'text': 'no id'});
      await fromNative(null);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen.map((e) => (e.id, e.kind, e.text)), [
        ('a', SurfaceEventKind.message, 'hello'),
        ('a', SurfaceEventKind.renderGone, null),
        ('b', SurfaceEventKind.loadFailed, null),
      ]);
      expect(seen.first.toString(), isNot(contains('hello')));
    });
  });

  group('LeadFormView', () {
    Future<_Controller> controller() async {
      final c = _Controller();
      await c.controller.prepare();
      return c;
    }

    testWidgets('is empty until the native view exists and on other platforms',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = _Controller();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: LeadFormView(controller: c.controller),
      ));
      expect(find.byType(SizedBox), findsOneWidget);
      expect(leadFormSurfaceReady(c.controller).value, isFalse);

      await tester.runAsync(c.controller.prepare);
      await tester.pump();

      expect(leadFormSurfaceReady(c.controller).value, isTrue);
      expect(find.byType(AndroidView), findsNothing);
      expect(find.byType(UiKitView), findsNothing);
      debugDefaultTargetPlatformOverride = null;
      await tester.runAsync(c.controller.dispose);
      await tester.pump();
      expect(leadFormSurfaceReady(c.controller).value, isFalse);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
          'attaches the controller\'s view on $platform and keeps it '
          'across rebuilds', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final c = await tester.runAsync(controller) as _Controller;
        Widget app(int n) => Directionality(
              textDirection: TextDirection.ltr,
              child: Column(children: [
                Text('rebuild $n'),
                SizedBox(
                    width: 100,
                    height: 100,
                    child: LeadFormView(controller: c.controller)),
              ]),
            );

        await tester.pumpWidget(app(1));
        final first = platform == TargetPlatform.android
            ? tester.widget<AndroidView>(find.byType(AndroidView))
            : tester.widget<UiKitView>(find.byType(UiKitView));
        await tester.pumpWidget(app(2));
        final second = platform == TargetPlatform.android
            ? tester.widget<AndroidView>(find.byType(AndroidView))
            : tester.widget<UiKitView>(find.byType(UiKitView));

        expect(first.key, second.key);
        expect(
            find.byType(
                platform == TargetPlatform.android ? AndroidView : UiKitView),
            findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
        await tester.runAsync(c.controller.dispose);
      });
    }
  });
}

class _Controller {
  _Controller() {
    controller = buildLeadFormController(
      descriptor: InteractiveExperience.tryFromJson({
        'type': 'lead_generation',
        'formId': 'form_1',
        'preparedVersionId': 'v_1',
        'formInstanceId': 'form_instance_01KG000000000000000000N001',
        'launchUrl': 'https://forms.example.com/runtime/index.html',
        'preparationToken': 'tok',
        'expiresAt': '2999-01-01T00:00:00Z',
      }) as LeadGenerationExperience,
      presentation: FormPresentation.inline,
      host: _Host(),
      surface: _Surface(),
    );
  }

  late final LeadFormController controller;
}

class _Host implements LeadFormHost {
  @override
  void onOpenExternalLink(
      LeadFormController controller, ExternalLinkPurpose purpose, Uri url) {}

  @override
  void onRequestClose(LeadFormController controller) {}
}

class _Surface extends LeadFormSurface {
  @override
  Stream<SurfaceEvent> get events => const Stream.empty();

  @override
  Future<void> create(String id, Uri url) async {}

  @override
  Future<void> post(String id, String text) async {}

  @override
  Future<void> destroy(String id) async {}
}
