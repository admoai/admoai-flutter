# AdMoai Flutter SDK

[![pub package](https://img.shields.io/pub/v/admoai.svg)](https://pub.dev/packages/admoai)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue.svg)](https://pub.dev/packages/admoai)
[![Dart](https://img.shields.io/badge/Dart-3.0%2B-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue.svg)](https://flutter.dev)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

AdMoai Flutter SDK is a cross-platform advertising solution that enables seamless integration of native and video ads into Flutter applications. The SDK provides a robust API for requesting and displaying various ad formats with advanced targeting capabilities.

## Features

- **Native Ads** - Multiple template types (wide, image+text, text-only, carousel)
- **Video Ads** - JSON, VAST Tag, and VAST XML delivery methods, with `Format.video` placement filter
- **Journey Takeover Ads** - Multi-stage, single-brand trip journeys via `sessionId` / `journeyOpt` and read-only `creative.journey` metadata (requires `apiVersion: "2025-11-01"`)
- **Rich Targeting** - Geo, current-location, destination, and custom key-value targeting
- **GDPR Compliance** - Built-in user consent management
- **Event Tracking** - Impressions, clicks, video quartiles, and custom events
- **Open Measurement** - Pass-through support for third-party verification scripts (IAS, DoubleVerify, …)
- **Flexible Templates** - Customizable ad layouts and formats
- **Locale-aware** - `defaultLanguage` config propagates `Accept-Language` on every request
- **Configurable transport** - Per-knob timeouts (request / connect / receive) and pluggable `http.Client`
- **Per-Request Control** - Override user/device data collection per request

## Requirements

- **Flutter** 3.0+
- **Dart** 3.0+
- **iOS** 14.0+ / **Android** API 21+

## Installation

Add this to your package's pubspec.yaml file:

```yaml
dependencies:
  admoai: ^0.4.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

### 1. Initialize the SDK

```dart
final config = SDKConfig(
  baseUrl: "https://api.admoai.com",
  apiVersion: "2025-11-01",
);

final sdk = await AdMoai.initialize(config: config);
```

### 2. Configure User Settings (Optional)

```dart
sdk.setUserConfig(
  id: "user_123",
  ip: "203.0.113.1",
  timezone: "UTC",
  consent: Consent(gdpr: true),
);
```

### 3. Build and Send a Request

```dart
final request = sdk.createRequestBuilder()
    .addPlacement(key: "home")
    .addPlacement(key: "promotions", format: Format.native)
    .addGeoTargeting(2643743)
    .addCustomTargeting(key: "category", value: "news")
    .build();

final response = await sdk.requestAds(request);

response.body.data?.forEach((decision) {
  decision.creatives?.forEach((creative) {
    // Render creative
  });
});
```

### 4. Extract Content

```dart
final headline = creative.contents.getContent("headline")?.value;
final imageUrl = creative.contents.getContent("coverImage")?.value;
final videoAsset = creative.contents.getContent("video_asset")?.value;
```

### 5. Track Events

```dart
// Impressions
sdk.fireImpression(creative.tracking);

// Clicks
sdk.fireClick(creative.tracking);

// Video quartiles
sdk.fireVideoEvent(creative.tracking, "start");
sdk.fireVideoEvent(creative.tracking, "first_quartile");
sdk.fireVideoEvent(creative.tracking, "midpoint");
sdk.fireVideoEvent(creative.tracking, "third_quartile");
sdk.fireVideoEvent(creative.tracking, "complete");

// Custom events
sdk.fireCustom(creative.tracking, "companionOpened");
```

### 6. Clean Up on Logout

```dart
sdk.clearUserConfig();
sdk.clearDeviceConfig();
sdk.clearAppConfig();
```

---

## Configuration Reference

### SDKConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseUrl` | String | Required | Decision Engine API endpoint |
| `apiVersion` | String? | `null` | API version (e.g., `"2025-11-01"`) |
| `logger` | Logger | SDK default | Custom logger instance |

---

## Video Ad Support

The SDK supports three video delivery methods:

| Delivery | Response Field | Tracking |
|----------|----------------|----------|
| **JSON** | `video_asset` content key | SDK methods (`fireVideoEvent`) |
| **VAST Tag** | `vast.tagUrl` | Manual HTTP GET |
| **VAST XML** | `vast.xmlBase64` | Manual HTTP GET |

### Detecting Video Ads

```dart
creative.isJsonDelivery()
creative.isVastTagDelivery()
creative.isVastXmlDelivery()

final videoUrl = creative.contents.getContent("video_asset")?.value;
final vastTagUrl = creative.getVastTagUrl();
final vastXmlBase64 = creative.getVastXmlBase64();
```

### Video Tracking Events

**Important**: Always fire the **impression** event first when the ad is displayed, then fire video-specific events as playback progresses.

| Event | When to Fire | Key |
|-------|--------------|-----|
| **Impression** | Ad displayed (before playback) | `default` |
| Start | Video begins playing (0%) | `start` |
| First Quartile | 25% progress | `first_quartile` |
| Midpoint | 50% progress | `midpoint` |
| Third Quartile | 75% progress | `third_quartile` |
| Complete | Video ends (98%) | `complete` |
| Skip | User skips | `skip` |

```dart
sdk.fireImpression(creative.tracking);
sdk.fireVideoEvent(creative.tracking, "start");
sdk.fireVideoEvent(creative.tracking, "first_quartile");
sdk.fireVideoEvent(creative.tracking, "midpoint");
sdk.fireVideoEvent(creative.tracking, "third_quartile");
sdk.fireVideoEvent(creative.tracking, "complete");
```

### Video Helper Methods

```dart
final isSkippable = creative.isSkippable();
final skipOffset = creative.getSkipOffset();
```

---

## Event Tracking

The SDK fires tracking beacons via HTTP requests automatically.

### Available Methods

```dart
sdk.fireImpression(trackingInfo); // optional: key: "default"
sdk.fireClick(trackingInfo); // optional: key: "default"
sdk.fireVideoEvent(trackingInfo, "start");
sdk.fireCustom(trackingInfo, "companionOpened");
```

### Tracking Keys

Each tracking type supports multiple keys. Use `"default"` for standard events or specify custom keys defined in your campaign configuration.

---

## Journey Takeover Ads

Journey Takeover Ads let a single brand tell an ordered, multi-stage story across a trip (e.g. pre-ride → in-ride → post-ride). The **decision-engine owns all Journey logic** — eligibility, stage progression, single-brand takeover protection, completion, and billing. The SDK only forwards your Journey context, parses the read-only Journey metadata, and fires the exact server-provided tracking URLs.

> **Requires `apiVersion: "2025-11-01"` or later.** Journey behavior is gated on the API version; without it (or with an older version) the engine ignores the Journey fields and serves normal ads. Journey fields are fully additive, so existing integrations keep working unchanged.

### 1. Provide a stable session id

Journey sequencing needs a **stable, publisher-owned `sessionId`** that is the same across every placement request belonging to one trip. You own its lifetime — the SDK never generates or changes it. Rotate it (start a new journey) only when your own rules say the trip changed (e.g. the app was backgrounded for 2h+).

```dart
final sdk = await AdMoai.initialize(
  config: SDKConfig(baseUrl: '...', apiVersion: '2025-11-01'),
  sessionId: 'trip_abc123', // sticky default, inherited by every builder
);

// Rotate when a new journey begins:
sdk.setSessionId('trip_def456');

// Or override per request:
final request = sdk
    .createRequestBuilder()
    .addPlacement(key: 'in_ride_map_banner')
    .setSessionId('trip_abc123')
    .setJourneyOpt(JourneyOpt.optIn) // or JourneyOpt.optOut
    .build();
```

`sessionId` must be ≤ 256 **UTF-8 bytes** (ASCII opaque ids recommended). Blank values are omitted; over-length values are sent as-is and the SDK logs a PII-safe warning (reason only, never the value) — the engine will treat such a value as absent and disable Journey for that request.

Use `journeyOpt` to gate a session in/out at serve time (including mid-journey). Opt-out ends the active journey; a later opt-in may start a **new** `journeyInstanceId`.

### 2. Read Journey metadata (read-only)

```dart
final creative = response.body.data?.first.creatives?.first;
if (creative != null && creative.isJourneyAd()) {
  creative.journeyDealId;      // commercial Journey Ad id
  creative.journeyInstanceId;  // this journey attempt
  creative.journeyStageId;     // current stage
  creative.journeyStageNodeId; // current node (surface)
  creative.journeyOptStatus;   // JourneyOpt.optIn / optOut / null
}
```

These values are server-owned. Never use them to infer progression, completion, or billing — the engine is authoritative. `optStatus` is an open set: an unrecognized value parses to `null` (malformed/unknown), not a business state.

### 3. Tracking & completion

Fire the returned tracking URLs verbatim (see [Event Tracking](#event-tracking)). For `vast_tag` / `vast_xml` video, beacons live inside the VAST — do **not** also fire `creative.tracking` for those. Completion has two server-owned modes:

- **`custom_event`** — `creative.tracking.completions` is populated. Fire it **once** when the mapped completion action occurs, and do **not** also fire a matching `custom` URL for the same action:

  ```dart
  if (creative.hasCompletionUrl) {
    sdk.fireCompletion(creative.tracking, key: 'purchase');
  }
  ```

- **`final_stage`** — `creative.isJourneyCompletion == true` and there is **no** completion URL. Completion is recorded server-side when the final stage serves; just fire the normal impression. Never synthesize or infer completion locally.

### 4. No-ad and takeover protection

While a Journey is active on its surfaces, the engine returns **no ad** rather than a competing brand. Treat both `creatives: []` and `creatives: null` uniformly as no-ad and never substitute a local, cached, or house ad:

```dart
final decision = response.body.data?.first;
if (decision == null || decision.isNoAd) {
  // Render nothing. Do not fall back to another ad on a Journey surface.
}
```

---

## Request Builder

The `DecisionRequestBuilder` provides a fluent API:

```dart
final request = sdk.createRequestBuilder()
    .addPlacement(key: "home")
    .addPlacement(key: "promotions", format: Format.native)
    
    .setUserId("user_123")
    .setUserIp("203.0.113.1")
    .setUserTimezone("America/New_York")
    .setUserConsent(Consent(gdpr: true))
    
    .addGeoTargeting(2643743)
    .addLocationTargeting(latitude: 37.7749, longitude: -122.4194)
    .addCustomTargeting(key: "category", value: "news")
    
    .disableAppCollection()
    .disableDeviceCollection()
    
    .build();
```

---

## Response Structure

```
APIResponse<DecisionResponse>
├── response: http.Response
├── body: APIResponseBody<DecisionResponse>
│   ├── success: bool
│   ├── data: List<Decision>?
│   │   └── Decision
│   │       ├── placement: String
│   │       └── creatives: List<Creative>?
│   │           └── Creative
│   │               ├── contents: List<Content>
│   │               ├── advertiser: Advertiser
│   │               ├── template: Template
│   │               ├── tracking: Tracking
│   │               ├── metadata: Metadata
│   │               ├── delivery: String
│   │               └── vast: VastData?
│   ├── errors: List<AdMoaiError>?
│   └── warnings: List<AdMoaiWarning>?
└── rawBody: String?
```

---

## Open Measurement (OM)

The Admoai Flutter SDK surfaces third-party verification resources (e.g. IAS, DoubleVerify, Moat) returned by the decision engine, so publishers can plug them into their own OM integration.

**Important:** Admoai is not OM-certified and does **not** bundle the IAB OM SDK. The SDK only exposes the verification metadata — the publisher is responsible for loading the scripts into a verified, namespaced OM SDK in their app.

### Accessing verification resources

```dart
import 'package:admoai/admoai.dart';

response.body.data?.forEach((decision) {
  decision.creatives?.forEach((creative) {
    if (creative.hasOMVerification()) {
      final resources = creative.getVerificationResources()!;
      for (final r in resources) {
        // Pass r.vendorKey, r.scriptUrl, r.verificationParameters
        // to your OM SDK integration.
      }
    }
  });
});
```

### Integration paths

1. **Native OM SDK (IAB)** — Full control. Bundle the IAB-namespaced Open Measurement SDK into your app and pass each `VerificationScriptResource` to its `VerificationScriptResource` API. Publisher owns the namespace and the integration.
2. **Google IMA SDK** — IMA handles `<AdVerifications>` automatically when fed a VAST tag/XML. The verification resources are processed inside IMA; no extra wiring needed.
3. **Third-party players (e.g. JW Player)** — Commercial players ship with OM support; consult their docs for how to feed the verification metadata.

### VerificationScriptResource shape

| Field | Type | Description |
|---|---|---|
| `vendorKey` | `String` | Vendor identifier (e.g. `"ias"`, `"doubleverify"`). |
| `scriptUrl` | `String` | JavaScript URL the verification provider hosts. |
| `verificationParameters` | `String?` | Optional opaque parameters the SDK passes through unchanged. |

---

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- How to submit Pull Requests
- Commit message conventions (Conventional Commits)
- Code style and testing requirements
- Development workflow

## Example App

For a complete example implementation, check out the [example app](example/).

## Documentation

For detailed documentation, please visit our [documentation site](https://docs.admoai.com).

## Support

- **Issues**: [GitHub Issues](https://github.com/admoai/admoai-flutter/issues)
- **Email**: support@admoai.com

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ by the AdMoai Team**
