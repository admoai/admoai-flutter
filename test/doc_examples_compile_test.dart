// Compile-check for the README's Journey examples. Not a behavioural test: it
// exists so a documented API that does not exist fails the build instead of a
// publisher's first integration.
// ignore_for_file: unused_local_variable, avoid_print
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

void main() {
  test('every API symbol used in the README exists and type-checks', () {
    // The assertion is trivial by design; the build failing is the real signal.
    expect(readmeExamples, isNotNull);
  });
}
