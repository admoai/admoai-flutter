import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the native secure web view reports for one surface id.
enum SurfaceEventKind { message, renderGone, loadFailed }

/// One event from a native surface. [text] is set only for
/// [SurfaceEventKind.message]: it is untrusted web content, so it only ever goes
/// to the bridge validator and never to a log.
@immutable
class SurfaceEvent {
  const SurfaceEvent(this.id, this.kind, [this.text]);

  final String id;
  final SurfaceEventKind kind;
  final String? text;

  @override
  String toString() => 'SurfaceEvent($id, ${kind.name})';
}

/// The Dart side of the native web views that host Lead Generation forms: one
/// view per id, locked to the launch URL's origin. Internal: not exported.
///
/// The controller is written against this seam; the real implementation talks to
/// the plugin over `admoai/lead_form`, and the tests use a fake.
abstract class LeadFormSurface {
  const LeadFormSurface();

  /// The plugin-backed surface.
  static LeadFormSurface get platform => PlatformLeadFormSurface.instance;

  /// Creates the view for [id] and starts loading [url] in it.
  Future<void> create(String id, Uri url);

  /// Sends one bridge text to the page of [id].
  Future<void> post(String id, String text);

  /// Removes the bridge and destroys the view of [id]. Safe to repeat.
  Future<void> destroy(String id);

  /// Events of every surface; consumers filter by id.
  Stream<SurfaceEvent> get events;

  static Future<bool>? _supported;
  static bool _supportedKnown = false;
  static bool _supportedValue = false;

  /// Whether this device can host the secure form view, asked once and cached.
  /// `false` on any platform exception or when the plugin is missing: the SDK
  /// never advertises Lead Generation on a device that cannot host it.
  static Future<bool> isSupported() => _supported ??= _check();

  /// The cached answer of [isSupported]: `false` until it has completed.
  static bool get isSupportedCached => _supportedKnown && _supportedValue;

  static Future<bool> _check() async {
    var answer = false;
    try {
      answer = await PlatformLeadFormSurface.channel
              .invokeMethod<bool>('isSupported') ==
          true;
    } catch (_) {
      answer = false;
    }
    _supportedValue = answer;
    _supportedKnown = true;
    return answer;
  }

  /// Forgets the cached [isSupported] answer. For tests.
  @visibleForTesting
  static void resetSupportForTesting() {
    _supported = null;
    _supportedKnown = false;
    _supportedValue = false;
  }
}

/// The real surface: method calls to the plugin, events back on the same channel.
class PlatformLeadFormSurface extends LeadFormSurface {
  PlatformLeadFormSurface._() {
    channel.setMethodCallHandler(_onCall);
  }

  static final PlatformLeadFormSurface instance = PlatformLeadFormSurface._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('admoai/lead_form');

  /// The platform view type registered by the plugin.
  static const String viewType = 'admoai/lead_form_view';

  final StreamController<SurfaceEvent> _events =
      StreamController<SurfaceEvent>.broadcast();

  @override
  Stream<SurfaceEvent> get events => _events.stream;

  @override
  Future<void> create(String id, Uri url) =>
      channel.invokeMethod<void>('create', {'id': id, 'url': url.toString()});

  @override
  Future<void> post(String id, String text) =>
      channel.invokeMethod<void>('post', {'id': id, 'text': text});

  @override
  Future<void> destroy(String id) =>
      channel.invokeMethod<void>('destroy', {'id': id});

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'event') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final id = args['id'], kind = args['kind'], text = args['text'];
    if (id is! String) return null;
    switch (kind) {
      case 'message':
        if (text is String) {
          _events.add(SurfaceEvent(id, SurfaceEventKind.message, text));
        }
      case 'renderGone':
        _events.add(SurfaceEvent(id, SurfaceEventKind.renderGone));
      case 'loadFailed':
        _events.add(SurfaceEvent(id, SurfaceEventKind.loadFailed));
    }
    return null;
  }
}
