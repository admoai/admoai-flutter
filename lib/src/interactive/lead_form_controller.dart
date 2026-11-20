import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/interactive_experience.dart';
import 'bridge_protocol.dart';
import 'form_presentation.dart';
import 'lead_form_host.dart';
import 'lead_form_prefill.dart';
import 'lead_form_registry.dart';
import 'lead_form_state.dart';
import 'secure_form_surface.dart';

/// Prepares and opens one Lead Generation form. Create one per served creative
/// with `AdMoai.createLeadFormController`.
///
/// The app still renders the creative, fires its impression and its single
/// click. The controller never fires a click, never fetches another ad and never
/// shows a stale form.
///
/// Typical use: [prepare] while the creative is on screen, [open] when the
/// viewer taps, show a `LeadFormView` for this controller, call [setVisible]
/// with `true` once it is actually on screen (and with `false` when it is hidden
/// again), and [dispose] when the form goes away, whatever the reason.
///
/// The form is untrusted web content: every message it sends goes through the
/// bridge validator, and neither the preparation token, a message, a prefilled
/// value nor a URL with a query string is ever logged.
///
/// Once the viewer opened the form and it activated, the controller asks the
/// app's [LeadFormValueProvider] for the standard attributes that form requests,
/// within the contract's lookup time, and prefills the form with the answer. It
/// also fires the tracking URLs the activation authorized when the form reports
/// those events.
class LeadFormController {
  LeadFormController._({
    required LeadGenerationExperience descriptor,
    required this.presentation,
    required LeadFormHost host,
    required LeadFormSurface surface,
    required DateTime Function() clock,
    required String channel,
    required void Function(String) log,
    required LeadFormValueProvider valueProvider,
    required void Function(String) fireTracking,
    required LeadFormRegistry? registry,
    required BridgeContract contract,
    required Timer Function(Duration, void Function()) timer,
  })  : _valueProvider = valueProvider,
        _fireTracking = fireTracking,
        _registry = registry,
        _contract = contract,
        _timer = timer,
        _descriptor = descriptor,
        _host = host,
        _surface = surface,
        _clock = clock,
        _channel = channel,
        _log = log,
        _launch = leadGenerationLaunch(descriptor),
        _id = 'lead_form_${_nextId++}',
        _session = BridgeSession(
            instanceId: descriptor.formInstanceId, channel: channel);

  static int _nextId = 0;

  final LeadGenerationExperience _descriptor;
  final LeadFormHost _host;
  final LeadFormSurface _surface;
  final DateTime Function() _clock;
  final String _channel;
  final void Function(String) _log;
  final ({Uri launchUrl, String preparationToken}) _launch;
  final String _id;
  BridgeSession _session;
  final LeadFormValueProvider _valueProvider;
  final void Function(String) _fireTracking;
  final LeadFormRegistry? _registry;
  final BridgeContract _contract;
  final Timer Function(Duration, void Function()) _timer;

  final ValueNotifier<LeadFormState> _state =
      ValueNotifier<LeadFormState>(const LeadFormIdle());
  final ValueNotifier<bool> _surfaceReady = ValueNotifier<bool>(false);
  StreamSubscription<SurfaceEvent>? _events;

  bool _surfaceStarted = false;
  bool _surfaceDestroyed = false;
  bool _pendingOpen = false;
  bool _visibleRequested = false;
  bool _visibleOnWire = false;
  bool _activateSent = false;
  bool _activatedReceived = false;
  bool _submittedReceived = false;
  bool _loadFailed = false;
  bool _disposed = false;
  bool _loadStarted = false;
  bool _everVisible = false;
  Map<String, Object?>? _activation;

  // What the activation asked for and authorized. Never holds a value the app
  // answered: the answer goes straight into the prefill message.
  Set<StandardAttributeKey> _requested = const <StandardAttributeKey>{};
  Map<String, String> _authorizedEvents = const <String, String>{};
  final Set<String> _fired = <String>{};
  int _lookupId = 0;
  bool _prefillDone = true;
  Timer? _lookupTimer;

  /// How the app shows the form; told to the form so it draws its own close
  /// button only full screen.
  final FormPresentation presentation;

  /// The form instance this controller drives, as the decision response named
  /// it.
  String get formInstanceId => _descriptor.formInstanceId;

  /// Where the form is now.
  ValueListenable<LeadFormState> get state => _state;

  /// Loads the form hidden and prepares it, so a later [open] is quick. Safe to
  /// repeat: a second call while preparing or prepared does nothing.
  ///
  /// When as many forms as the contract allows are already loaded and hidden,
  /// this one stays idle (it does not load yet); [open] loads it anyway.
  Future<void> prepare() => _prepare(force: false);

  Future<void> _prepare({required bool force}) async {
    if (_disposed || _state.value is! LeadFormIdle) return;
    if (_expired()) {
      _set(const LeadFormExpired());
      return;
    }
    if (!force && _registry?.mayPrepare(this) == false) return;
    _loadStarted = true;
    _set(const LeadFormPreparing());
    await _createSurface();
  }

  /// Opens the form: activates it as soon as it is prepared. Safe to repeat.
  Future<void> open() async {
    if (_disposed) return;
    final s = _state.value;
    if ((s is LeadFormIdle ||
            s is LeadFormPreparing ||
            s is LeadFormPrepared) &&
        _expired()) {
      _set(const LeadFormExpired());
      return;
    }
    switch (s) {
      case LeadFormIdle():
        _pendingOpen = true;
        await _prepare(force: true);
      case LeadFormPreparing():
        _pendingOpen = true;
      case LeadFormPrepared():
        _activate();
      default:
        break;
    }
  }

  /// Tells the form whether the app is showing it right now. Repeating the same
  /// value does nothing.
  void setVisible(bool visible) {
    if (_disposed || visible == _visibleRequested) return;
    _visibleRequested = visible;
    switch (_state.value) {
      case LeadFormReadyToShow():
        if (visible) _becomeVisible();
      case LeadFormVisible() || LeadFormSubmitting() || LeadFormSubmitted():
        _syncVisibility();
      default:
        break;
    }
  }

  /// Retries after a failure that reported `retryable`. Does nothing in any
  /// other state. Never reloads a page that loaded: it asks the form to prepare
  /// or activate again.
  Future<void> retry() async {
    if (_disposed) return;
    final failed = _state.value;
    if (failed is! LeadFormFailed || !failed.retryable) return;
    if (_loadFailed) {
      await _restartAfterLoadFailure();
    } else if (_activateSent) {
      _activate();
    } else if (_send('retry_prepare')) {
      _set(const LeadFormPreparing());
    }
  }

  /// Ends the form: tells it to drop what it holds, destroys the view and
  /// ignores everything after. Safe to repeat. Call it whenever the form goes
  /// away.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _endLookup();
    _requested = const <StandardAttributeKey>{};
    _authorizedEvents = const <String, String>{};
    _registry?.remove(this);
    String? farewell;
    if (_session.bridgeReadyCount > 0 &&
        _surfaceStarted &&
        !_surfaceDestroyed) {
      try {
        farewell = _session.encode('dispose', const <String, Object?>{});
      } on StateError {
        farewell = null;
      }
    }
    _pendingOpen = false;
    _set(const LeadFormDisposed());
    final events = _events;
    _events = null;
    await events?.cancel();
    if (farewell != null) {
      try {
        await _surface.post(_id, farewell);
      } catch (_) {
        // Best effort: the page may already be gone.
      }
    }
    await _destroySurface();
  }

  /// Never shows the preparation token or the launch URL.
  @override
  String toString() => 'LeadFormController(formInstanceId: $formInstanceId, '
      'presentation: ${presentation.name}, state: ${_state.value})';

  bool _expired() => !_clock().toUtc().isBefore(_descriptor.expiresAt);

  void _set(LeadFormState next) => _state.value = next;

  bool get _ended {
    final s = _state.value;
    return s is LeadFormExpired ||
        s is LeadFormDisposed ||
        (s is LeadFormFailed && !s.retryable);
  }

  /// The launch URL with the instance and the channel in its fragment (a
  /// fragment is never sent to a server). The preparation token never goes in
  /// the URL.
  Uri _launchUrlWithIdentity() {
    final base = _launch.launchUrl.removeFragment().toString();
    final instance = Uri.encodeQueryComponent(formInstanceId);
    final channel = Uri.encodeQueryComponent(_channel);
    return Uri.parse('$base#instanceId=$instance&channel=$channel');
  }

  Future<void> _createSurface() async {
    _surfaceStarted = true;
    _surfaceDestroyed = false;
    _events ??= _surface.events.listen(_onSurfaceEvent);
    try {
      await _surface.create(_id, _launchUrlWithIdentity());
    } catch (e) {
      if (_disposed) return;
      _log('Lead form surface not created (${e.runtimeType})');
      _failTerminal('surface_error');
      return;
    }
    if (_disposed || _surfaceDestroyed) {
      // Disposed (or failed) while the view was being created: do not leak it.
      unawaited(_surface.destroy(_id).then((_) {}, onError: (Object _) {}));
      return;
    }
    _surfaceReady.value = true;
  }

  Future<void> _destroySurface() async {
    if (!_surfaceStarted || _surfaceDestroyed) return;
    _surfaceDestroyed = true;
    _surfaceReady.value = false;
    try {
      await _surface.destroy(_id);
    } catch (_) {
      // The view is going away either way.
    }
  }

  Future<void> _restartAfterLoadFailure() async {
    _loadFailed = false;
    await _destroySurface();
    if (_disposed) return;
    // A fresh bridge state for the new page, on the same channel: the old page
    // was destroyed, so nothing can still be talking on it.
    _session = BridgeSession(
        instanceId: _descriptor.formInstanceId, channel: _channel);
    _activateSent = false;
    _activatedReceived = false;
    _submittedReceived = false;
    _visibleOnWire = false;
    _activation = null;
    _endLookup();
    _set(const LeadFormPreparing());
    await _createSurface();
  }

  void _failTerminal(String code) {
    _set(LeadFormFailed(code, false));
    unawaited(_destroySurface());
  }

  void _onSurfaceEvent(SurfaceEvent event) {
    if (_disposed || event.id != _id || _surfaceDestroyed) return;
    switch (event.kind) {
      case SurfaceEventKind.message:
        final text = event.text;
        if (text != null) _onMessage(text);
      case SurfaceEventKind.renderGone:
        _set(const LeadFormFailed('renderer_gone', false));
        unawaited(_destroySurface());
      case SurfaceEventKind.loadFailed:
        final s = _state.value;
        if (s is LeadFormPreparing && !_activatedReceived) {
          _loadFailed = true;
          _set(const LeadFormFailed('load_failed', true));
        }
    }
  }

  void _onMessage(String text) {
    final received = _session.accept(text);
    switch (received) {
      case BridgeRefused(:final reason):
        _log('Lead form message refused: ${reason.name}');
      case BridgeMessage(:final type, :final payload):
        try {
          _handle(type, payload);
        } catch (e) {
          _log('Lead form message handler failed (${e.runtimeType})');
        }
    }
  }

  void _handle(String type, Map<String, Object?> payload) {
    if (type == 'request_close') {
      _host.onRequestClose(this);
      return;
    }
    if (_ended) return;
    switch (type) {
      case 'bridge_ready':
        _onBridgeReady();
      case 'prepared':
        _onPrepared();
      case 'activated':
        _onActivated(payload);
      case 'prefill_applied':
        _onPrefillApplied();
      case 'prepare_failed':
        _onPrepareFailed(payload);
      case 'fatal_error':
        _onFatal(payload['errorCode'] as String);
      case 'submitting':
        if (_isVisibleState()) _set(const LeadFormSubmitting());
      case 'submit_failed':
        if (_state.value is LeadFormSubmitting) _set(const LeadFormVisible());
      case 'submitted':
        if (_isVisibleState()) {
          _submittedReceived = true;
          _set(LeadFormSubmitted(payload['leadId'] as String,
              DateTime.parse(payload['submittedAt'] as String).toUtc()));
        }
      case 'request_external_url':
        _onExternalUrl(payload);
      case 'event':
        _onEvent(payload);
      default:
        break;
    }
  }

  bool _isVisibleState() =>
      _state.value is LeadFormVisible || _state.value is LeadFormSubmitting;

  void _onBridgeReady() {
    if (_activatedReceived) {
      _failTerminal('page_reloaded');
      return;
    }
    if (_session.bridgeReadyCount > 1) {
      // The page reloaded before activation and lost its state: start the
      // preparation over.
      if (_state.value is LeadFormActivating) _pendingOpen = true;
      _activateSent = false;
      _set(const LeadFormPreparing());
    }
    final sent = _send('initialize', {
      'preparationToken': _launch.preparationToken,
      'presentation': presentation.wireName,
    });
    if (!sent) _failTerminal('bridge_error');
  }

  void _onPrepared() {
    if (_state.value is! LeadFormPreparing) return;
    _set(const LeadFormPrepared());
    if (_pendingOpen) {
      _pendingOpen = false;
      _activate();
    }
  }

  void _activate() {
    if (_send('activate')) {
      _activateSent = true;
      _set(const LeadFormActivating());
    }
  }

  void _onActivated(Map<String, Object?> payload) {
    if (_state.value is! LeadFormActivating) return;
    _activatedReceived = true;
    _activation = payload;
    _requested = {
      for (final name in (payload['requestedAttributeKeys'] as List))
        if (StandardAttributeKey.fromWire(name as String) case final key?) key,
    };
    _authorizedEvents = {
      for (final e in (payload['events'] as List))
        (e as Map)['name'] as String: e['url'] as String,
    };
    _startPrefill();
  }

  /// Ends a lookup in flight: whatever it answers later is discarded.
  void _endLookup() {
    _lookupId++;
    _lookupTimer?.cancel();
    _lookupTimer = null;
    _prefillDone = true;
  }

  /// Asks the app for the requested values, at most once per activation, within
  /// the contract's lookup time. Anything but a usable answer prefills nothing.
  void _startPrefill() {
    _endLookup();
    final id = _lookupId;
    _prefillDone = false;
    if (_requested.isEmpty) {
      _finishPrefill(id, null);
      return;
    }
    _lookupTimer = _timer(
      Duration(milliseconds: _contract.prefillLookupTimeoutMs),
      () => _finishPrefill(id, null),
    );
    try {
      _valueProvider.lookUpValues(Set.unmodifiable(_requested)).then(
        (Map<StandardAttributeKey, String>? values) =>
            _finishPrefill(id, values),
        onError: (Object e) {
          // The type only: the message may carry user data.
          _log('Lead Generation value lookup failed: ${e.runtimeType}');
          _finishPrefill(id, null);
        },
      );
    } catch (e) {
      _log('Lead Generation value lookup failed: ${e.runtimeType}');
      _finishPrefill(id, null);
    }
  }

  void _finishPrefill(int id, Map<StandardAttributeKey, String>? values) {
    if (_disposed || id != _lookupId || _prefillDone) return;
    _prefillDone = true;
    _lookupTimer?.cancel();
    _lookupTimer = null;
    if (_state.value is! LeadFormActivating) return;
    Map<String, String> accepted;
    try {
      accepted = leadFormPrefillValues(values, _requested, _contract);
    } catch (e) {
      _log('Lead Generation prefill dropped: ${e.runtimeType}');
      accepted = const <String, String>{};
    }
    _send('prefill', {'values': accepted});
  }

  /// Fires the tracking URL of an event the activation authorized, once per
  /// event. The form never fires the creative's click or impression. Only the
  /// event name may be logged, never the URL.
  void _onEvent(Map<String, Object?> payload) {
    final name = payload['name'] as String;
    final url = _authorizedEvents[name];
    if (url == null || !_fired.add(name)) return;
    try {
      _fireTracking(url);
    } catch (e) {
      _log('Lead form event not reported: $name (${e.runtimeType})');
    }
  }

  void _onPrefillApplied() {
    if (_state.value is! LeadFormActivating) return;
    _set(const LeadFormReadyToShow());
    if (_visibleRequested) _becomeVisible();
  }

  void _becomeVisible() {
    if (_send('became_visible')) {
      _visibleOnWire = true;
      _everVisible = true;
      _set(const LeadFormVisible());
    }
  }

  void _syncVisibility() {
    if (_visibleRequested == _visibleOnWire) return;
    if (_send(_visibleRequested ? 'became_visible' : 'became_hidden')) {
      _visibleOnWire = _visibleRequested;
    }
  }

  void _onPrepareFailed(Map<String, Object?> payload) {
    final code = payload['errorCode'] as String;
    if (code == 'expired') {
      _set(const LeadFormExpired());
      return;
    }
    _set(LeadFormFailed(code, payload['retryable'] == true));
  }

  void _onFatal(String code) {
    if (code == 'expired') {
      _set(const LeadFormExpired());
    } else {
      _set(LeadFormFailed(code, false));
    }
    unawaited(_destroySurface());
  }

  void _onExternalUrl(Map<String, Object?> payload) {
    ExternalLinkPurpose? purpose;
    for (final p in ExternalLinkPurpose.values) {
      if (p.wireName == payload['purpose']) purpose = p;
    }
    final url = Uri.tryParse(payload['url'] as String);
    if (purpose == null || url == null) return;
    if (purpose == ExternalLinkPurpose.websiteCta && !_submittedReceived) {
      return;
    }
    _host.onOpenExternalLink(this, purpose, url);
  }

  /// Encodes and posts one app message. A message the contract refuses is not
  /// sent. A post that fails ends the form: fail closed.
  bool _send(String type, [Map<String, Object?> payload = const {}]) {
    if (_surfaceDestroyed || !_surfaceStarted) return false;
    final String text;
    try {
      text = _session.encode(type, payload);
    } on StateError catch (e) {
      _log('Lead form message not sent: ${e.message}');
      return false;
    }
    unawaited(_surface.post(_id, text).then((_) {}, onError: (Object e) {
      if (_disposed || _surfaceDestroyed) return;
      _log('Lead form transport failed (${e.runtimeType})');
      _failTerminal('bridge_error');
    }));
    return true;
  }
}

/// SDK-internal: builds a controller over [surface]. Not part of the public API
/// (hidden from the package export).
LeadFormController buildLeadFormController({
  required LeadGenerationExperience descriptor,
  required FormPresentation presentation,
  required LeadFormHost host,
  LeadFormSurface? surface,
  DateTime Function()? clock,
  String? channel,
  void Function(String)? log,
  required LeadFormValueProvider valueProvider,
  void Function(String)? fireTracking,
  LeadFormRegistry? registry,
  BridgeContract? contract,
  Timer Function(Duration, void Function())? timer,
}) =>
    LeadFormController._(
      descriptor: descriptor,
      presentation: presentation,
      host: host,
      surface: surface ?? LeadFormSurface.platform,
      clock: clock ?? DateTime.now,
      channel: channel ?? mintBridgeChannel(),
      log: log ?? (_) {},
      valueProvider: valueProvider,
      fireTracking: fireTracking ?? (_) {},
      registry: registry,
      contract: contract ?? BridgeContract.shipped,
      timer: timer ?? Timer.new,
    );

/// SDK-internal: the id of the native view [controller] owns.
String leadFormSurfaceId(LeadFormController controller) => controller._id;

/// SDK-internal: whether [controller]'s native view exists and can be attached.
ValueListenable<bool> leadFormSurfaceReady(LeadFormController controller) =>
    controller._surfaceReady;

/// SDK-internal: the `activated` payload of [controller] (formVersionId,
/// requestedAttributeKeys, events), or null before activation.
Map<String, Object?>? leadFormActivation(LeadFormController controller) =>
    controller._activation;

/// SDK-internal: whether [controller] was disposed.
bool leadFormIsDisposed(LeadFormController controller) => controller._disposed;

/// SDK-internal: whether [controller] is loaded but has never been shown, so it
/// counts toward the bound on hidden prepared forms.
bool leadFormCountsAsHidden(LeadFormController controller) =>
    !controller._disposed &&
    controller._loadStarted &&
    !controller._everVisible;
