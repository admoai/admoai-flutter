import 'dart:async';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/interactive/bridge_protocol.dart';
import 'package:admoai/src/interactive/lead_form_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/lead_form_support.dart';

/// The scenarios of `lib/src/interactive/lead_form_registry.feature`, one test
/// per scenario, named after it, driven through `AdMoai` and its test seam for
/// the native surface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scenarios = <String>{};

  void scenario(String title, Future<void> Function() body) {
    scenarios.add(title);
    test(title, body);
  }

  final fixtures = leadFormBridgeFixtures();
  final bound = BridgeContract.shipped.maxHiddenPreparedForms;

  setUp(() => AdMoai.secureSurfaceAvailableForTesting = () => true);
  tearDown(() => AdMoai.secureSurfaceAvailableForTesting = null);

  test('every scenario has a test', () {
    final titles = File('lib/src/interactive/lead_form_registry.feature')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('Scenario:'))
        .map((l) => l.substring('Scenario:'.length).trim())
        .toSet();

    expect(titles, isNotEmpty);
    expect(titles, equals(scenarios));
  });

  final descriptorJson = leadFormDescriptorJson()
    ..['expiresAt'] = '2999-01-01T00:00:00Z';
  final creative = Creative.fromJson({
    'contents': [],
    'advertiser': {},
    'tracking': {},
    'interactiveExperience': descriptorJson,
  });

  /// An opted-in SDK whose forms run over fake surfaces, in creation order.
  ({AdMoai sdk, List<FakeSurface> surfaces}) world(
      {LeadFormValueProvider? provider}) {
    final surfaces = <FakeSurface>[];
    final sdk = AdMoai.forTesting(
      config: SDKConfig(
          baseUrl: 'https://mock.api.admoai.com', apiVersion: '2025-11-01'),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    )
      ..leadFormSurfaceFactoryForTesting = (() {
        final s = FakeSurface();
        surfaces.add(s);
        return s;
      })
      ..enableInteractiveExperiences(provider ?? NoPrefill());
    return (sdk: sdk, surfaces: surfaces);
  }

  /// A new form and the page behind it (its surface is the one just created by
  /// the factory the first time the form loads).
  ({LeadFormController controller, FakePage page}) form(
      ({AdMoai sdk, List<FakeSurface> surfaces}) w) {
    final before = w.surfaces.length;
    final c = w.sdk.createLeadFormController(creative,
        presentation: FormPresentation.fullScreen, host: FakeHost())!;
    // The factory runs when the controller is built, so its surface is known.
    final page = FakePage(fixtures, w.surfaces[before])..controller = c;
    return (controller: c, page: page);
  }

  Future<void> prepare(
      ({LeadFormController controller, FakePage page}) f) async {
    await f.controller.prepare();
    if (f.controller.state.value is LeadFormIdle) return;
    f.page.say('bridge_ready');
    f.page.say('prepared');
  }

  Future<void> show(({LeadFormController controller, FakePage page}) f) async {
    await prepare(f);
    await f.controller.open();
    f.page.say('activated');
    f.page.say('prefill_applied');
    f.controller.setVisible(true);
  }

  Future<List<({LeadFormController controller, FakePage page})>> hiddenForms(
      ({AdMoai sdk, List<FakeSurface> surfaces}) w) async {
    final forms = [for (var i = 0; i < bound; i++) form(w)];
    for (final f in forms) {
      await prepare(f);
      expect(f.controller.state.value, isA<LeadFormPrepared>());
    }
    return forms;
  }

  scenario('a user change closes every open form', () async {
    final w = world()..sdk.setUserConfig(id: 'user-a');
    final a = form(w);
    await prepare(a);
    final b = form(w);
    await show(b);
    expect(b.controller.state.value, isA<LeadFormVisible>());

    w.sdk.setUserConfig(id: 'user-b');

    expect(a.controller.state.value, isA<LeadFormDisposed>());
    expect(b.controller.state.value, isA<LeadFormDisposed>());
  });

  scenario('a lookup that answers after the user changed fills nothing',
      () async {
    final pending = Completer<Map<StandardAttributeKey, String>>();
    final w = world(provider: ScriptedProvider((_) => pending.future));
    w.sdk.setUserConfig(id: 'user-a');
    final f = form(w);
    await prepare(f);
    await f.controller.open();
    f.page.say('activated');

    w.sdk.clearUserConfig();
    pending.complete({StandardAttributeKey.email: 'a@example.invalid'});
    await pumpEventQueue();

    expect(f.controller.state.value, isA<LeadFormDisposed>());
    expect(f.page.sent, isNot(contains('prefill')));
  });

  scenario('setting the same user again keeps the forms', () async {
    final w = world()..sdk.setUserConfig(id: 'user-a');
    final f = form(w);
    await prepare(f);

    w.sdk.setUserConfig(id: 'user-a', timezone: 'UTC');
    w.sdk.userConfig = UserConfig(id: 'user-a');

    expect(f.controller.state.value, isA<LeadFormPrepared>());
  });

  scenario(
      'turning the opt-in off or changing the value provider closes every form',
      () async {
    final w = world();
    final off = form(w);
    await show(off);
    w.sdk.disableInteractiveExperiences();
    expect(off.controller.state.value, isA<LeadFormDisposed>());

    w.sdk.enableInteractiveExperiences(NoPrefill());
    final swapped = form(w);
    await show(swapped);
    w.sdk.enableInteractiveExperiences(NoPrefill());
    expect(swapped.controller.state.value, isA<LeadFormDisposed>());

    // The very same provider again keeps them.
    final provider = NoPrefill();
    w.sdk.enableInteractiveExperiences(provider);
    final kept = form(w);
    await prepare(kept);
    w.sdk.enableInteractiveExperiences(provider);
    expect(kept.controller.state.value, isA<LeadFormPrepared>());
  });

  scenario('the app can close every form at once', () async {
    final w = world();
    final a = form(w);
    final b = form(w);
    await prepare(a);
    await prepare(b);

    w.sdk.disposeAllLeadForms();

    expect(a.controller.state.value, isA<LeadFormDisposed>());
    expect(b.controller.state.value, isA<LeadFormDisposed>());
  });

  scenario('hidden prepared forms are bounded', () async {
    final w = world();
    await hiddenForms(w);
    final extra = form(w);

    await extra.controller.prepare();
    expect(extra.controller.state.value, isA<LeadFormIdle>());
    expect(extra.page.surface.created, isEmpty);

    await extra.controller.open();
    expect(extra.controller.state.value, isA<LeadFormPreparing>());
    expect(extra.page.surface.created, hasLength(1));
    extra.page.say('bridge_ready');
    extra.page.say('prepared');
    expect(extra.controller.state.value, isA<LeadFormActivating>());
  });

  scenario('a form that becomes visible no longer counts toward the bound',
      () async {
    final w = world();
    final forms = await hiddenForms(w);
    final extra = form(w);
    await extra.controller.prepare();
    expect(extra.controller.state.value, isA<LeadFormIdle>());

    await forms.first.controller.open();
    forms.first.page.say('activated');
    forms.first.page.say('prefill_applied');
    forms.first.controller.setVisible(true);
    await extra.controller.prepare();

    expect(extra.controller.state.value, isA<LeadFormPreparing>());
  });

  scenario('a form whose view failed to load frees its place', () async {
    final w = world();
    for (var i = 0; i < bound; i++) {
      final f = form(w);
      f.page.surface.failCreate = true;
      await f.controller.prepare();
      expect(f.controller.state.value,
          const LeadFormFailed('surface_error', false));
    }
    final extra = form(w);

    await extra.controller.prepare();

    expect(extra.controller.state.value, isA<LeadFormPreparing>());
    expect(extra.page.surface.created, hasLength(1));
  });

  scenario('a disposed form frees its place', () async {
    final w = world();
    final forms = await hiddenForms(w);
    final extra = form(w);
    await extra.controller.prepare();
    expect(extra.controller.state.value, isA<LeadFormIdle>());

    await forms.first.controller.dispose();
    await extra.controller.prepare();

    expect(extra.controller.state.value, isA<LeadFormPreparing>());
  });

  group('beyond the scenarios', () {
    test('a registry forgets a controller that was disposed', () async {
      final registry = LeadFormRegistry();
      final r = FakeRig(
          InteractiveExperience.tryFromJson(descriptorJson)
              as LeadGenerationExperience,
          fixtures,
          DateTime.utc(2026),
          registry: registry);
      expect(registry.isEmpty, isFalse);

      await r.controller.dispose();

      expect(registry.isEmpty, isTrue);
    });

    test('the SDK disposing its resources closes every form', () async {
      final w = world();
      final f = form(w);
      await prepare(f);

      w.sdk.dispose();

      expect(f.controller.state.value, isA<LeadFormDisposed>());
    });
  });
}
