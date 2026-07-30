// Compile-check for the README's Journey examples. Not a behavioural test: it
// exists so a documented API that does not exist fails the build instead of a
// publisher's first integration.
// ignore_for_file: unused_local_variable, avoid_print
import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings { bool personalisedJourneys = true; }

// Never invoked: this is a compile-time check, not a behavioural test. Calling it
// would hit the network. The value is entirely in the analyzer resolving every
// symbol the README tells a publisher to call.
Future<void> readmeExamples() async {
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
  final built = sdk.createRequestBuilder()
      .addPlacement(key: 'home')
      .addPlacement(key: 'promotions', format: Format.native)
      .addGeoTargeting(2643743)
      .addCustomTargeting(key: 'category', value: 'news')
      .build();
  final headline = creative.contents.getContent('headline')?.value;
  sdk.setUserConfig(
      id: 'user_123', ip: '203.0.113.1', timezone: 'UTC',
      consent: Consent(gdpr: true));
  sdk.clearUserConfig();
  sdk.clearDeviceConfig();
  sdk.clearAppConfig();
}

void main() {
  test('every API symbol used in the README exists and type-checks', () {
    // The assertion is trivial by design; the build failing is the real signal.
    expect(readmeExamples, isNotNull);
  });
}
