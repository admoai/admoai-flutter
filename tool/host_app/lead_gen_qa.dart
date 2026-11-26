import 'dart:async';
import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';

/// The placement the Lead Generation QA round requests.
const String qaPlacementKey = 'sdk_ie_lead_generation';

/// Fixed values the "Prefill" switch offers, so a run can be compared by eye.
const Map<StandardAttributeKey, String> qaPrefillValues = {
  StandardAttributeKey.fullName: 'Alex Rider',
  StandardAttributeKey.email: 'alex@example.invalid',
  StandardAttributeKey.phone: '+56 9 1234 5678',
};

/// Prefill on offers fullName, email and phone; off is the empty provider.
class QaPrefillProvider implements LeadFormValueProvider {
  const QaPrefillProvider({required this.prefill});

  final bool prefill;

  @override
  Set<StandardAttributeKey> get availableKeys =>
      prefill ? qaPrefillValues.keys.toSet() : const <StandardAttributeKey>{};

  @override
  Future<Map<StandardAttributeKey, String>> lookUpValues(
    Set<StandardAttributeKey> keys,
  ) async {
    if (!prefill) return const {};
    return {
      for (final entry in qaPrefillValues.entries)
        if (keys.contains(entry.key)) entry.key: entry.value,
    };
  }
}

class LeadGenQaApp extends StatelessWidget {
  const LeadGenQaApp({super.key, required this.sdk, required this.baseUrl});

  final AdMoai sdk;
  final String baseUrl;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: LeadGenQaScreen(sdk: sdk, baseUrl: baseUrl),
      );
}

/// The Lead Generation QA screen: request `sdk_ie_lead_generation`, draw the
/// native creative, and on tap fire the click, `open()` and show the form, as
/// in the README "Lead Generation" how-to.
class LeadGenQaScreen extends StatefulWidget {
  const LeadGenQaScreen({super.key, required this.sdk, required this.baseUrl});

  final AdMoai sdk;
  final String baseUrl;

  @override
  State<LeadGenQaScreen> createState() => _LeadGenQaScreenState();
}

class _LeadGenQaScreenState extends State<LeadGenQaScreen>
    implements LeadFormHost {
  bool _prefill = true;
  bool _optIn = true;

  bool _requesting = false;
  bool _requested = false;
  String _requestJson = '(no request yet)';
  String? _requestError;
  Creative? _creative;
  LeadFormController? _controller;
  bool _formShown = false;

  @override
  void initState() {
    super.initState();
    _applyOptIn();
  }

  @override
  void didUpdateWidget(LeadGenQaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flutter reuses this State for another SDK: the controller belongs to the
    // old one, so release it and opt the new one in.
    if (oldWidget.sdk != widget.sdk) {
      _releaseController();
      _creative = null;
      _requested = false;
      _applyOptIn();
    }
  }

  @override
  void dispose() {
    _releaseController();
    super.dispose();
  }

  /// Declares (or withdraws) the Lead Generation opt-in with the provider the
  /// switches describe. A new provider closes the forms opened with the old one.
  void _applyOptIn() {
    if (_optIn) {
      widget.sdk.enableInteractiveExperiences(
        QaPrefillProvider(prefill: _prefill),
      );
    } else {
      widget.sdk.disableInteractiveExperiences();
    }
  }

  void _onControllerState() {
    if (mounted) setState(() {});
  }

  void _releaseController() {
    final old = _controller;
    _controller = null;
    _formShown = false;
    if (old != null) {
      old.state.removeListener(_onControllerState);
      old.setVisible(false);
      unawaited(old.dispose());
    }
  }

  void _adopt(LeadFormController controller) {
    _controller = controller;
    controller.state.addListener(_onControllerState);
  }

  LeadFormController? _newController(Creative creative) =>
      widget.sdk.createLeadFormController(
        creative,
        presentation: FormPresentation.fullScreen,
        host: this,
      );

  Future<void> _request() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _requestError = null;
    });
    _releaseController();
    _applyOptIn();
    final request = widget.sdk
        .createRequestBuilder()
        .addPlacement(key: qaPlacementKey)
        .build();
    Creative? creative;
    String json = const JsonEncoder.withIndent('  ').convert(request.toJson());
    String? error;
    try {
      final response = await widget.sdk.requestAds(request);
      json = _sentRequest(response, fallback: json);
      final decision = response.body.data?.firstOrNull;
      if (decision != null && !decision.isNoAd) {
        for (final candidate in decision.creatives ?? const <Creative>[]) {
          if (candidate.interactiveExperience is LeadGenerationExperience) {
            creative = candidate;
            break;
          }
        }
      }
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    LeadFormController? controller;
    if (creative != null) controller = _newController(creative);
    if (controller != null) _adopt(controller);
    setState(() {
      _requesting = false;
      _requested = true;
      _requestJson = json;
      _requestError = error;
      _creative = creative;
    });
    if (creative != null) {
      final shown = creative;
      unawaited(controller?.prepare());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_creative, shown)) {
          widget.sdk.fireImpression(shown.tracking);
        }
      });
    }
  }

  /// The exact headers and body the SDK sent for the last request, read from
  /// the response, so the opt-in keys and `X-Decision-Version` are visible.
  String _sentRequest(APIResponse<DecisionResponse> response,
      {required String fallback}) {
    final sent = response.response.request;
    if (sent == null) return fallback;
    final version = sent.headers['X-Decision-Version'];
    var body = fallback;
    try {
      final raw = (sent as dynamic).body as String;
      body = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      // Not a plain request: keep the builder's JSON.
    }
    return 'X-Decision-Version: ${version ?? '(none)'}\n$body';
  }

  Future<void> _onCreativeTap() async {
    final creative = _creative;
    if (creative == null || _formShown) return;
    var controller = _controller;
    final current = controller?.state.value;
    if (current is LeadFormFailed && current.retryable) {
      // open() does nothing on a failure: Retry brings the form back first.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The form failed and can be retried: press Retry')));
      return;
    }
    final reusable = controller != null &&
        current is! LeadFormDisposed &&
        current is! LeadFormExpired &&
        current is! LeadFormFailed;
    if (!reusable) {
      _releaseController();
      controller = _newController(creative);
      if (controller == null) {
        setState(() {});
        return;
      }
      _adopt(controller);
    }
    final active = controller;
    _formShown = true;
    widget.sdk.fireClick(creative.tracking); // the SDK never fires it
    unawaited(active.open());
    final opened = active.state.value;
    if (opened is LeadFormExpired || opened is LeadFormFailed) {
      // Nothing to show: the status line names the outcome.
      _formShown = false;
      setState(() {});
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _QaFormSurface(controller: active),
    ));
    // The form is gone: by its close button, Back or the host's pop.
    _formShown = false;
    if (!mounted || !identical(_controller, active)) return;
    final state = active.state.value;
    final keepForRetry = state is LeadFormFailed && state.retryable;
    if (!keepForRetry) {
      // The status keeps showing LeadFormDisposed until the next tap.
      active.setVisible(false);
      unawaited(active.dispose());
    }
    setState(() {});
  }

  @override
  void onRequestClose(LeadFormController controller) {
    // Pop the form's own route; maybePop() would run Back handling,
    // which the visible form intercepts.
    if (mounted && _formShown) Navigator.of(context).pop();
  }

  @override
  void onOpenExternalLink(
    LeadFormController controller,
    ExternalLinkPurpose purpose,
    Uri url,
  ) {
    // The link reaches the app, never the form: the QA screen only names it.
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('link: ${purpose.name} -> $url')),
    );
  }

  String _statusText() {
    final controller = _controller;
    if (controller == null) return 'state: none';
    final state = controller.state.value;
    final base = 'state: ${state.runtimeType}';
    if (state is LeadFormFailed) {
      return '$base\ncode: ${state.errorCode} retryable: ${state.retryable}';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state.value;
    final canRetry = state is LeadFormFailed && state.retryable;
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Generation QA')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Base URL: ${widget.baseUrl}'),
          SwitchListTile(
            key: const Key('qa-prefill'),
            title: const Text('Prefill'),
            value: _prefill,
            onChanged: (value) => setState(() {
              _prefill = value;
              _applyOptIn();
            }),
          ),
          SwitchListTile(
            key: const Key('qa-optin'),
            title: const Text('Opt-in'),
            value: _optIn,
            onChanged: (value) => setState(() {
              _optIn = value;
              _applyOptIn();
            }),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const Key('qa-request'),
                onPressed: _requesting ? null : () => unawaited(_request()),
                child: const Text('Request'),
              ),
              if (canRetry)
                OutlinedButton(
                  key: const Key('qa-retry'),
                  onPressed: () => unawaited(controller?.retry()),
                  child: const Text('Retry'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _statusText(),
            key: const Key('qa-status'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_requestError != null) Text('request failed: $_requestError'),
          const SizedBox(height: 8),
          _buildCreative(context),
          const SizedBox(height: 16),
          SelectableText(_requestJson, key: const Key('qa-request-json')),
        ],
      ),
    );
  }

  Widget _buildCreative(BuildContext context) {
    final creative = _creative;
    if (creative == null) {
      return Card(
        key: const Key('qa-creative'),
        child: ListTile(
          title: Text(_requested ? 'No ad' : 'Tap Request'),
        ),
      );
    }
    final offered = _controller != null;
    return Card(
      key: const Key('qa-creative'),
      child: InkWell(
        onTap: offered ? () => unawaited(_onCreativeTap()) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final content in creative.contents)
                if (content.type == 'image' && content.value is String)
                  Image.network(
                    content.value as String,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        Text('image: ${content.value}'),
                  )
                else
                  Text('${content.key}: ${content.value}'),
              if (!offered)
                const Text('form not offered: no controller for this creative'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The form on screen, as a full-screen route. It reports the
/// real visibility to the controller, as the README's `_LeadFormRoute` does.
class _QaFormSurface extends StatefulWidget {
  const _QaFormSurface({required this.controller});

  final LeadFormController controller;

  @override
  State<_QaFormSurface> createState() => _QaFormSurfaceState();
}

class _QaFormSurfaceState extends State<_QaFormSurface> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.setVisible(true);
    });
  }

  @override
  void dispose() {
    widget.controller.setVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The Scaffold resizes for the keyboard; the form draws its own close.
    return Scaffold(
      body: SafeArea(child: LeadFormView(controller: widget.controller)),
    );
  }
}
