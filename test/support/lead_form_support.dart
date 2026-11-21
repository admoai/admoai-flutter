import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/interactive/lead_form_controller.dart'
    show buildLeadFormController, leadFormSurfaceId;
import 'package:admoai/src/interactive/lead_form_registry.dart';
import 'package:admoai/src/interactive/secure_form_surface.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/services.dart';

/// Fakes shared by the Lead Generation controller, prefill and registry tests:
/// a native surface that records what the controller asks of it, a host, app
/// value providers, manual timers, and a rig that plays the page's side of the
/// bridge with the contract pack's fixtures.

/// An app that holds no value: every lookup answers empty.
class NoPrefill implements LeadFormValueProvider {
  @override
  Set<StandardAttributeKey> get availableKeys => const {};

  @override
  Future<Map<StandardAttributeKey, String>> lookUpValues(
          Set<StandardAttributeKey> keys) =>
      // Answers in place, so a test needs no event-loop turn to see the prefill.
      SynchronousFuture(const <StandardAttributeKey, String>{});
}

/// An app whose lookups are answered by [answer], and which records what it was
/// asked for.
class ScriptedProvider implements LeadFormValueProvider {
  ScriptedProvider(this.answer, {Set<StandardAttributeKey>? keys})
      : _keys = keys ?? const {};

  final Future<Map<StandardAttributeKey, String>> Function(
      Set<StandardAttributeKey> keys) answer;
  final Set<StandardAttributeKey> _keys;
  final asked = <Set<StandardAttributeKey>>[];

  @override
  Set<StandardAttributeKey> get availableKeys => _keys;

  @override
  Future<Map<StandardAttributeKey, String>> lookUpValues(
      Set<StandardAttributeKey> keys) {
    asked.add(keys);
    return answer(keys);
  }
}

/// Timers on manual time: nothing fires until [advance] reaches it.
class FakeTimers {
  var _now = 0;
  final _timers = <_FakeTimer>[];

  Timer create(Duration d, void Function() cb) {
    final t = _FakeTimer(_now + d.inMilliseconds, cb);
    _timers.add(t);
    return t;
  }

  void advance(int ms) {
    _now += ms;
    final due = _timers.where((t) => t.isActive && t.at <= _now).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    for (final t in due) {
      t._fire();
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.at, this._cb);
  final int at;
  final void Function() _cb;
  bool _active = true;

  void _fire() {
    if (!_active) return;
    _active = false;
    _cb();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

class FakeHost implements LeadFormHost {
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

class FakeCreated {
  FakeCreated(this.id, this.url);
  final String id;
  final Uri url;
}

/// A fake native surface: records what the controller asks of it and lets a test
/// play the page.
class FakeSurface extends LeadFormSurface {
  final created = <FakeCreated>[];
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
    created.add(FakeCreated(id, url));
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

/// The page's side of the bridge for one controller over its [surface]: it says
/// the contract pack's runtime messages, with the controller's identity.
class FakePage {
  FakePage(this.fixtures, this.surface);

  final Map<String, Map<String, dynamic>> fixtures;
  final FakeSurface surface;
  late LeadFormController controller;

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

/// A controller, its fake surface and host, and the page's side of the bridge.
class FakeRig extends FakePage {
  FakeRig(
    LeadGenerationExperience descriptor,
    Map<String, Map<String, dynamic>> fixtures,
    DateTime now, {
    FormPresentation presentation = FormPresentation.inline,
    DateTime Function()? clock,
    LeadFormValueProvider? provider,
    void Function(String)? fireTracking,
    LeadFormRegistry? registry,
  }) : super(fixtures, FakeSurface()) {
    controller = buildLeadFormController(
      descriptor: descriptor,
      presentation: presentation,
      host: host,
      surface: surface,
      clock: clock ?? () => now,
      log: logs.add,
      valueProvider: provider ?? NoPrefill(),
      fireTracking: fireTracking ?? fired.add,
      registry: registry,
      timer: timers.create,
    );
    registry?.register(controller);
  }

  final host = FakeHost();
  final logs = <String>[];
  final timers = FakeTimers();
  final fired = <String>[];
}

const leadFormFixtureDir = 'test/fixtures/interactive_experience';

/// The contract pack's runtime-to-app fixtures, by message type.
Map<String, Map<String, dynamic>> leadFormBridgeFixtures() => {
      for (final f in Directory('$leadFormFixtureDir/bridge/runtime-to-app')
          .listSync()
          .whereType<File>())
        (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['type']
            as String: jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    };

/// The pack's creative descriptor, as a decision response carries it.
Map<String, dynamic> leadFormDescriptorJson() => Map<String, dynamic>.from(
    (jsonDecode(File('$leadFormFixtureDir/creative-descriptor.json')
            .readAsStringSync())
        as Map<String, dynamic>)['interactiveExperience'] as Map);
