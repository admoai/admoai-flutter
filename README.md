# AdMoai Flutter SDK

[![pub package](https://img.shields.io/pub/v/admoai.svg)](https://pub.dev/packages/admoai)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue.svg)](https://pub.dev/packages/admoai)
[![Dart](https://img.shields.io/badge/Dart-3.0%2B-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue.svg)](https://flutter.dev)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

AdMoai Flutter SDK is a cross-platform advertising solution that enables seamless integration of native and video ads into Flutter applications. The SDK provides a robust API for requesting and displaying various ad formats with advanced targeting capabilities.

## Features

- **Native Ads** - Multiple template types (wide, image+text, text-only, carousel)
- **Video Ads** - JSON, VAST Tag, and VAST XML delivery methods
- **Rich Targeting** - Geo, location, and custom key-value targeting
- **GDPR Compliance** - Built-in user consent management
- **Event Tracking** - Impressions, clicks, video quartiles, and custom events
- **Flexible Templates** - Customizable ad layouts and formats
- **Per-Request Control** - Override user/device data collection per request

## Requirements

- **Flutter** 3.0+
- **Dart** 3.0+
- **iOS** 14.0+ / **Android** API 21+

## Installation

Add this to your package's pubspec.yaml file:

```yaml
dependencies:
  admoai: ^0.2.0
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
final headline = creative.contents.getContent(key: "headline")?.value;
final imageUrl = creative.contents.getContent(key: "coverImage")?.value;
final videoAsset = creative.contents.getContent(key: "video_asset")?.value;
```

### 5. Track Events

```dart
// Impressions
sdk.fireImpression(tracking: creative.tracking);

// Clicks
sdk.fireClick(tracking: creative.tracking);

// Video quartiles
sdk.fireVideoEvent(tracking: creative.tracking, key: "start");
sdk.fireVideoEvent(tracking: creative.tracking, key: "first_quartile");
sdk.fireVideoEvent(tracking: creative.tracking, key: "midpoint");
sdk.fireVideoEvent(tracking: creative.tracking, key: "third_quartile");
sdk.fireVideoEvent(tracking: creative.tracking, key: "complete");

// Custom events
sdk.fireCustom(tracking: creative.tracking, key: "companionOpened");
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

final videoUrl = creative.contents.getContent(key: "video_asset")?.value;
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
sdk.fireImpression(tracking: creative.tracking);
sdk.fireVideoEvent(tracking: creative.tracking, key: "start");
sdk.fireVideoEvent(tracking: creative.tracking, key: "first_quartile");
sdk.fireVideoEvent(tracking: creative.tracking, key: "midpoint");
sdk.fireVideoEvent(tracking: creative.tracking, key: "third_quartile");
sdk.fireVideoEvent(tracking: creative.tracking, key: "complete");
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
sdk.fireImpression(tracking: trackingInfo, key: "default");
sdk.fireClick(tracking: trackingInfo, key: "default");
sdk.fireVideoEvent(tracking: trackingInfo, key: "start");
sdk.fireCustom(tracking: trackingInfo, key: "companionOpened");
```

### Tracking Keys

Each tracking type supports multiple keys. Use `"default"` for standard events or specify custom keys defined in your campaign configuration.

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
