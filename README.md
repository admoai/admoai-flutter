# AdMoai Flutter SDK

AdMoai Flutter SDK is a cross-platform advertising solution that enables seamless integration of ads into Flutter applications. The SDK provides a robust API for requesting and displaying various ad formats with advanced targeting capabilities.

## Features

- Native ad format support
- Rich targeting options (geo, location, custom)
- User consent management (GDPR)
- Flexible ad templates
- Companion ad support
- Carousel ad layouts
- Impression and click tracking
- Per-request data collection control

## Requirements

- Flutter 3.0+
- Dart 3.0+
- iOS 14.0+ / Android API 21+

## Installation

Add this to your package's pubspec.yaml file:

```yaml
dependencies:
  admoai: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

1. Initialize the SDK:

```dart
// Initialize SDK with base URL and optional configurations
final config = SDKConfig(baseUrl: "https://example.api.admoai.com");
final sdk = await AdMoai.initialize(config: config);

// Configure user settings globally
sdk.setUserConfig(
  id: "user_123",
  ip: "203.0.113.1",
  timezone: "UTC",
  consent: Consent(gdpr: true),
);
```

2. Create and send an ad request:

```dart
// Build request with placement
final request = sdk.createRequestBuilder()
    .addPlacement(key: "home")
    .build();

// Request ads
final response = await sdk.requestAds(request);
```

You can also build the request with targeting and user settings:

```dart
final request = sdk.createRequestBuilder()
    .addPlacement(key: "home")

    // Override user settings for this request
    .setUserId("different_user")
    .setUserIp("203.0.113.2")
    .setUserTimezone("America/New_York")
    .setUserConsent(Consent(gdpr: false))

    // Add targeting
    .addGeoTargeting(2643743)  // London
    .addLocationTargeting(latitude: 37.7749, longitude: -122.4194)
    .addCustomTargeting(key: "category", value: "news")

    // Build request
    .build();
```

3. Handle the creative:

```dart
if (response.body.data?.isNotEmpty == true) {
  final decision = response.body.data!.first;
  if (decision.creatives?.isNotEmpty == true) {
    final creative = decision.creatives!.first;

    // Access creative properties
    final headline = creative.contents.getContent(key: "headline")?.value;
    final imageUrl = creative.contents.getContent(key: "coverImage")?.value;

    // Track impression
    sdk.fireImpression(tracking: creative.tracking);

    // Handle click with tracking
    final clickUrl = creative.tracking.getClickUrl();
    if (clickUrl != null) {
      launchUrl(Uri.parse(clickUrl));
    }
  }
}
```

4. Clean up on logout:

```dart
// Reset user configuration when user logs out
sdk.clearUserConfig();  // Resets to: id = null, ip = null, timezone = null, consent.gdpr = false
```

## Event Tracking

The SDK automatically handles event tracking through HTTP requests. Each creative contains tracking URLs for different events (impressions, clicks, custom events) that are called when triggered.

### Tracking Configuration

Each creative includes tracking configuration for different event types:

```dart
// Available tracking URLs in the creative
creative.tracking.impressions  // List of impression tracking URLs
creative.tracking.clicks       // List of click tracking URLs
creative.tracking.custom       // List of custom event tracking URLs

// Get specific URLs
final impressionUrl = creative.tracking.getImpressionUrl(key: "default");
final clickUrl = creative.tracking.getClickUrl(key: "default");
final customUrl = creative.tracking.getCustomUrl(key: "companionOpened");
```

### Firing Events

Use the SDK to fire tracking events:

```dart
// Fire impressions
sdk.fireImpression(tracking: creative.tracking);  // "default" key
sdk.fireImpression(tracking: creative.tracking, key: "slide1");

// Fire clicks
sdk.fireClick(tracking: creative.tracking);  // "default" key
sdk.fireClick(tracking: creative.tracking, key: "slide1");

// Fire custom events
sdk.fireCustom(tracking: creative.tracking, key: "companionOpened");
```

> [!NOTE]
> The `key` parameter is optional for impressions and clicks, defaulting to `default`.

### Utility Functions

Here's an example of utility functions to handle tracking and URL opening:

```dart
void handleImpression(Creative creative, {String? key}) {
  sdk.fireImpression(tracking: creative.tracking, key: key);
}

void handleClick(Creative creative, {String? key}) {
  // Get click URL which includes tracking
  final clickUrl = creative.tracking.getClickUrl(key: key ?? "default");
  if (clickUrl != null) {
    // Opening URL in browser handles both tracking and redirection
    launchUrl(Uri.parse(clickUrl));
  }
}

void handleCustomEvent(Tracking tracking, String key) {
  sdk.fireCustom(tracking: tracking, key: key);
}
```

> [!NOTE]
> For click tracking, opening the URL in a browser handles both the tracking and destination URL redirection in a single request.

## Example App

For a complete example implementation, check out the [example app](example/README.md).

## Documentation

For detailed documentation, please visit our [documentation site](https://docs.admoai.com).
