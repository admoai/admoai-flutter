// Compile-check for the README's examples (Journey, Audience signals, Lead Generation). Not a behavioural test: it
// exists so a documented API that does not exist fails the build instead of a
// publisher's first integration.
// ignore_for_file: unused_local_variable, avoid_print
import 'dart:async';

import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings {
  bool personalisedJourneys = true;
}

class _FormHost implements LeadFormHost {
  _FormHost(this.close);
  final void Function(LeadFormController) close;

  @override
  void onRequestClose(LeadFormController controller) => close(controller);

  @override
  void onOpenExternalLink(
      LeadFormController controller, ExternalLinkPurpose purpose, Uri url) {}
}

// README, "Lead Generation forms / System Back": the full screen, inline and own
// Back control snippets.
Widget fullScreenForm(LeadFormController controller) =>
    Scaffold(body: SafeArea(child: LeadFormView(controller: controller)));

Widget inlineForm(LeadFormController controller) =>
    SizedBox(height: 480, child: LeadFormView(controller: controller));

bool handled(LeadFormController controller) => controller.handleBack();

LeadFormHost formHost() => _FormHost((controller) {});

// Never invoked: this is a compile-time check, not a behavioural test. Calling it
// would hit the network. The value is entirely in the analyzer resolving every
// symbol the README tells a publisher to call.
Future<void> readmeExamples() async {
  final host = formHost();
  final sdk = await AdMoai.initialize(
    config: SDKConfig(baseUrl: '...', apiVersion: '2025-11-01'),
    sessionId: 'sess_abc123',
  );

  var request = sdk
      .createRequestBuilder()
      .addPlacement(key: 'in_ride_map_banner')
      .setSessionId('sess_other')
      .build();

  final noJourney = sdk
      .createRequestBuilder()
      .addPlacement(key: 'home')
      .clearSessionId()
      .build();

  request = sdk
      .createRequestBuilder()
      .addPlacement(key: 'vehicleSelection')
      .setJourneyOpt(JourneyOpt.optIn)
      .build();
  var response = await sdk.requestAds(request);
  var creative = response.body.data?.first.creatives?.firstOrNull;
  if (creative != null) {
    sdk.fireImpression(creative.tracking);
    if (creative.hasCompletionUrl) {
      sdk.fireCompletion(creative.tracking, key: 'journey_complete');
    }
  }

  if (creative != null && creative.isJourneyAd()) {
    creative.journeyDealId;
    creative.journeyInstanceId;
    creative.journeyDefinitionKey;
    creative.journeyStageId;
    creative.journeyStageKey;
    creative.journeyStageNodeId;
    creative.journeySessionId;
    creative.journeyOptStatus;
    creative.journeyPricingModel;
    creative.journeyFallbackBillingMode;
    creative.isJourneyCompletion;
    creative.hasCompletionUrl;
  }

  final decision = response.body.data?.first;
  if (decision == null || decision.isNoAd) {}

  sdk.setSessionId('sess_x');

  final userSettings = _Settings();
  final toggled = sdk
      .createRequestBuilder()
      .addPlacement(key: 'vehicleSelection')
      .setJourneyOpt(
        userSettings.personalisedJourneys
            ? JourneyOpt.optIn
            : JourneyOpt.optOut,
      )
      .build();

  // Event Tracking section
  sdk.fireImpression(creative!.tracking);
  sdk.fireClick(creative.tracking);
  sdk.fireVideoEvent(creative.tracking, 'start');
  sdk.fireCustomEvent(creative.tracking, 'companionOpened');
  sdk.fireCompletion(creative.tracking, key: 'journey_complete');
  sdk.fireTracking('https://t.example/v1/tracking?e=x');

  // Quick Start section
  final built = sdk
      .createRequestBuilder()
      .addPlacement(key: 'home')
      .addPlacement(key: 'promotions', format: Format.native)
      .addGeoTargeting(2643743)
      .addCustomTargeting(key: 'category', value: 'news')
      .build();
  final headline = creative.contents.getContent('headline')?.value;
  sdk.setUserConfig(
      id: 'user_123',
      ip: '203.0.113.1',
      timezone: 'UTC',
      consent: Consent(gdpr: true));
  sdk.clearUserConfig();

  // Audience signals and Device sections
  final audience = sdk
      .createRequestBuilder()
      .addPlacement(key: 'home')
      .setAgeGroup(AgeGroup.age25To34)
      .setGender(Gender.female)
      .setAccountType(AccountType.personal)
      .setSubscriptionStatus(SubscriptionStatus.active)
      .setAccountTenure(AccountTenure.days31To90)
      .setActivityFrequency30d(ActivityFrequency30d.zero)
      .setLastActivityRecency(LastActivityRecency.days31To90)
      .setPublisherSegments(['airport_commuter', 'high_value'])
      .addCustomTargeting(key: 'category', value: 'news')
      .build();
  await sdk.requestAds(audience);
  sdk.setDeviceConfig(
      carrier: 'Example Mobile', category: DeviceCategory.tablet);
  await sdk.resetDeviceConfig();
  sdk.clearDeviceConfig();
  sdk.clearAppConfig();

  // Mirrors README "Audience signals" (Publisher segments, Request examples,
  // When the engine refuses a request) and "Device". Hand-copied, not
  // extracted: a new README snippet must be added here too.
  final segments = sdk.createRequestBuilder().addPlacement(key: 'home');
  segments.setPublisherSegments(['airport_commuter', 'beach_goer']);
  segments.setPublisherSegments(null);
  segments.setPublisherSegments([]);
  segments.clearAll();
  final optedIn = await AdMoai.initialize(
    config: SDKConfig(
      baseUrl: '...',
      apiVersion: '2025-11-01',
      collectDeviceSignals: true,
    ),
  );
  optedIn.setDeviceConfig(
      carrier: 'Example Mobile', category: DeviceCategory.phone);
  try {
    await optedIn.requestAds(
        optedIn.createRequestBuilder().addPlacement(key: 'home').build());
  } on ValidationError catch (e) {
    // 422: the code is in e.errors, for example e.errors.first.code == 10028.
    for (final error in e.errors) {
      print('${error.code}: ${error.message}');
    }
  } on ClientError catch (e) {
    // 400, 404, 429 and the other mapped 4xx: e.errors may be empty.
    if (e.status == HTTPStatus.badRequest) {
      for (final error in e.errors) {
        print('${error.code}: ${error.message}'); // 10009 for device values
      }
    }
  }
}

// Mirrors README "Lead Generation": every Dart block of that section, with the
// imports hoisted and `url_launcher` (the app's own dependency, not the SDK's)
// replaced by the stub below. Hand-copied, not extracted: a changed README block
// must be changed here too.
enum LaunchMode { externalApplication }

Future<bool> launchUrl(Uri url, {LaunchMode? mode}) async => true;

/// What the app already holds about the signed-in rider, from its own memory.
class RiderProfile {
  const RiderProfile({
    required this.fullName,
    required this.email,
    required this.phone,
  });

  final String fullName;
  final String email;
  final String phone;
}

/// With prefill: offers full name, email and phone for the current rider.
class RiderPrefillProvider implements LeadFormValueProvider {
  RiderPrefillProvider(this.currentRider);

  /// Returns the rider who is signed in right now, or null when nobody is.
  final RiderProfile? Function() currentRider;

  @override
  Set<StandardAttributeKey> get availableKeys => const {
        StandardAttributeKey.fullName,
        StandardAttributeKey.email,
        StandardAttributeKey.phone,
      };

  @override
  Future<Map<StandardAttributeKey, String>> lookUpValues(
    Set<StandardAttributeKey> keys,
  ) async {
    final rider = currentRider();
    if (rider == null) return const {};
    final all = {
      StandardAttributeKey.fullName: rider.fullName,
      StandardAttributeKey.email: rider.email,
      StandardAttributeKey.phone: rider.phone,
    };
    return {
      for (final entry in all.entries)
        if (keys.contains(entry.key)) entry.key: entry.value,
    };
  }
}

/// Without prefill: the form opens empty and the viewer types everything.
class NoPrefillProvider implements LeadFormValueProvider {
  @override
  Set<StandardAttributeKey> get availableKeys => const <StandardAttributeKey>{};

  @override
  Future<Map<StandardAttributeKey, String>> lookUpValues(
    Set<StandardAttributeKey> keys,
  ) async =>
      const {};
}

Future<AdMoai> startAdMoai(RiderProfile? Function() currentRider) async {
  final sdk = await AdMoai.initialize(
    config: SDKConfig(
        baseUrl: 'https://your-decision-engine.example.com',
        apiVersion: '2025-11-01'),
  );
  sdk.enableInteractiveExperiences(RiderPrefillProvider(currentRider));
  // Or: sdk.enableInteractiveExperiences(NoPrefillProvider());
  return sdk;
}

Future<Creative?> loadLeadGenerationCreative(AdMoai sdk) async {
  final request =
      sdk.createRequestBuilder().addPlacement(key: 'ride_summary').build();
  final response = await sdk.requestAds(request);
  final decision = response.body.data?.firstOrNull;
  if (decision == null || decision.isNoAd) return null;
  for (final creative in decision.creatives ?? const <Creative>[]) {
    switch (creative.interactiveExperience) {
      case LeadGenerationExperience():
        return creative;
      case UnsupportedInteractiveExperience():
      case null:
        continue;
    }
  }
  return null;
}

class InlineLeadCard extends StatefulWidget {
  const InlineLeadCard({super.key, required this.sdk, required this.creative});

  final AdMoai sdk;
  final Creative creative;

  @override
  State<InlineLeadCard> createState() => _InlineLeadCardState();
}

class _InlineLeadCardState extends State<InlineLeadCard>
    implements LeadFormHost {
  LeadFormController? _controller;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.sdk.createLeadFormController(
      widget.creative,
      presentation: FormPresentation.inline,
      host: this,
    );
    unawaited(_controller?.prepare());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.sdk.fireImpression(widget.creative.tracking);
    });
  }

  void _onTap() {
    final controller = _controller;
    if (controller == null) return;
    widget.sdk.fireClick(widget.creative.tracking); // the SDK never fires it
    unawaited(controller.open());
    setState(() => _expanded = true);
    // The form is on screen from the next frame: tell it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _expanded) controller.setVisible(true);
    });
  }

  @override
  void onRequestClose(LeadFormController controller) {
    // Collapse the card, then release the form.
    if (!mounted) return;
    controller.setVisible(false);
    setState(() {
      _expanded = false;
      _controller = null;
    });
    unawaited(controller.dispose());
  }

  @override
  void onOpenExternalLink(
    LeadFormController controller,
    ExternalLinkPurpose purpose,
    Uri url,
  ) {
    // A separate browser, never inside the form, and nothing added to the URL.
    unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Card(
      child: Column(
        children: [
          ListTile(
            // Your template's content keys; this one is an example.
            title: Text(
                '${widget.creative.contents.getContent('headline')?.value ?? ''}'),
            onTap: controller == null ? null : _onTap,
          ),
          if (_expanded && controller != null)
            SizedBox(height: 480, child: LeadFormView(controller: controller)),
        ],
      ),
    );
  }
}

class FullScreenLeadCard extends StatefulWidget {
  const FullScreenLeadCard(
      {super.key, required this.sdk, required this.creative});

  final AdMoai sdk;
  final Creative creative;

  @override
  State<FullScreenLeadCard> createState() => _FullScreenLeadCardState();
}

class _FullScreenLeadCardState extends State<FullScreenLeadCard>
    implements LeadFormHost {
  LeadFormController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.sdk.createLeadFormController(
      widget.creative,
      presentation: FormPresentation.fullScreen,
      host: this,
    );
    unawaited(_controller?.prepare());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.sdk.fireImpression(widget.creative.tracking);
    });
  }

  Future<void> _onTap() async {
    final controller = _controller;
    if (controller == null) return;
    widget.sdk.fireClick(widget.creative.tracking); // the SDK never fires it
    unawaited(controller.open());
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _LeadFormRoute(controller: controller),
    ));
    // The route is gone, by the form's close button or by the back gesture.
    unawaited(controller.dispose());
    if (mounted) setState(() => _controller = null);
  }

  @override
  void onRequestClose(LeadFormController controller) {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void onOpenExternalLink(
    LeadFormController controller,
    ExternalLinkPurpose purpose,
    Uri url,
  ) {
    unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(
              '${widget.creative.contents.getContent('headline')?.value ?? ''}'),
          onTap: _controller == null ? null : _onTap,
        ),
      );
}

class _LeadFormRoute extends StatefulWidget {
  const _LeadFormRoute({required this.controller});

  final LeadFormController controller;

  @override
  State<_LeadFormRoute> createState() => _LeadFormRouteState();
}

class _LeadFormRouteState extends State<_LeadFormRoute> {
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
  Widget build(BuildContext context) => Scaffold(
        // The Scaffold resizes for the keyboard; the form draws its own close button.
        body: SafeArea(child: LeadFormView(controller: widget.controller)),
      );
}

Widget leadFormStatus(LeadFormController controller) {
  return ValueListenableBuilder<LeadFormState>(
    valueListenable: controller.state,
    builder: (context, state, _) => switch (state) {
      // Retryable: the viewer can try again. Never show the error code.
      LeadFormFailed(retryable: true) => TextButton(
          onPressed: () => unawaited(controller.retry()),
          child: const Text('Try again'),
        ),
      LeadFormFailed() => const Text('This form is not available right now.'),
      // The preparation passed its expiry: offer nothing, ask for a new ad.
      LeadFormExpired() => const Text('This offer is no longer available.'),
      // The form shows its own confirmation; here you may hide your call to action.
      LeadFormSubmitted() => const SizedBox.shrink(),
      LeadFormIdle() ||
      LeadFormPreparing() ||
      LeadFormPrepared() ||
      LeadFormActivating() ||
      LeadFormReadyToShow() ||
      LeadFormVisible() ||
      LeadFormSubmitting() ||
      LeadFormDisposed() =>
        const SizedBox.shrink(),
    },
  );
}

void signOut(AdMoai sdk) {
  sdk.disposeAllLeadForms();
  sdk.setUserConfig(id: 'another_user'); // a different id also disposes forms
}

void main() {
  test('every API symbol used in the README exists and type-checks', () {
    // The assertion is trivial by design; the build failing is the real signal.
    expect(readmeExamples, isNotNull);
  });
}
