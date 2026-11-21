import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/interactive/lead_form_controller.dart'
    show buildLeadFormController, leadFormActivation, leadFormSurfaceId;
import 'package:admoai/src/interactive/secure_form_surface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The scenarios of `lib/src/interactive/lead_form_controller.feature`, one test
/// per scenario, named after it. `every scenario has a test` holds the binding.
/// The fake surface plays the runtime side of the bridge with the contract
/// pack's fixtures, under `test/fixtures/interactive_experience`, carrying the
/// instance and channel the controller put in the launch URL fragment.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dir = 'test/fixtures/interactive_experience';
  final scenarios = <String>{};

  void scenario(String title, Future<void> Function() body) {
    scenarios.add(title);
    test(title, body);
  }

  Map<String, dynamic> json(String path) =>
      jsonDecode(File('$dir/$path').readAsStringSync()) as Map<String, dynamic>;

  final fixtures = <String, Map<String, dynamic>>{
    for (final f
        in Directory('$dir/bridge/runtime-to-app').listSync().whereType<File>())
      (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['type']
          as String: jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  };
  final descriptorJson = Map<String, dynamic>.from(
      json('creative-descriptor.json')['interactiveExperience'] as Map);
  final token = descriptorJson['preparationToken'] as String;
  final beforeExpiry = DateTime.utc(2026, 11, 12, 15, 0);
  final afterExpiry = DateTime.utc(2026, 11, 12, 15, 20);

  LeadGenerationExperience descriptor() =>
      InteractiveExperience.tryFromJson(descriptorJson)
          as LeadGenerationExperience;

  tearDown(() {
    AdMoai.secureSurfaceAvailableForTesting = null;
    LeadFormSurface.resetSupportForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformLeadFormSurface.channel, null);
  });

  test('every scenario has a test', () {
    final titles = File('lib/src/interactive/lead_form_controller.feature')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('Scenario:'))
        .map((l) => l.substring('Scenario:'.length).trim())
        .toSet();

    expect(titles, isNotEmpty);
    expect(titles, equals(scenarios));
  });

  // --- the creative and the SDK ---------------------------------------------

  Creative creativeWith(Object? experience) => Creative.fromJson({
        'contents': [],
        'advertiser': {},
        'tracking': {},
        if (experience != null) 'interactiveExperience': experience,
      });

  AdMoai sdk({
    http.Client? client,
    String? apiVersion = '2025-11-01',
    bool optedIn = true,
  }) {
    final s = AdMoai.forTesting(
      config: SDKConfig(
          baseUrl: 'https://mock.api.admoai.com', apiVersion: apiVersion),
      httpClient: client ?? MockClient((_) async => http.Response('{}', 200)),
    );
    if (optedIn) s.enableInteractiveExperiences(_NoPrefill());
    return s;
  }

  // --- one controller over a fake surface -----------------------------------

  _Rig rig({DateTime? now}) =>
      _Rig(descriptor(), fixtures, now ?? beforeExpiry);

  Future<_Rig> prepared() async {
    final r = rig();
    await r.controller.prepare();
    r.say('bridge_ready');
    r.say('prepared');
    expect(r.state, isA<LeadFormPrepared>());
    return r;
  }

  Future<_Rig> readyToShow() async {
    final r = await prepared();
    await r.controller.open();
    r.say('activated');
    r.say('prefill_applied');
    expect(r.state, isA<LeadFormReadyToShow>());
    return r;
  }

  Future<_Rig> visible() async {
    final r = await readyToShow();
    r.controller.setVisible(true);
    expect(r.state, isA<LeadFormVisible>());
    return r;
  }

  // --- scenarios --------------------------------------------------------------

  scenario('an app that has not opted in gets no controller', () async {
    AdMoai.secureSurfaceAvailableForTesting = () => true;
    final host = _Host();
    final creative = creativeWith(descriptorJson);

    expect(
        sdk(optedIn: false).createLeadFormController(creative,
            presentation: FormPresentation.inline, host: host),
        isNull);

    // Opting in on a device that hosts the form gives a controller.
    final controller = sdk().createLeadFormController(creative,
        presentation: FormPresentation.fullScreen, host: host);
    expect(controller, isNotNull);
    expect(controller!.presentation, FormPresentation.fullScreen);
    expect(controller.formInstanceId, descriptorJson['formInstanceId']);
    expect(controller.state.value, isA<LeadFormIdle>());

    // Withdrawing the opt-in takes it away again.
    final s = sdk()..disableInteractiveExperiences();
    expect(
        s.createLeadFormController(creative,
            presentation: FormPresentation.inline, host: host),
        isNull);
  });

  scenario(
      'an app on a device without the secure surface does not advertise Lead Generation',
      () async {
    final calls = <String>[];
    Future<void> advertises(Object? Function() answer, bool expected) async {
      LeadFormSurface.resetSupportForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformLeadFormSurface.channel, (c) async {
        calls.add(c.method);
        return answer();
      });
      final sent = <http.Request>[];
      final s = sdk(client: MockClient((r) async {
        sent.add(r);
        return http.Response('{"success":true,"data":[]}', 200);
      }));
      await s.requestAds((s.createRequestBuilder()
            ..addPlacement(key: 'ride_summary_banner'))
          .build());
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body.containsKey('interactiveExperience'), expected);
      // Neither does a controller exist on a device that cannot host the form.
      expect(
          s.createLeadFormController(creativeWith(descriptorJson),
                  presentation: FormPresentation.inline, host: _Host()) !=
              null,
          expected);
    }

    await advertises(() => false, false);
    await advertises(
        () => throw PlatformException(code: 'create_failed'), false);
    await advertises(() => 'not a bool', false);
    await advertises(() => true, true);
    expect(calls.toSet(), {'isSupported'});
  });

  scenario('a creative without a usable descriptor gets no controller',
      () async {
    AdMoai.secureSurfaceAvailableForTesting = () => true;
    final s = sdk();
    for (final experience in <Object?>[
      null,
      {'type': 'quiz'},
      Map<String, dynamic>.from(descriptorJson)..remove('preparationToken'),
      Map<String, dynamic>.from(descriptorJson)
        ..['launchUrl'] = 'http://forms.example.com/',
    ]) {
      expect(
          s.createLeadFormController(creativeWith(experience),
              presentation: FormPresentation.inline, host: _Host()),
          isNull,
          reason: '$experience');
    }
  });

  scenario(
      'the launch URL carries the instance and channel in its fragment and never the token',
      () async {
    final r = rig();

    await r.controller.prepare();

    final url = r.surface.created.single.url;
    expect(r.surface.created.single.id, leadFormSurfaceId(r.controller));
    expect(url.scheme, 'https');
    expect(url.host, Uri.parse(descriptorJson['launchUrl'] as String).host);
    expect(url.path, Uri.parse(descriptorJson['launchUrl'] as String).path);
    expect(url.hasQuery, isFalse);
    expect(Uri.splitQueryString(url.fragment), {
      'instanceId': descriptorJson['formInstanceId'],
      'channel': r.channel,
    });
    expect(r.channel, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));
    expect(url.toString(), isNot(contains(token)));
    expect(url.toString().contains('token'), isFalse);
    // Two controllers never share a channel.
    final other = rig();
    await other.controller.prepare();
    expect(other.channel, isNot(r.channel));
  });

  scenario('preparing loads the form hidden and stops before activation',
      () async {
    final r = rig();

    await r.controller.prepare();
    expect(r.state, isA<LeadFormPreparing>());
    expect(r.sent, isEmpty);
    r.say('bridge_ready');
    expect(r.sent, ['initialize']);
    r.say('prepared');

    expect(r.state, isA<LeadFormPrepared>());
    final init = r.posted('initialize');
    expect(init['payload'], {
      'preparationToken': token,
      'presentation': 'inline',
    });
    expect(init['instanceId'], descriptorJson['formInstanceId']);
    expect(init['channel'], r.channel);
    expect(r.sent, isNot(contains('activate')));

    final full = _Rig(descriptor(), fixtures, beforeExpiry,
        presentation: FormPresentation.fullScreen);
    await full.controller.prepare();
    full.say('bridge_ready');
    expect(full.posted('initialize')['payload']['presentation'], 'full_screen');
  });

  scenario(
      'opening a prepared form activates it, prefills and makes it ready to show',
      () async {
    final r = await prepared();

    await r.controller.open();
    expect(r.state, isA<LeadFormActivating>());
    expect(r.sent, ['initialize', 'activate']);
    r.say('activated');
    expect(r.posted('prefill')['payload'], {'values': <String, Object?>{}});
    expect(r.state, isA<LeadFormActivating>());
    r.say('prefill_applied');

    expect(r.state, isA<LeadFormReadyToShow>());
    final activation = leadFormActivation(r.controller)!;
    final activated = fixtures['activated']!['payload'] as Map;
    expect(activation['formVersionId'], activated['formVersionId']);
    expect(activation['requestedAttributeKeys'],
        activated['requestedAttributeKeys']);
    expect(activation['events'], activated['events']);
  });

  scenario('a form becomes visible only when the app says it is on screen',
      () async {
    final r = await readyToShow();
    expect(r.sent, isNot(contains('became_visible')));

    r.controller.setVisible(true);
    r.controller.setVisible(true);

    expect(r.state, isA<LeadFormVisible>());
    expect(r.sent.where((t) => t == 'became_visible'), hasLength(1));

    // Telling the app is visible before the form is ready is remembered.
    final early = await prepared();
    early.controller.setVisible(true);
    expect(early.state, isA<LeadFormPrepared>());
    await early.controller.open();
    early.say('activated');
    early.say('prefill_applied');
    expect(early.state, isA<LeadFormVisible>());
    expect(early.sent.last, 'became_visible');
  });

  scenario(
      'tapping before preparation finished opens the form once it is ready',
      () async {
    final r = rig();
    await r.controller.prepare();
    expect(r.state, isA<LeadFormPreparing>());

    await r.controller.open();
    expect(r.sent, isEmpty);
    r.say('bridge_ready');
    r.say('prepared');

    expect(r.state, isA<LeadFormActivating>());
    expect(r.sent, ['initialize', 'activate']);
    expect(r.surface.created, hasLength(1));
  });

  scenario('preparing or opening twice never creates a second form', () async {
    final r = rig();

    await r.controller.prepare();
    await r.controller.prepare();
    await r.controller.open();
    await r.controller.open();
    r.say('bridge_ready');
    r.say('prepared');
    await r.controller.open();
    await r.controller.open();
    await r.controller.prepare();

    expect(r.surface.created, hasLength(1));
    expect(r.sent.where((t) => t == 'activate'), hasLength(1));
    expect(r.sent.where((t) => t == 'initialize'), hasLength(1));

    // Opening straight from idle starts the preparation once.
    final fromIdle = rig();
    await fromIdle.controller.open();
    await fromIdle.controller.open();
    expect(fromIdle.surface.created, hasLength(1));
  });

  scenario('hiding and showing again keeps the same form', () async {
    final r = await visible();

    r.controller.setVisible(false);
    r.controller.setVisible(false);
    expect(r.state, isA<LeadFormVisible>());
    r.controller.setVisible(true);

    expect(r.surface.created, hasLength(1));
    expect(r.surface.destroyed, isEmpty);
    expect(r.sent.skip(r.sent.indexOf('became_visible')), [
      'became_visible',
      'became_hidden',
      'became_visible',
    ]);
    expect(r.state, isA<LeadFormVisible>());
  });

  scenario('a preparation that expired never opens', () async {
    final r = rig(now: afterExpiry);

    await r.controller.open();

    expect(r.state, isA<LeadFormExpired>());
    expect(r.surface.created, isEmpty);
    expect(r.sent, isEmpty);

    // Prepared in time but opened too late.
    var now = beforeExpiry;
    final late = _Rig(descriptor(), fixtures, beforeExpiry, clock: () => now);
    await late.controller.prepare();
    late.say('bridge_ready');
    late.say('prepared');
    now = afterExpiry;
    final sentBefore = late.sent.length;
    await late.controller.open();
    expect(late.state, isA<LeadFormExpired>());
    expect(late.sent, hasLength(sentBefore));

    final prepareLate = rig(now: afterExpiry);
    await prepareLate.controller.prepare();
    expect(prepareLate.state, isA<LeadFormExpired>());
    expect(prepareLate.surface.created, isEmpty);
  });

  scenario('a preparation that expires while the form is loading never opens',
      () async {
    var now = beforeExpiry;
    final r = _Rig(descriptor(), fixtures, beforeExpiry, clock: () => now);
    await r.controller.prepare();
    await r.controller.open();
    expect(r.state, isA<LeadFormPreparing>());

    r.say('bridge_ready');
    now = afterExpiry;
    r.say('prepared');

    expect(r.state, isA<LeadFormExpired>());
    expect(r.sent, ['initialize']);
  });

  scenario('a retryable preparation failure can be retried in the same view',
      () async {
    final r = rig();
    await r.controller.prepare();
    r.say('bridge_ready');
    r.say('prepare_failed');
    expect(r.state, const LeadFormFailed('temporary_failure', true));

    await r.controller.retry();

    expect(r.state, isA<LeadFormPreparing>());
    expect(r.sent, ['initialize', 'retry_prepare']);
    expect(r.surface.created, hasLength(1));
    expect(r.surface.destroyed, isEmpty);
    r.say('prepared');
    expect(r.state, isA<LeadFormPrepared>());
  });

  scenario('a retryable activation failure retries activation', () async {
    final r = await prepared();
    await r.controller.open();
    r.say('prepare_failed');
    expect(r.state, const LeadFormFailed('temporary_failure', true));

    await r.controller.retry();

    expect(r.sent, ['initialize', 'activate', 'activate']);
    expect(r.state, isA<LeadFormActivating>());
    expect(r.surface.created, hasLength(1));
  });

  scenario('a failure that cannot be retried ends the controller', () async {
    final r = await prepared();

    r.say('fatal_error');

    expect(r.state, const LeadFormFailed('revoked', false));
    await r.controller.retry();
    expect(r.state, const LeadFormFailed('revoked', false));
    expect(r.surface.destroyed, [leadFormSurfaceId(r.controller)]);
    // A non-retryable prepare failure does not retry either.
    final p = rig();
    await p.controller.prepare();
    p.say('bridge_ready');
    p.say('prepare_failed', {'errorCode': 'unauthorized', 'retryable': false});
    await p.controller.retry();
    expect(p.state, const LeadFormFailed('unauthorized', false));
    expect(p.sent, ['initialize']);
    // An expired preparation is its own state, never a failure to retry.
    final e = rig();
    await e.controller.prepare();
    e.say('bridge_ready');
    e.say('prepare_failed', {'errorCode': 'expired', 'retryable': true});
    expect(e.state, isA<LeadFormExpired>());
  });

  scenario('the form reports a submission in progress and its outcome',
      () async {
    final r = await visible();
    final states = <LeadFormState>[];
    r.controller.state.addListener(() => states.add(r.state));

    r.say('submitting');
    r.say('submitted');

    expect(states, [
      isA<LeadFormSubmitting>(),
      LeadFormSubmitted('lead_01KG000000000000000000W001',
          DateTime.utc(2026, 11, 12, 15, 4, 5)),
    ]);
    expect((r.state as LeadFormSubmitted).submittedAt.isUtc, isTrue);
  });

  scenario('a failed submission keeps the same form for a retry', () async {
    final r = await visible();
    r.say('submitting');
    expect(r.state, isA<LeadFormSubmitting>());

    r.say('submit_failed');

    expect(r.state, isA<LeadFormVisible>());
    expect(r.surface.created, hasLength(1));
    expect(r.surface.destroyed, isEmpty);
    r.say('submitting');
    r.say('submitted');
    expect(r.state, isA<LeadFormSubmitted>());
  });

  scenario('the form asks to close', () async {
    final r = await visible();

    r.say('request_close');

    expect(r.host.closes, [r.controller]);
    expect(r.state, isA<LeadFormVisible>());
  });

  scenario('the privacy policy link goes to the app, never inside the form',
      () async {
    final r = await visible();

    r.say('request_external_url');

    final privacy = Uri.parse(
        (fixtures['request_external_url']!['payload'] as Map)['url'] as String);
    expect(r.host.links,
        [(r.controller, ExternalLinkPurpose.privacyPolicy, privacy)]);
    expect(r.surface.created, hasLength(1));
    expect(r.sent.last, 'became_visible', reason: 'nothing sent to navigate');
  });

  scenario('the website link is refused before a submission', () async {
    final r = await visible();

    r.say('request_external_url', {
      'purpose': 'website_cta',
      'url': 'https://advertiser.example.invalid/',
    });
    r.say('submitting');
    r.say('request_external_url', {
      'purpose': 'website_cta',
      'url': 'https://advertiser.example.invalid/',
    });

    expect(r.host.links, isEmpty);
  });

  scenario('the website link goes to the app after a submission', () async {
    final r = await visible();
    r.say('submitting');
    r.say('submitted');

    r.say('request_external_url', {
      'purpose': 'website_cta',
      'url': 'https://advertiser.example.invalid/',
    });

    expect(r.host.links, [
      (
        r.controller,
        ExternalLinkPurpose.websiteCta,
        Uri.parse('https://advertiser.example.invalid/')
      ),
    ]);
  });

  scenario('a page that reloads after activation fails the controller',
      () async {
    final r = await visible();

    r.say('bridge_ready');

    expect(r.state, const LeadFormFailed('page_reloaded', false));
    expect(r.surface.destroyed, [leadFormSurfaceId(r.controller)]);
    expect(r.sent.where((t) => t == 'initialize'), hasLength(1));
  });

  scenario('disposing ends the form and ignores everything after', () async {
    final r = await visible();
    final seen = <LeadFormState>[];
    r.controller.state.addListener(() => seen.add(r.state));

    await r.controller.dispose();
    await r.controller.dispose();
    for (final type in [
      'request_close',
      'request_external_url',
      'submitting',
      'fatal_error',
      'bridge_ready',
    ]) {
      r.say(type);
    }
    r.surface.emit(SurfaceEvent(
        leadFormSurfaceId(r.controller), SurfaceEventKind.renderGone));
    r.controller.setVisible(false);
    await r.controller.open();
    await r.controller.retry();

    expect(r.sent.last, 'dispose');
    expect(r.sent.where((t) => t == 'dispose'), hasLength(1));
    expect(r.state, isA<LeadFormDisposed>());
    expect(seen, [isA<LeadFormDisposed>()], reason: 'notified once');
    expect(r.surface.destroyed, [leadFormSurfaceId(r.controller)]);
    expect(r.host.closes, isEmpty);
    expect(r.host.links, isEmpty);
  });

  scenario("the controller's description never shows the preparation token",
      () async {
    final r = await prepared();
    final logs = r.logs;

    final texts = [
      r.controller.toString(),
      r.state.toString(),
      for (final s in <LeadFormState>[
        LeadFormIdle(),
        LeadFormPreparing(),
        LeadFormPrepared(),
        LeadFormActivating(),
        LeadFormReadyToShow(),
        LeadFormVisible(),
        LeadFormSubmitting(),
        LeadFormSubmitted('lead_1', DateTime.utc(2026)),
        LeadFormFailed('x', true),
        LeadFormExpired(),
        LeadFormDisposed(),
      ])
        s.toString(),
      descriptor().toString(),
    ];
    for (final t in texts) {
      expect(t, isNot(contains(token)));
      expect(t, isNot(contains('index.html')));
    }
    expect(r.controller.toString(), contains('formInstanceId'));
    expect(logs.join('\n'), isNot(contains(token)));
  });

  // --- behaviour beyond the scenarios -----------------------------------------

  test('a listener that opens the form on Prepared causes one activation',
      () async {
    final r = rig();
    await r.controller.prepare();
    await r.controller.open();
    r.controller.state.addListener(() {
      if (r.state is LeadFormPrepared) unawaited(r.controller.open());
    });

    r.say('bridge_ready');
    r.say('prepared');

    expect(r.state, isA<LeadFormActivating>());
    expect(r.sent.where((t) => t == 'activate'), hasLength(1));
  });

  group('hostile or broken pages', () {
    test('messages the contract refuses are dropped and logged by reason only',
        () async {
      final r = await prepared();
      final before = r.state;
      final secret = 'SECRET-${DateTime.now().microsecondsSinceEpoch}';

      r.raw('not json $secret');
      r.raw(jsonEncode({'type': 'request_close', 'x': secret}));
      r.say('request_close', {'extra': secret});
      r.say('activated');
      r.say('prefill_applied');
      r.sayWith('request_close', instanceId: 'other_instance_0000000000000000');
      r.sayWith('request_close', channel: 'x' * 32);

      expect(r.state, before);
      expect(r.host.closes, isEmpty);
      expect(r.logs, isNotEmpty);
      expect(r.logs.join('\n'), isNot(contains(secret)));
      expect(r.logs.every((l) => l.startsWith('Lead form message refused: ')),
          isTrue);
    });

    test('a message from another surface is ignored', () async {
      final r = await prepared();
      r.surface
          .emit(SurfaceEvent('lead_form_9999', SurfaceEventKind.renderGone));
      expect(r.state, isA<LeadFormPrepared>());
    });

    test('a second ready before activation sends initialize again', () async {
      final r = await prepared();
      await r.controller.open();
      expect(r.state, isA<LeadFormActivating>());

      r.say('bridge_ready');

      expect(r.state, isA<LeadFormPreparing>());
      expect(r.sent, ['initialize', 'activate', 'initialize']);
      r.say('prepared');
      expect(r.state, isA<LeadFormActivating>(), reason: 'the open is kept');
      expect(r.sent.last, 'activate');
    });

    test('events are accepted and ignored', () async {
      final r = await visible();
      r.say('event');
      expect(r.state, isA<LeadFormVisible>());
    });

    test('the renderer going away fails the controller and destroys the view',
        () async {
      final r = await visible();

      r.surface.emit(SurfaceEvent(
          leadFormSurfaceId(r.controller), SurfaceEventKind.renderGone));

      expect(r.state, const LeadFormFailed('renderer_gone', false));
      expect(r.surface.destroyed, [leadFormSurfaceId(r.controller)]);
      await r.controller.dispose();
      expect(r.sent.where((t) => t == 'dispose'), isEmpty,
          reason: 'the page is gone');
    });

    test(
        'a load failure before the form is prepared can be retried on a new view',
        () async {
      final r = rig();
      await r.controller.prepare();
      r.surface.emit(SurfaceEvent(
          leadFormSurfaceId(r.controller), SurfaceEventKind.loadFailed));
      expect(r.state, const LeadFormFailed('load_failed', true));

      await r.controller.retry();

      expect(r.state, isA<LeadFormPreparing>());
      expect(r.surface.destroyed, hasLength(1));
      expect(r.surface.created, hasLength(2));
      expect(r.surface.created.last.url, r.surface.created.first.url);
      r.say('bridge_ready');
      r.say('prepared');
      expect(r.state, isA<LeadFormPrepared>());
      expect(r.sent, ['initialize']);

      // A load failure after the page was prepared is not a load failure.
      r.surface.emit(SurfaceEvent(
          leadFormSurfaceId(r.controller), SurfaceEventKind.loadFailed));
      expect(r.state, isA<LeadFormPrepared>());
    });

    test('a view that cannot be created fails closed', () async {
      final r = rig();
      r.surface.failCreate = true;
      await r.controller.prepare();
      expect(r.state, const LeadFormFailed('surface_error', false));
      expect(r.logs.join('\n'), isNot(contains('index.html')));
    });

    test('a message that cannot be posted fails closed', () async {
      final r = rig();
      await r.controller.prepare();
      r.surface.failPost = true;
      r.say('bridge_ready');
      await Future<void>.delayed(Duration.zero);
      expect(r.state, const LeadFormFailed('bridge_error', false));
    });

    test('disposing while the view is still being created does not leak it',
        () async {
      final r = rig();
      final gate = Completer<void>();
      r.surface.createGate = gate.future;
      final preparing = r.controller.prepare();
      await Future<void>.delayed(Duration.zero);

      await r.controller.dispose();
      gate.complete();
      await preparing;
      await Future<void>.delayed(Duration.zero);

      expect(r.surface.destroyed, isNotEmpty);
      expect(r.state, isA<LeadFormDisposed>());
    });

    test('a host that throws does not break the controller', () async {
      final r = await visible();
      r.host.throwOnClose = true;
      r.say('request_close');
      expect(r.state, isA<LeadFormVisible>());
      expect(r.logs.last, isNot(contains('StateError:')));
    });
  });
}

class _NoPrefill implements LeadFormValueProvider {
  @override
  Set<StandardAttributeKey> get availableKeys => const {};
}

class _Host implements LeadFormHost {
  final closes = <LeadFormController>[];
  final links = <(LeadFormController, ExternalLinkPurpose, Uri)>[];
  bool throwOnClose = false;

  @override
  void onOpenExternalLink(
      LeadFormController controller, ExternalLinkPurpose purpose, Uri url) {
    links.add((controller, purpose, url));
  }

  @override
  void onRequestClose(LeadFormController controller) {
    if (throwOnClose) throw StateError('boom');
    closes.add(controller);
  }
}

class _Created {
  _Created(this.id, this.url);
  final String id;
  final Uri url;
}

/// A fake native surface: records what the controller asks of it and lets a test
/// play the page.
class _FakeSurface extends LeadFormSurface {
  final created = <_Created>[];
  final posts = <Map<String, dynamic>>[];
  final destroyed = <String>[];
  final _events = StreamController<SurfaceEvent>.broadcast(sync: true);
  bool failCreate = false;
  bool failPost = false;
  Future<void>? createGate;

  @override
  Stream<SurfaceEvent> get events => _events.stream;

  @override
  Future<void> create(String id, Uri url) async {
    final gate = createGate;
    if (gate != null) await gate;
    if (failCreate) throw PlatformException(code: 'create_failed');
    created.add(_Created(id, url));
  }

  @override
  Future<void> post(String id, String text) async {
    if (failPost) throw PlatformException(code: 'no_view');
    posts.add(jsonDecode(text) as Map<String, dynamic>);
  }

  @override
  Future<void> destroy(String id) async => destroyed.add(id);

  void emit(SurfaceEvent e) => _events.add(e);
}

/// A controller, its fake surface and host, and the page's side of the bridge.
class _Rig {
  _Rig(
    LeadGenerationExperience descriptor,
    this.fixtures,
    DateTime now, {
    FormPresentation presentation = FormPresentation.inline,
    DateTime Function()? clock,
  }) {
    controller = buildLeadFormController(
      descriptor: descriptor,
      presentation: presentation,
      host: host,
      surface: surface,
      clock: clock ?? () => now,
      log: logs.add,
    );
  }

  final Map<String, Map<String, dynamic>> fixtures;
  final surface = _FakeSurface();
  final host = _Host();
  final logs = <String>[];
  late final LeadFormController controller;

  LeadFormState get state => controller.state.value;

  /// The channel the controller minted, read from the launch URL it loaded.
  String get channel =>
      Uri.splitQueryString(surface.created.first.url.fragment)['channel']!;

  List<String> get sent => [for (final p in surface.posts) p['type'] as String];

  Map<String, dynamic> posted(String type) =>
      surface.posts.lastWhere((p) => p['type'] == type);

  String get _id => leadFormSurfaceId(controller);

  void raw(String text) =>
      surface.emit(SurfaceEvent(_id, SurfaceEventKind.message, text));

  /// The page sends [type] from the fixtures, with the controller's identity and
  /// [payload] merged over the fixture's.
  void say(String type, [Map<String, Object?>? payload]) =>
      sayWith(type, payload: payload);

  void sayWith(String type,
      {Map<String, Object?>? payload, String? instanceId, String? channel}) {
    final base = fixtures[type]!;
    raw(jsonEncode({
      'type': type,
      'instanceId': instanceId ?? base['instanceId'],
      'channel': channel ?? this.channel,
      'payload': payload == null
          ? base['payload']
          : {...(base['payload'] as Map), ...payload},
    }));
  }
}
