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
sdk.fireCustomEvent(creative.tracking, "companionOpened");
```

Nothing is fired automatically — you decide when each event happens. All `fire*`
methods are fire-and-forget: they return `void`, dispatch in the background, and
never throw into your code.

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
| `apiVersion` | String? | `null` | API version. **Required for Journey Ads** (`"2025-11-01"` or later) and for the `format` placement filter |
| `defaultLanguage` | String? | `null` | Sent as `Accept-Language` on every request |
| `requestTimeout` | Duration | 10s | Per-request timeout |
| `connectTimeout` | Duration | 10s | Connection timeout (default HTTP client only) |
| `receiveTimeout` | Duration | 10s | Idle timeout (default HTTP client only) |
| `logger` | Logger | SDK default | Custom logger instance |

`AdMoai.initialize` additionally accepts `sessionId` (the sticky Journey session —
see [Journey Takeover Ads](#journey-takeover-ads)) and `httpClient` (a custom
`http.Client`).

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
final skipOffset = creative.getSkipOffset();   // String?
```

Both read the engine-owned `creative.metadata` first and fall back to the creative's
content fields. For a typed value, read `creative.metadata?.isSkippable` (`bool?`)
and `creative.metadata?.skipOffsetSeconds` (`int?`) directly.

---

## Event Tracking

**The SDK never fires anything automatically.** You call a `fire*` method when the
event happens in your UI. Each one fires the exact URL the server returned,
verbatim — never parse, rebuild, or append to a tracking URL; the identity is
inside the opaque `?e=` token.

All `fire*` methods are **fire-and-forget**: they return `void`, dispatch on the
SDK's own scope, and never throw into the caller. Network failures are logged, not
surfaced — so there is no return value to retry on. If you need a retry, call the
method again with the same `Tracking` object; the identical URL is re-fired.

### Available Methods

```dart
sdk.fireImpression(creative.tracking);                        // optional: key: "default"
sdk.fireClick(creative.tracking);                             // optional: key: "default"
sdk.fireVideoEvent(creative.tracking, "start");
sdk.fireCustomEvent(creative.tracking, "companionOpened");
sdk.fireCompletion(creative.tracking, key: "journey_complete"); // Journey custom_event deals
sdk.fireTracking(url);                                         // fire a URL you already hold
```

`fireCustom` is a deprecated alias of `fireCustomEvent`, kept for compatibility and
removed in 1.0.0.

### Tracking Keys

Each tracking type supports multiple keys. Use `"default"` for standard events or specify custom keys defined in your campaign configuration.

---

## Journey Takeover Ads

A **Journey Takeover Ad** is a single-advertiser takeover spanning several screens
of one user session (e.g. pre-ride → in-ride → post-ride). Instead of an
independent decision per placement, one advertiser holds the journey: the engine
walks the user through an ordered set of **stages**, keeps progress against the
`sessionId` you supply, and suppresses competing ads on the placements it owns
until the journey ends.

> **Requires `apiVersion: "2025-11-01"` or later.** Without it the engine
> **silently** ignores the Journey fields and serves normal ads — no error, no
> empty response. The SDK logs a warning if you send Journey context without an
> `apiVersion`. Journey fields are fully additive, so existing integrations keep
> working unchanged.

### What the SDK does, and never does

Everything about journeys is server-owned. The SDK has exactly three jobs.

| The SDK does | The SDK never does |
|---|---|
| Forwards `sessionId` and `journeyOpt` on the request | Generate, rotate, or persist a `sessionId` |
| Exposes read-only journey metadata off the served creative | Decide which stage serves next, or track progress |
| Fires the exact tracking URLs the engine returned, when you tell it to | Fire anything automatically, or on a timer |
| Reports a no-ad faithfully | Substitute a cached, local, or house ad |
| — | Infer completion, eligibility, or billing |

If you find yourself running a state machine, inferring a stage, or rebuilding a
tracking URL, something has gone wrong.

### The one rule: one session id, every call

This is the first Admoai feature where a **sequence** of calls behaves differently
from a set of unrelated ones — and the only part you have to get right.

**Every request belonging to one user session must carry the same `sessionId`.**

Two ways to get it wrong, both silent:

| Mistake | What happens |
|---|---|
| A *different* `sessionId` on a later screen | The engine sees a new session and **restarts** the journey from stage 1. The user sees stage 1 again and never reaches the end. |
| *No* `sessionId` at all | Journeys **never activate**. You keep serving normal ads. This is the safe default — nothing breaks, you just get no journeys. |

### 1. The `sessionId` contract

```dart
final sdk = await AdMoai.initialize(
  config: SDKConfig(baseUrl: '...', apiVersion: '2025-11-01'),
  sessionId: 'sess_abc123', // sticky: inherited by every builder from here on
);
```

- **You own it.** The SDK never creates or changes it.
- **It is sticky.** Set it once and every builder created afterwards carries it;
  rebuilding a request never regenerates it.
- **Override or clear per request** when you need to:

  ```dart
  final request = sdk
      .createRequestBuilder()
      .addPlacement(key: 'in_ride_map_banner')
      .setSessionId('sess_other')  // this request only
      .build();

  final noJourney = sdk
      .createRequestBuilder()
      .addPlacement(key: 'home')
      .clearSessionId()            // this request only
      .build();
  ```

- **When to rotate it** (i.e. start a new journey): a new app launch, login,
  logout, or when the business activity genuinely ends (the trip finished, the
  order was delivered). Rotating on every screen restarts the journey; never
  rotating across genuinely separate activities blends them into one.
- **Maximum 256 UTF-8 bytes.** Longer values are sent as-is, but the engine treats
  them as absent and Journey is disabled for that request. The SDK logs a
  **PII-safe** warning — a reason token only, never the value.
- **It is PII, and it is not a user id.** Use an opaque, rotating identifier. Do
  not reuse your `user.id`, and do not log it.

### 2. The three `journeyOpt` states

```dart
.setJourneyOpt(JourneyOpt.optIn)   // "give me a journey"
.setJourneyOpt(JourneyOpt.optOut)  // "no journeys for this session"
// or omit setJourneyOpt entirely
```

> ⚠️ **Omitting `journeyOpt` is permissive, not neutral.** With a `sessionId`
> present and no `journeyOpt`, journeys **may serve** and an already-active journey
> **continues**. Only `JourneyOpt.optOut` suppresses them. This is the single most
> likely misreading of this API.
>
> So if you want a request that definitely has no journey — a control, a
> screenshot, a diagnostic — send **no `sessionId` at all**. An "opt-out" that
> merely omits `journeyOpt` does the opposite of what it looks like.

**Opt-out *ends* a journey rather than pausing it.** A later opt-in cannot resume
it — the engine mints a **new** `journeyInstanceId` and starts over. Completed
journeys are terminal for the same reason.

### 3. Read journey metadata (read-only)

```dart
final creative = response.body.data?.first.creatives?.first;
if (creative != null && creative.isJourneyAd()) {
  creative.journeyDealId;              // the commercial Journey Ad
  creative.journeyInstanceId;          // this journey attempt — constant for the journey
  creative.journeyDefinitionKey;       // the journey definition
  creative.journeyStageId;             // current stage id
  creative.journeyStageKey;            // current stage key, e.g. "pre_ride"
  creative.journeyStageNodeId;         // current node (stage + surface)
  creative.journeySessionId;           // the session id echoed back
  creative.journeyOptStatus;           // JourneyOpt.optIn / optOut / null
  creative.journeyPricingModel;        // e.g. "cpt"
  creative.journeyFallbackBillingMode; // e.g. "bill_per_stage"
  creative.isJourneyCompletion;        // true only on a final_stage completion
  creative.hasCompletionUrl;           // true only on a custom_event deal
}
```

On a normal ad every one of these is `null` (or `false`) — never a crash and never
a default object. `isJourneyAd()` is `true` only when the engine issued a real deal
or instance id.

`creative.metadata.impId` carries the engine's **render-level attribution key**, minted
per served creative and present on every Journey serve (`null` on normal ads). Use it to
reconcile a specific render against reporting; it is not a substitute for the tracking
token, and the SDK derives nothing from it.

> **Do not branch your UI on stage keys or node ids.** They are server-owned
> identifiers that change when a campaign is reconfigured; a UI keyed to
> `"pre_ride"` breaks the day someone renames a stage. Render whatever the creative
> contains. `optStatus` is an open set — an unrecognized value parses to `null`
> (meaning "unknown"), not to a business state.

### 4. Completion — two modes, chosen by the campaign

The two are mutually exclusive per deal, and both are **additive** to the normal
impression rather than a replacement. Always fire the impression as usual.

**`custom_event` — you must fire it, and it is what bills.**

`creative.tracking.completions` is populated. The completion is recorded **only**
when you fire the beacon. If you never fire it, the advertiser is never charged for
the completion.

```dart
if (creative.hasCompletionUrl) {
  sdk.fireCompletion(creative.tracking, key: 'journey_complete');
}
```

Fire it **once**, when the action you agreed with the advertiser actually happens.
Do not also fire a matching `custom` URL for the same action — that double counts.

**`final_stage` — there is nothing to fire.**

`creative.isJourneyCompletion == true` and there is **no** completion URL.
Completion was recorded server-side the moment the final stage served. Just fire the
normal impression. Never synthesize or infer a completion locally.

### 5. No-ad is correct behaviour, not a failure

While a journey holds its surfaces, the engine returns **no ad** rather than a
competing brand. That is takeover protection working.

```dart
final decision = response.body.data?.first;
if (decision == null || decision.isNoAd) {
  // Collapse the slot. Render nothing.
}
```

- Treat `creatives: []`, `creatives: null`, and an absent `creatives` **identically**
  — `isNoAd` covers all three. Do not branch on which empty shape came back; the
  reason is server-side only.
- **Do not substitute** another ad on a journey surface — it breaks the takeover you
  sold.
- **Do not retry in a loop.** The answer will not change within the session.

### 6. Journey ads with video

For `vast_tag` and `vast_xml` delivery, the impression, quartile and click beacons
live **inside the VAST document** and belong to your player. The SDK deliberately
surfaces no VAST-owned video events. If you fire `creative.tracking` *and* let the
player fire the VAST beacons, everything is counted twice.

For `json` delivery the beacons come from `creative.tracking.videoEvents` and are
yours to fire from your player's callbacks.

### Worked example: a multi-screen session

One session id across every screen. Nothing else is required of you.

```dart
// A session begins — the user starts a ride, opens an order, whatever your
// product calls a session. Mint one id and hold it.
final sessionId = 'sess_${DateTime.now().microsecondsSinceEpoch}';
sdk.setSessionId(sessionId);

// Screen 1 — vehicle selection.
var request = sdk
    .createRequestBuilder()
    .addPlacement(key: 'vehicleSelection')
    .setJourneyOpt(JourneyOpt.optIn)
    .build();
var response = await sdk.requestAds(request);
var creative = response.body.data?.first.creatives?.firstOrNull;
if (creative != null) {
  render(creative);
  sdk.fireImpression(creative.tracking);
}

// Screen 2 — during the ride. Same session id (inherited from setSessionId),
// so the engine advances the journey instead of restarting it.
request = sdk
    .createRequestBuilder()
    .addPlacement(key: 'journey')
    .setJourneyOpt(JourneyOpt.optIn)
    .build();
response = await sdk.requestAds(request);

// Screen 3 — ride summary. Still the same session id.
request = sdk
    .createRequestBuilder()
    .addPlacement(key: 'rideSummary')
    .setJourneyOpt(JourneyOpt.optIn)
    .build();
response = await sdk.requestAds(request);
creative = response.body.data?.first.creatives?.firstOrNull;
if (creative != null) {
  sdk.fireImpression(creative.tracking);
  // custom_event deals hand you a beacon; final_stage deals do not.
  if (creative.hasCompletionUrl) {
    sdk.fireCompletion(creative.tracking, key: 'journey_complete');
  }
}

// The session ends — rotate for the next one.
sdk.setSessionId('sess_${DateTime.now().microsecondsSinceEpoch}');
```

### Worked example: honouring a personalisation toggle

Opting out of journeys does **not** mean opting out of ads. Normal ads keep serving.

```dart
final request = sdk
    .createRequestBuilder()
    .addPlacement(key: 'vehicleSelection')
    .setJourneyOpt(
      userSettings.personalisedJourneys ? JourneyOpt.optIn : JourneyOpt.optOut,
    )
    .build();
```

Remember that `optOut` **ends** any active journey rather than pausing it. If the
user turns the setting back on, the engine starts a **new** journey — it cannot
resume the one it closed.

### Common mistakes

| Mistake | Consequence | Do this instead |
|---|---|---|
| A new `sessionId` on each screen | The journey restarts at stage 1 forever | Mint one id per session and reuse it on every call |
| No `sessionId` | Journeys never activate; you see only normal ads | Set it once via `initialize(sessionId:)` or `setSessionId` |
| Omitting `journeyOpt` to mean "no journeys" | Permissive — journeys serve and continue anyway | Send `JourneyOpt.optOut`, or no `sessionId` at all |
| No `apiVersion` (or an older one) | Journey fields are silently ignored | Set `apiVersion: "2025-11-01"` |
| Substituting a house ad on a journey no-ad | Breaks the single-brand takeover you sold | Collapse the slot |
| Branching UI on `journeyStageKey` | Breaks when a campaign is reconfigured | Render the creative's contents |
| Not firing the `custom_event` completion beacon | The advertiser is never charged for the completion | Fire it once when the agreed action happens |
| Firing `creative.tracking` for `vast_*` delivery | Every event counted twice | Let the player fire the VAST beacons |
| Re-requesting in a loop after a no-ad | Wasted calls; the answer will not change | Collapse the slot and move on |
| Reusing your `user.id` as the `sessionId` | Cross-session PII leak, and journeys never end | Use an opaque per-session id |

### Verifying your integration

Two checks catch most integration bugs.

1. **The instance id must stay constant across a session.** Log it on every serve:

   ```dart
   debugPrint('journey instance: ${creative.journeyInstanceId}');
   ```

   If it changes mid-session, your `sessionId` is changing (or the session's
   server-side state expired).

2. **The stage key must advance and never repeat.**

   ```dart
   debugPrint('journey stage: ${creative.journeyStageKey}');
   ```

   Seeing `pre_ride` on every screen means each request is starting a new journey.

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

`clearAll()` resets a builder for reuse: it drops placements, targeting and user, stops automatic
app and device collection, and clears `journeyOpt`. It deliberately **keeps** the sticky
`sessionId` — that is session-scoped state, not per-request state, so a journey survives a builder
reset. Call `clearSessionId()` to drop it explicitly.

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
│   │       └── creatives: List<Creative>?          // null or [] ⇒ no ad
│   │           └── Creative
│   │               ├── contents: List<Content>
│   │               ├── advertiser: Advertiser
│   │               ├── template: Template
│   │               ├── tracking: Tracking
│   │               │   ├── impressions: List<TrackingItem>?
│   │               │   ├── clicks: List<TrackingItem>?
│   │               │   ├── custom: List<TrackingItem>?
│   │               │   ├── videoEvents: List<TrackingItem>?
│   │               │   └── completions: List<TrackingItem>?   // Journey custom_event
│   │               ├── metadata: Metadata?
│   │               ├── delivery: String?           // json | vast_tag | vast_xml
│   │               ├── vast: VastData?
│   │               ├── journey: CreativeJourney?   // Journey serves only, else null
│   │               └── verificationScriptResources: List<VerificationScriptResource>?
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
