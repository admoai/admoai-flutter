# AdMoai Flutter SDK

[![pub package](https://img.shields.io/pub/v/admoai.svg)](https://pub.dev/packages/admoai)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue.svg)](https://pub.dev/packages/admoai)
[![Dart](https://img.shields.io/badge/Dart-3.0%2B-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue.svg)](https://flutter.dev)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

AdMoai Flutter SDK is a cross-platform advertising solution that enables seamless integration of native and video ads into Flutter applications. The SDK provides a robust API for requesting and displaying various ad formats with advanced targeting capabilities.

## Features

- **Native Ads** - Multiple template types (wide, image+text, text-only, carousel)
- **Admoai standard formats** - Native Display, Carousel, Tap-to-expand, Branded Assets, Standard Video
  and Sponsored Pin Locations, plus templates based on a standard. Read
  [Admoai standard formats](#admoai-standard-formats): the SDK draws none of them, and it never
  fires a beacon on its own
- **Video Ads** - JSON, VAST Tag, and VAST XML delivery methods, with `Format.video` placement filter
- **Journey Ads** - Multi-stage, single-brand trip journeys via `sessionId` / `journeyOpt` and read-only `creative.journey` metadata (requires `apiVersion: "2025-11-01"`)
- **Sponsored Pin Locations** – Promote an advertiser's real places as pins on your map.
  Read [Sponsored Pin Locations](#sponsored-pin-locations) before integrating: the SDK
  renders nothing and never infers that a pin was seen, so the measurement contract is
  yours to honour
- **Lead Generation** (experimental) - A native creative that opens a hosted lead form in an SDK-owned secure web view; read [Lead Generation](#lead-generation) (requires `apiVersion: "2025-11-01"`)
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
  admoai: ^0.8.0
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
| `apiVersion` | String? | `null` | Engine API version. `"2025-11-01"` gates Journey Ads, video ads, POI / destination targeting, mid-flight campaign changes, Open Measurement and the `format` placement filter |
| `defaultLanguage` | String? | `null` | Sent as `Accept-Language` on every request |
| `requestTimeout` | Duration | 10s | Per-request timeout |
| `connectTimeout` | Duration | 10s | Connection timeout (default HTTP client only) |
| `receiveTimeout` | Duration | 10s | Idle timeout (default HTTP client only) |
| `logger` | Logger | SDK default | Custom logger instance |
| `collectDeviceSignals` | bool | `false` | Opt-in: read the device's mobile carrier and category (phone, tablet, other) and send them as `device.carrier` / `device.category` |

**Device carrier and category are opt-in.** The default SDK never sends them. A workspace without
audience signals enabled rejects a request that carries them, so an app that sent them before its
workspace is ready would get no ads. Turn collection on once audience signals are enabled for your
workspace, or set the values by hand; a value set by hand is sent with or without the flag:

```dart
final sdk = await AdMoai.initialize(
  config: SDKConfig(
    baseUrl: 'https://api.admoai.com',
    apiVersion: '2025-11-01',
    collectDeviceSignals: true,
  ),
);

// Or by hand:
sdk.setDeviceConfig(carrier: 'Example Mobile', category: DeviceCategory.phone);
```

`AdMoai.initialize` additionally accepts `sessionId` (the sticky Journey session —
see [Journey Ads](#journey-ads)) and `httpClient` (a custom
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

A click beacon records the click and nothing else. The tracking endpoint answers
a click with a `302` to the creative's destination, which is meant for browsers;
the SDK takes that response as final and never requests the destination. Opening
it is your app's job — call `fireClick` and navigate from the creative's contents.

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

### Third-party Event Trackers (automatic)

#### Why this exists commercially

Advertisers often buy through an agency, and the agency counts impressions and
clicks on **its own ad server** (Google CM360 and similar) before it will activate
or renew a campaign. Their trafficking sheet supplies fixed measurement URLs —
"GET this URL of mine every time the ad is shown". Without a safe way to fire
those URLs, campaigns stall at activation. This feature closes that gap, and **it
asks nothing of your integration**: if your app already calls
`fireImpression`/`fireClick` at the right moments, agency measurement works the
day the campaign is configured.

#### What the SDK does — and never does

- It **does** fire each matching third-party URL automatically when you call
  `fireImpression(tracking)` or `fireClick(tracking, key: …)`. Your call sites do
  not change.
- It **never** fires anything on its own — no view-lifecycle hooks, no visibility
  detection. You still decide when an impression or click happened, exactly as
  before.
- It **never** lets a third-party tracker affect your app: dispatch is
  fire-and-forget on a separate, dedicated HTTP client, so a slow or dead agency
  server cannot delay rendering, the Admoai beacon, or the other trackers.

#### What arrives in the response

Under `X-Decision-Version: 2025-11-01`, a creative that carries trackers gains one
extra, read-only list. There are exactly three shapes:

```jsonc
"tracking": {
  "impressions": [...], "clicks": [...],            // canonical — unchanged
  "thirdPartyTrackers": [                            // absent when the campaign has none
    { "trackerId": "tpt_…", "eventType": "impression", "url": "https://…" },
    { "trackerId": "tpt_…", "eventType": "click", "matchType": "any", "url": "https://…" },
    { "trackerId": "tpt_…", "eventType": "click", "matchType": "specific",
      "eventKey": "cta_tap", "url": "https://…" }
  ]
}
```

You can read `creative.tracking.thirdPartyTrackers` (e.g. to display in a debug
screen), but you never fire these yourself — the helpers own dispatch.

#### When exactly a tracker fires — and why

| Your call | What fires alongside the canonical beacon |
|---|---|
| `fireImpression(tracking)` | every `eventType: "impression"` tracker |
| `fireClick(tracking, key: 'anyValidKey')` | every `matchType: "any"` click tracker |
| `fireClick(tracking, key: 'cta_tap')` | the above **plus** every `matchType: "specific"` tracker whose `eventKey == 'cta_tap'` |
| A key with **no canonical URL** | **nothing** — canonical or third-party |

The "specific" shape exists because an operator can tie a tracker to one named
click event (say, the CTA button) instead of every tap on the card — the agency
then counts CTA engagement, not card touches.

Worked example — same code you already have:

```dart
// Ad displayed:
sdk.fireImpression(creative.tracking);
// → 1 Admoai impression beacon + 1 GET per impression tracker

// User taps the CTA (a click event your template names "cta_tap"):
sdk.fireClick(creative.tracking, key: 'cta_tap');
// → 1 Admoai click beacon + every any-click tracker + the cta_tap-specific trackers
```

#### The guarantees behind the counts

Agencies reconcile their numbers against Admoai reporting, so dispatch is
deliberately strict:

- **One attempt per matching unique URL per invocation.** No retries, no queuing,
  no re-fire on app lifecycle. Calling `fireImpression` twice fires everything
  twice — by design, the SDK never second-guesses your event reporting.
- **Third-party can never out-count Admoai**: trackers fire only when the
  canonical beacon for that key fires.
- **The URL goes out byte-identical** to what the operator stored. A URL the
  platform cannot represent verbatim (e.g. a raw `%%MACRO%%` placeholder) is
  discarded rather than fired mutated — a corrupted URL would silently skew the
  agency's counts.
- **Credential isolation**: a plain GET on a dedicated client — no Admoai or SDK
  identity headers, no cookies, redirects never followed. The agency sees an
  anonymous hit, never your users' or Admoai's identity.
- **Privacy**: tracker URLs never appear in SDK logs (outcomes log the
  `trackerId` only).

#### What can you configure? Nothing — by design

There is no opt-in, no opt-out, and no per-tracker setting on the SDK side. Which
trackers exist, on which events, is entirely a campaign-configuration decision
made in the Ad Manager by the people trafficking the campaign — the SDK is a
faithful dispatcher. Older SDK versions simply ignore the field, so upgrading is
the only integration step that exists.

#### "Why didn't my tracker fire?"

1. **Wrong API version** — the field is only served under
   `X-Decision-Version: 2025-11-01`.
2. **The key had no canonical URL** — an unknown key is a safe no-op for
   everything.
3. **A `specific` tracker on a different key** — it only fires when the reported
   key equals its `eventKey`.
4. **The URL is not a plain, final HTTPS URL** — macro placeholders and malformed
   URLs are discarded (check the campaign configuration).
5. **VAST-delivered video** — the engine never serves third-party trackers with
   VAST creatives; the player owns those beacons.

---

## Journey Ads

A **Journey Ad** is a single-advertiser takeover spanning several screens
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

`2025-11-01` is not only about Journey Ads. It gates several capabilities, so
unless you have a specific reason not to, set it: **Journey Ads**, **video ads**,
**POI / destination targeting**, **mid-flight campaign changes**, **Open
Measurement** support, and the **format filter**.

<!-- MIRRORED SECTION START — this Journey Ads guide is duplicated in admoai-ios, admoai-android
     (sdk/README.md) and admoai-flutter. Prose must stay equivalent in all three; only the code
     samples differ. Change all three together. -->

### Why your integration matters commercially

A Journey Ad is **one advertiser buying one user's activity as a single deal**, usually
priced **CPT** (cost per trip) — the advertiser pays once for the whole journey, not
per impression. In exchange, competing ads are suppressed on the placements the journey
owns.

That moves real commercial weight into your app:

| If your app… | Consequence |
|---|---|
| Sends a different `sessionId` per screen | The journey restarts at stage 1 forever. The advertiser's multi-screen story never happens and the campaign under-delivers. |
| Never fires the completion beacon (on `custom_event` deals) | The journey never completes, so **CPT revenue is never recorded**. |
| Fills a journey-owned slot with a different advertiser's ad when the journey returns no ad | Breaks the single-brand exclusivity the advertiser paid for. |
| Uses journey metadata (stage keys, node ids) to drive app logic or layout | Breaks silently the moment someone edits the campaign. |

**None of this raises an error at request time.** Requests succeed, ads appear, and the
problem only shows up later in reporting — which is why the checklist and the checks
at the end of this section matter more than usual.

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

### What a session actually is

The most common mistake is reaching for something identity-shaped — a login, a user id,
an app launch. **A session is one activity, not one user and not one app run.** Define it
as the thing that starts and finishes in your product, because that is the unit the
advertiser is buying.

Examples, **not prescriptions** — pick the equivalent in your own product:

| Product | One `sessionId` = | Starts | Ends |
|---|---|---|---|
| Ride-hailing | one ride | user opens the booking flow | ride completed or cancelled |
| Delivery | one order | checkout begins | order delivered |
| Micromobility | one trip | unlock | lock / trip ends |

Two consequences worth internalising:

- **Login is usually the wrong boundary.** A user who takes three rides today should
  produce three `sessionId` values, not one — otherwise all three collapse into a single
  journey.
- **Concurrent activities need separate ids.** If your product allows two live orders at
  once, give each its own `sessionId` (a per-request override is the simplest way). One
  id for both makes them share one journey and one stage pointer.

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

> **The exception to "omitted is permissive".** Once a session has explicitly opted
> out, that refusal is remembered. Later requests that simply **omit** `journeyOpt`
> do **not** re-enable journeys for it — the session must re-consent with an explicit
> `JourneyOpt.optIn`. So a consent toggle that sends `optOut` when off and *nothing*
> when on will leave journeys permanently disabled for that session.

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

The two are mutually exclusive per deal. Which one applies is **configured per campaign
in the Ad Manager** by Admoai ad-ops — the engine reads that configuration and applies
it in the ad response; it does not decide it. Both are **additive** to the normal
impression rather than a replacement, so always fire the impression as usual.

**`custom_event` — you must fire it, and it is what bills.**

`creative.tracking.completions` is populated. The completion is recorded **only**
when you fire the beacon. If you never fire it, the advertiser is never charged for
the completion.

> **Do not hard-code the completion key.** The key is **campaign-specific** — it is the
> event name the Admoai ad operator configured for this deal, so it differs between
> campaigns and is not a fixed string you can rely on. Read it from
> `creative.tracking.completions`, which carries exactly one entry when the deal uses
> `custom_event`. Passing a key that is not in that list logs a warning and fires
> **nothing** — no error, no completion, no revenue.

```dart
// Read the key the engine returned; never invent it locally.
final completions = creative.tracking.completions;
if (completions != null && completions.isNotEmpty) {
  sdk.fireCompletion(creative.tracking, key: completions.first.key);
}
```

Fire it **once**, when the action you agreed with the advertiser actually happens —
not on render. Which app action that is, is a commercial decision the SDK cannot tell
you; get it from your Admoai contact before you ship (see
[Before you ship](#before-you-ship)).

Completion is **idempotent server-side**, so firing twice will not double-charge the
advertiser — but still fire once: repeated callbacks add confusing analytics rows and
make debugging harder.

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
- **Do not immediately retry the same placement in a loop.** Collapse the slot and
  carry on; request again when your app naturally reaches its next ad opportunity. A
  later request may well serve — the answer depends on placement, stage, time and
  campaign state. See [Why a journey can stop serving](#why-a-journey-can-stop-serving).

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
| A new `sessionId` per screen or per request | The journey restarts at stage 1 forever and never progresses | One id per activity, rotated only when the activity ends |
| Reusing a user id, account id or login as the `sessionId` | Every activity by that user collapses into a single journey | Mint an opaque id per activity |
| No `sessionId` at all | Journeys never activate; the feature is silently off (ordinary ads still serve) | Set it once via `AdMoai.initialize(sessionId: …)` |
| Omitting `journeyOpt` to mean "no journeys" | Permissive — journeys still serve, and an active one continues | Send `JourneyOpt.optOut` explicitly |
| Expecting opt-out to pause a journey | The instance is **closed**; a later opt-in starts a brand-new one | Treat opt-out as terminal |
| Sending `JourneyOpt.optOut`, then omitting `journeyOpt` to re-enable | A stored opt-out persists, so journeys stay off for that session | Send `JourneyOpt.optIn` explicitly to re-consent |
| Missing or older `apiVersion` | Journey fields are ignored silently, and completions do not record | Set `2025-11-01` |
| Not firing the `custom_event` completion beacon | The journey never completes and CPT never bills | Fire it once when the agreed action happens |
| Hard-coding the completion key | The key is campaign-specific; a wrong key fires **nothing** and only logs a warning | Read it from `creative.tracking``.completions` |
| Firing a completion on a `final_stage` deal | Nothing to fire; the call is a no-op | Check `isJourneyCompletion` and fire only the impression |
| Firing the completion on render instead of on the action | Completions and CPT revenue are reported for journeys that never delivered the outcome | Fire on the real user action |
| Filling a journey-owned slot with another ad when the journey returns no ad | Breaks the single-brand takeover the advertiser paid for | Collapse the slot |
| Immediately re-requesting the same placement in a loop after a no-ad | Wasted calls; a placement the journey is holding will not free up mid-loop | Collapse, then request again at your next natural ad opportunity |
| Treating a repeated `journeyStageKey` as a bug | One stage can own several surfaces, so it legitimately repeats | Use `journeyStageNodeId` for the no-repeat rule |
| Using journey metadata to drive app logic or layout | Breaks silently the moment someone edits the campaign | Render from `contents` / `template` |
| Rebuilding or appending to a tracking URL | Invalidates the encrypted token; attribution is lost | Fire the string verbatim |
| Firing SDK video events for VAST delivery | Every event counts twice | Let the player's VAST beacons do it |

### Verifying your integration

Two checks catch most integration bugs.

1. **The instance id must stay constant across a session.** Log it on every serve:

   ```dart
   debugPrint('journey instance: ${creative.journeyInstanceId}');
   ```

   If it changes mid-session, your `sessionId` is changing (or the session's
   server-side state expired).

2. **The stage NODE id must never repeat within one instance.**

   ```dart
   debugPrint('stage: ${creative.journeyStageKey}  node: ${creative.journeyStageNodeId}');
   ```

   `journeyStageNodeId` must **never repeat** while the same `journeyInstanceId` is
   active — each node serves at most once per journey. `journeyStageKey` **may**
   repeat, and that is not a bug: one stage can own several surfaces, and the engine
   will serve another unserved node from a stage it already served without advancing.
   The real red flag is `pre_ride` on every screen **with a changing instance id** —
   that means each request is starting a new journey.

### How long a journey stays alive

A journey's server-side progress has an **idle expiry**, configured by the Admoai ad
operator **per journey definition** — not per campaign, and not by your app. It defaults
to **24 hours** and can be set to anything from minutes to days.

Two things follow, and the second surprises people:

- **The clock runs from the last activity, not from the start.** Every serve refreshes it,
  so an active journey does not expire mid-use.
- **After the idle window the journey is gone — even if your `sessionId` never changed.**
  The next request starts a **new** journey at stage 1 with a new `journeyInstanceId`. An
  unchanged `sessionId` is not enough to keep a journey alive.

Pick the window to match how long your activity realistically pauses. *As an example
only:* a delivery product whose orders complete within a couple of hours has no reason to
keep state for a day. Agree the value with your Admoai contact — there is no universally
correct number.

### Why a journey can stop serving

**Frequency capping** decides whether a **new** journey may start. It is set per deal by
Admoai ad-ops, as "X times per Y period". There is **no default — if it is not configured,
no cap applies.** Two properties matter to you:

- It **never interrupts a journey already in progress.** A cap filling up mid-journey
  cannot cut the user off.
- It is scoped per **user + deal**, so it only applies when you send a **user id**.
  Without one, journey frequency capping cannot apply.

**Edge cases — uncommon, but they explain a journey that stops mid-session.** An active
journey can end early if the deal's **budget** runs out, its **pacing** limit is reached,
an **event cap** is hit, or it falls outside its **parting** window (the times of day and
days of week the campaign is allowed to serve). Add the idle expiry above, a **mandatory
stage** with nothing servable on the requested placement, and an explicit **opt-out**, and
you have the full list.

Your app's response is identical in every case: collapse the slot and carry on. The
distinction only matters when someone asks ad-ops why delivery stopped.

### How your integration shows up in reporting

Journey reporting is computed from the events your app fires and the session boundaries
you chose, so these numbers are only as good as the integration. What a publisher and an
advertiser will be looking at:

| Metric | What it is | What your app affects |
|---|---|---|
| **Journeys started** | How many journeys began | Your session boundaries. A `sessionId` per screen inflates this; one per login collapses many activities into one. |
| **Completions** | Journeys that reached the finish | Firing the completion beacon on `custom_event` deals. Ad-ops chooses which stages must be served for a journey to count as finished — any combination — and that is reconciled against billing. |
| **Avg duration** | Average time between a journey's first and last event | Whether the journey actually progresses. A restarting journey reports many short ones instead of one real one. |
| **Avg attention time** | Estimated time the ad was on screen: average duration × an attention percentage set on the **journey definition** | Same as duration. This is **estimated from configuration, not measured viewability** — it is not Open Measurement and never affects billing. |
| **CTR** | Clicks ÷ impressions, counted per event | Firing impressions and clicks. |
| **Journey CTR** | Journeys clicked at least once ÷ journeys started | Each journey counts **once** however many times it was clicked, and completion is irrelevant. It reads **higher** than CTR because a journey spans several placements — that is expected, not a bug. |

### Before you ship

**Get these from your Admoai contact.** Guessing any of them produces an integration that
looks fine and reports wrongly:

| What | Why you need it |
|---|---|
| Placement keys owned by the journey | Which of your surfaces participate |
| The billable app action | Which real user action fires completion |
| Completion mode (`custom_event` or `final_stage`) | Whether you fire anything at all |
| Idle expiry for the definition | How long a paused activity survives |
| Video delivery mode (JSON or VAST) | Who owns the video beacons |
| Whether a user id is expected | Frequency capping needs one |

**Then check your own integration:**

- [ ] `apiVersion: '2025-11-01'` is set.
- [ ] One `sessionId` per **activity** (see [What a session actually is](#what-a-session-actually-is)), not per screen and not per login.
- [ ] `journeyInstanceId` is constant across one activity; `journeyStageNodeId` never repeats.
- [ ] Completion key is read from `creative.tracking.completions`, never hard-coded.
- [ ] Completion fires **once**, on the agreed action — not on render.
- [ ] Normal impression still fires on journey serves.
- [ ] A journey no-ad collapses the slot; no substitute ad, no retry loop.
- [ ] Consent toggle sends an explicit `JourneyOpt.optIn` to re-enable, not an omitted field.
- [ ] Nothing fires automatically; VAST beacons left to the player.
- [ ] UI renders from `contents` / `template`, never from journey metadata.

### Glossary

For product and ops readers.

| Term | Meaning |
|---|---|
| **Journey** | One advertiser's multi-screen experience across a single user activity. |
| **Journey definition** | The reusable template: ordered stages, and the idle-expiry setting. |
| **Journey deal** | A campaign bought against a definition: pricing, budget, caps, flight dates. |
| **Instance** (`journeyInstanceId`) | One concrete run of a deal for one session. The unit reporting and billing reconcile on. |
| **Stage** | One ordered step of a journey. May own several surfaces. |
| **Stage node** | One placement + template within a stage. Serves at most once per instance. |
| **Takeover protection** | Suppression of competing ads on placements a journey owns. |
| **CPT** | Cost per trip — the advertiser pays once per journey, not per impression. |
| **Completion** | The moment the journey is considered fulfilled; what CPT bills on. |
| **Parting** | The times of day / days of week a campaign may serve. |
| **Pacing** | Spreading delivery over the flight instead of spending at once. |

### Questions publishers ask

**We do not implement `sessionId` at all. Can we still request ads?**
Yes. Everything works exactly as before — only Journey Ads are ineligible. Journeys never
activate, ordinary ads keep serving. It is a valid, safe default.

**Is `apiVersion` only about Journey Ads?**
No. `2025-11-01` also gates video ads, the format filter, mid-flight campaign changes and
Open Measurement support. Journey Ads are one of several reasons to set it — set it unless
you have a specific reason not to.

**Two users share a device. Same `sessionId`?**
No. A session is one activity by one user. On account switch, rotate it.

**The app was killed mid-activity. Reuse the id or rotate?**
Reuse it if the activity is still the same one — that is the whole point of it being yours
to persist. Rotate only when the activity itself ends.

**Our `sessionId` never changed, but the journey restarted at stage 1. Why?**
Almost certainly the idle expiry — see
[How long a journey stays alive](#how-long-a-journey-stays-alive).

**How do we tell the completion beacon apart from our own template custom events?**
They are separate lists. Your template's events are in `tracking.custom` and unchanged.
The journey completion beacon is the single entry in `tracking.completions`, fired with
`fireCompletion`.

**We fired the completion twice. Did we double-charge the advertiser?**
No — completion is idempotent server-side. Still fire once; duplicates only clutter
analytics.

**We never fire it. What happens?**
On a `custom_event` deal the journey never completes and **CPT revenue is never recorded**.
Nothing errors. This is the most expensive mistake on this page.

**The user opted out, then we stopped sending `journeyOpt`. Why no journeys?**
A stored opt-out is remembered and an omitted field does not clear it. Send an explicit
`JourneyOpt.optIn`.

**A journey stopped serving mid-session and we never opted out.**
See [Why a journey can stop serving](#why-a-journey-can-stop-serving).

<!-- MIRRORED SECTION END -->

---

## Sponsored Pin Locations

An advertiser buys a **format**, not a template: a Sponsored Pin Location campaign promotes real
places — their shops, branches, pickup points — as pins on your map.

Those places are **Advertiser Locations**: an inventory the advertiser maintains in the Ad
Manager, each with a name, coordinates, an optional address and an optional destination URL. They
group them into **Location Sets** ("all airport counters", "stores open past 10pm") and attach a
selection to a campaign as its **Distance Targeting**.

Two halves make it work, and they belong to different people:

- the **advertiser** says *which places* — their Locations, in the Ad Manager;
- **you** say *where to look and how far* — the distance search, on the request.

That is why the Ad Manager has no radius or bounds control anywhere. The campaign cannot know
where your user is looking; only your request does.

### Why your integration matters commercially

A Sponsored Pin campaign is bought on the promise that a real person saw a real shop near them.
Three parts of that promise live in your code and nowhere else:

- **Whether a pin is on screen.** We cannot see your map. If you report a view for every pin you
  drew, the advertiser pays attention to numbers that describe nothing.
- **Which pin the user chose.** Attribution is per location, so "someone clicked" is worth far
  less than "someone clicked *Providencia*".
- **Whether an action was a look or a decision.** A tap that opens a card is free. A click that
  opens the shop is billable. Confusing them bills the advertiser for curiosity.

Get those three right and the campaign reports honestly. Get them wrong and the numbers are
confidently false, which is worse than missing.

### What the SDK does, and never does

| The SDK does | The SDK never does |
|---|---|
| Send your distance search and validate it before the network call | Render a map, a pin, a cluster or a card |
| Give you typed, tolerant access to the places that came back | Decide whether a pin is visible |
| Fire the beacon you ask it to, exactly once per call | Fire anything because a response was parsed |
| Resolve nothing about the destination — the server already did | Re-derive a pin's click URL from the creative |

**Rendering is yours.** Deliberately: you know your map, your clustering, your sheets and your
scroll position, and we do not. The whole measurement contract rests on that honesty.

### Before anything else: the API version

```dart
final sdk = await AdMoai.initialize(
  config: SDKConfig(
    baseUrl: 'https://api.admoai.com',
    apiVersion: '2025-11-01',   // REQUIRED — see below
  ),
);
```

**Without `apiVersion` set to `2025-11-01`, no pins come back at all.** The decision API is
versioned by header; a request that omits it falls back to the older default, which has no concept
of Matched Points. The response is a perfectly ordinary, perfectly empty-of-pins ad — no error, no
warning. If `matchedPoints` is always empty, check this first.

### Asking for pins

Dart has no method overloading, so the two shapes are two named constructors — `Distance.radius` and `Distance.bounds` — passed to one `setDistanceTargeting`. The effect is the same one iOS and Android get from overloads: a call naming both a radius and a rectangle, or neither, cannot be written.

**A radius**, when you have a point and a sensible distance — a user's location, a searched
address:

```dart
final request = (sdk.createRequestBuilder()..addPlacement(key: 'map'))
    .setDistanceTargeting(Distance.radius(
      latitude: viewer.latitude,
      longitude: viewer.longitude,
      radiusMeters: 8000,        // metres
    ))
    .build();
```

**Bounds**, when the user is looking at a region — the natural call for a map that pans and
zooms, because it matches what is actually on screen:

```dart
final visible = await mapController.getVisibleRegion();
final centre = await mapController.getLatLng(const ScreenCoordinate(x: 0, y: 0));

final request = (sdk.createRequestBuilder()..addPlacement(key: 'map'))
    .setDistanceTargeting(Distance.bounds(
      latitude: centre.latitude,
      longitude: centre.longitude,
      bounds: DistanceBounds(
        north: visible.northeast.latitude, south: visible.southwest.latitude,
        east: visible.northeast.longitude, west: visible.southwest.longitude,
      ),
    ))
    .build();
```

The origin stays required for a bounds search. "Nearest first" needs somewhere to measure from,
and the centre of the viewport is not necessarily where the user is.

**`limit`** is optional and **narrows** the campaign's own cap — it can never widen it. The
advertiser sets a maximum (20 by default); your limit asks for no more than N of those. Omit it to
take as many as the campaign allows:

```dart
Distance.radius(latitude: lat, longitude: lng, radiusMeters: 5000, limit: 10)
```

`clearDistanceTargeting()` removes the search and leaves every other targeting axis alone.

**A Sponsored Pin campaign does not serve without a distance search — at all.** Not "serves with
no pins": the response carries no ad. A publisher who asked no spatial question has no map, and
rendering the creative with an empty pin list would bill for something nobody can act on, so the
campaign is dropped from the auction. The practical consequence: only request the Sponsored Pin
placement from a surface that can send a search. Asking for it from a screen with no map looks
exactly like a fill problem and is not one.

### What the SDK checks, and what the server decides

Checked locally, before any network call, because they are mistakes no round trip should be spent
on — each throws `ArgumentError`:

- latitude in [-90, 90], longitude in [-180, 180];
- a radius greater than zero;
- bounds with north above south and west below east (a rectangle crossing the antimeridian is
  refused in this version);
- a limit greater than zero.

**Not** checked locally, on purpose:

- **The radius and diagonal ceilings** (50 km and 100 km today). They are server policy. An SDK
  that hard-codes them ships a client that refuses what a newer engine would accept, and every
  publisher would need an app release to benefit from a raised limit. The server's error is the
  authority.
- **Whether any pins will match.** That is the question the request exists to ask.

### `distance` is not `setLocationTargeting`

The one thing every integrator asks. They look alike on the wire and are completely different
questions:

| | what it answers | what it affects |
|---|---|---|
| `setLocationTargeting` | where is the **viewer**? | whether a campaign is eligible to serve at all |
| `distance` | where am **I looking**, and how far? | which of an eligible campaign's places come back |

They compose, and neither implies the other. A Sponsored Pin request often sends both: one says
the user is in Santiago, the other says show me what is within 8 km of this corner.

### Reading the pins

```dart
final response = await sdk.requestAds(request);

for (final decision in response.body.data ?? const <Decision>[]) {
  final creative = decision.creatives?.firstOrNull;
  if (creative == null) continue;

  for (final point in creative.matchedPoints) {
    markers.add(Marker(
      markerId: MarkerId(point.id),
      position: LatLng(point.latitude, point.longitude),
      infoWindow: InfoWindow(title: point.name, snippet: point.address), // may be null
    ));
  }
}
```

| field | type | notes |
|---|---|---|
| `id` | String | the Advertiser Location's public id — the unit of attribution |
| `name` | String | the shop's name, as the advertiser maintains it |
| `address` | String? | null when the location has none |
| `latitude`, `longitude` | Double | where to draw it |
| `distance` | Int | **metres** from the point you searched around |
| `clickUrl` | String? | where this pin goes — already resolved, see below |
| `tracking` | object? | this point's own beacons |

Points come back **nearest first**. They hang off the creative, so with several winning ads each
creative keeps its own — there is no flat list to confuse.

A creative that is not a Sponsored Pin creative returns an empty list, never an error. Code that
does not know about pins keeps working unchanged: the points ride inside `contents` as one more
entry, and every version of this SDK has tolerated entries it does not recognise.

The marker image is not on the points. `pinImage` is a content key of the creative, and you read it
like any other key: `creative.contents.getContent('pinImage')?.value`. Every pin of that creative
uses the same image.

### The click URL is already decided

`point.clickUrl` is the answer. The server has already applied the precedence — the location's own
URL, unless the campaign deliberately overrides every pin with the creative's default.

**Do not fall back to the creative's URL when it is null.** This is the single most likely place
for a well-meaning integration to go wrong, because the creative also has a URL and it is right
there. A pin with no destination is a pin you render and do not make tappable-through. Falling
back silently defeats a campaign that points each shop at its own page, and the bug surfaces
months later as "our clicks all go to the homepage".

### The three events, and what each one costs

| call | fires when | cost |
|---|---|---|
| `fireImpression(creative.tracking)` | the creative is on screen — **once**, however many pins it shows | the campaign's **CPM** |
| `trackPointView(point)` | that specific pin became visible to the user | free |
| `trackPointTap(point)` | the user tapped that marker | free |
| `trackPointClick(point)` | the user activated that pin's destination | the campaign's **CPC** |

Three consequences worth stating plainly:

1. **A screenful of pins is one impression.** Five pins is one impression and five views. Pin views
   are in addition to the impression, never summed into it.
2. **A tap is not a click.** Opening your detail card is a tap and nothing more.
3. **`trackPointClick` replaces `fireClick` for that action.** Never both — both would count and
   charge the same click twice.

Nothing in the SDK encodes a price. The cost rides inside the signed token the server minted, so
a pricing change never needs an app release.

### Worked example 1 — a map screen, end to end

Ask, render, then report only what was genuinely seen:

```dart
class SponsoredPinMap extends StatefulWidget {
  @override
  State<SponsoredPinMap> createState() => _SponsoredPinMapState();
}

class _SponsoredPinMapState extends State<SponsoredPinMap> {
  final Map<String, MatchedPoint> _pins = {};   // marker id -> point
  Creative? _creative;
  bool _reportedImpression = false;

  // 1. ASK. One request per meaningful map move, not per frame.
  Future<void> _loadPins(LatLng centre) async {
    final request = (sdk.createRequestBuilder()..addPlacement(key: 'map'))
        .setDistanceTargeting(Distance.radius(
          latitude: centre.latitude, longitude: centre.longitude, radiusMeters: 8000,
        ))
        .build();

    final response = await sdk.requestAds(request);
    final creative = response.body.data?.firstOrNull?.creatives?.firstOrNull;
    if (creative == null) {
      setState(_clearPins);     // no ad: show no sponsored pins at all
      return;
    }

    setState(() {
      _creative = creative;
      _reportedImpression = false;

      // 2. RENDER. Entirely your code — the SDK draws nothing.
      _clearPins();
      for (final point in creative.matchedPoints) {
        _pins[point.id] = point;
        _markers.add(_markerFor(point));
      }
    });
  }

  // 3. REPORT what the user actually saw, never what you merely drew.
  Future<void> _onCameraIdle() async {
    final creative = _creative;
    if (creative == null) return;

    // The creative's own impression: ONCE per served creative, however many pins it shows.
    if (!_reportedImpression) {
      sdk.fireImpression(creative.tracking);
      _reportedImpression = true;
    }

    // One view per pin that is genuinely on screen. Pins already reported for this
    // response send nothing, so there is no "already seen" set to keep.
    final bounds = await _controller.getVisibleRegion();
    final nowVisible = _pins.values.where((p) => _within(bounds, p)).toList();

    sdk.trackPointViews(nowVisible);
  }
}
```

The three numbered comments are the whole contract. Note what is missing: nothing fires when the
response arrives, and nothing fires when a marker is added.

### Worked example 2 — a detail card, and the one expensive mistake

```dart
// The user taps a marker and your detail sheet slides up.
void _onMarkerTapped(MatchedPoint point) {
  sdk.trackPointTap(point);       // FREE. The sheet opening is not a click.
  showModalBottomSheet(context: context, builder: (_) => _DetailSheet(point: point));
}

// The user taps "Order now" inside that sheet.
Future<void> _onDetailCtaPressed(MatchedPoint point) async {
  sdk.trackPointClick(point);     // BILLABLE at the campaign's CPC.

  // Do NOT also call sdk.fireClick(...) — that would charge the click twice.
  final url = point.clickUrl;
  if (url != null) await launchUrlString(url);
}
```

If your marker navigates straight to the destination with no card in between, that is a
`trackPointClick` — and a `trackPointTap` beside it if you want the interaction counted, which
remains free.

### Reporting a screenful at once

A map that draws twenty pins reports twenty views. The bulk call saves you the loop:

```dart
sdk.trackPointViews(nowVisiblePoints);
```

Call it on every render with whatever is on screen. **Each pin is reported once per decision
response**: re-rendering the same response — a zoom, a pan, a cluster expanding — sends nothing for
pins already reported, and only the newly visible ones fire. A new response returning the same
location is a new view and is reported again. `trackPointView` follows the same rule. The SDK
remembers the last 500 view URLs (ten full responses); a view that failed to send is not retried.
Taps and clicks are never de-duplicated: two taps are two taps.

There is deliberately no bulk tap and no bulk click. Each of those is one user gesture, so a
plural form could only report something that did not happen.

### Journey Ads

Identical. A Journey screen whose creative is a Sponsored Pin creative exposes `matchedPoints` the
same way and takes the same three calls. A returned Matched Point is not a Journey stage
impression — the stage's own impression event is, exactly as for every other screen type.

### Common mistakes

| Mistake | Consequence | Do this instead |
|---|---|---|
| No `apiVersion`, or an older one | No pins ever come back; the response looks like an ordinary ad | Set `2025-11-01` |
| Reporting a view when the response arrives | Views for pins nobody saw; the advertiser's numbers describe nothing | Report from your map's visibility signal |
| Reporting a view when a marker is added | Same, including pins inside a collapsed cluster or off screen | Check the pin is genuinely on screen |
| Re-reporting a view on every camera idle | One render inflates to dozens of views | Keep a per-render set of already-reported ids |
| `trackPointClick` when a card opens | The advertiser is charged CPC for someone who only looked | `trackPointTap` for the card, `trackPointClick` for the destination |
| `trackPointClick` **and** `fireClick` for one action | The click is counted and charged twice | Fire only `trackPointClick` |
| Firing the creative impression once per pin | A five-pin render bills five impressions instead of one | Fire it once per served creative |
| Falling back to the creative's URL when `clickUrl` is null | Silently defeats per-location destinations | Treat null as "this pin has no destination" |
| Re-deriving or rebuilding a tracking URL | Invalidates the signed token; the event is lost | Fire it verbatim |
| Hard-coding 50 km or 100 km in your app | You refuse searches a newer server would accept | Let the server answer |
| Sending a new request on every camera frame | Hammers the API and churns pins under the user | One request per settled map move |
| Treating an empty `matchedPoints` as an error | Normal: no campaign matched that search | Render no sponsored pins |
| Requesting the placement without a distance search | **No ad at all**, which reads as a fill problem | Only request it where you can send a search |
| Using `distance` to decide whether the user is in a region | Wrong tool; it does not gate eligibility | Use `setLocationTargeting` |

### Two self-checks that catch most integration bugs

**1. Your view count should exceed your impression count, and never equal it by accident.**

```dart
// Self-check 1 — print what you are about to report.
debugPrint('impression: 1, views: ${nowVisible.length}, '
    'pins drawn: ${creative.matchedPoints.length}');
```

One served creative showing five visible pins should print one impression and five views. If
impressions and views are always equal, you are reporting one view per creative rather than per
pin. If views equal the number of pins *drawn* rather than *seen*, your visibility check is not
doing anything.

**2. Open a card, close it, and check nothing was charged.**

Tap a marker, let the card open, close it without touching the CTA. Exactly one `pin_tap` should
have been reported and zero clicks. If a click appears, `trackPointClick` is wired to the card
instead of the destination — the one mistake in this API that costs the advertiser money.

### How your integration shows up in reporting

The advertiser sees, per location: pin views, pin taps, clicks, and the rates between them. A
location they attached but that never matched shows a row of zeros with a dash for its rates —
deliberately, because "never seen" and "seen and ignored" are different facts and only one of them
is a reason to drop a shop.

A location the campaign later stops targeting keeps its history and is labelled as no longer
targeted. Dropping a shop does not erase what it earned.

### Before you ship

- `apiVersion` is `2025-11-01`.
- Your distance search is sent on the placement the campaign is booked against.
- Pins render from `matchedPoints`, and the screen renders nothing sponsored when it is empty.
- A view is reported from real visibility, once per pin per render.
- The creative impression is fired once per served creative.
- Tap and click are wired to different gestures, and the click is not doubled with `fireClick`.
- `clickUrl` is used verbatim, and a null one is handled.
- A no-ad response leaves no sponsored pins on the map.

### Glossary

| term | meaning |
|---|---|
| **Advertiser Location** | One real place in the advertiser's inventory. The unit of attribution. |
| **Location Set** | A named group of Advertiser Locations, attached to campaigns as a unit. |
| **Distance Targeting** | The campaign's attached selection of Locations and Sets. Set by the advertiser, not by you. |
| **Matched Point** | One Advertiser Location that answered *your* distance search, with its distance and beacons. |
| **Max matched points** | The campaign's own cap on how many points it will return. Your `limit` narrows it. |
| **pin view** | One Advertiser Location seen by the user inside one served creative. Free. |
| **pin tap** | The user tapped that marker. Free. |
| **click** | The user activated the destination. Billable, attributed to that location. |

### Questions publishers ask

**Do I have to use a map?** No. Pins are places with coordinates, a name and a distance; a sorted
list of nearby shops is a perfectly good rendering. The measurement rules do not change — a row
the user scrolled past is a view, a row they never reached is not.

**How often should I request?** When the map settles, not while it moves. Each request is a fresh
decision; churning them changes the pins under the user and spends quota for nothing.

**What if the user denies location permission?** Send the centre of whatever region you are
showing. The search is about where you are looking, not where the user is — only `setLocationTargeting`
carries that claim.

**Can I filter or re-sort the points?** Render fewer if you must, and report views only for the
ones you actually showed. Do not re-sort by your own idea of relevance and call the result
"nearest"; `distance` is there if you want to show it.

**Why is `matchedPoints` empty when I can see the campaign is live?** In order of likelihood:
`apiVersion` is not `2025-11-01`; the search is centred somewhere the advertiser has no locations;
the radius is too small; or the placement you asked for is not the one the campaign is booked
against.

**And why did I get no ad at all?** If you sent no distance search, that is the expected answer
rather than a fill problem — see above. Otherwise it is an ordinary no-fill: no campaign was
eligible for that placement.

**Does any of this fan out third-party trackers?** No. Third-party trackers stay at the creative
level and are not duplicated per pin.

## Lead Generation

> **Experimental.** The Lead Generation API (`enableInteractiveExperiences`,
> `createLeadFormController`, `LeadFormController`, `LeadFormView`, `LeadFormHost`) may change in a
> minor release. Nothing changes for an app that does not opt in.

A Lead Generation ad is a **native creative that your app renders**. When the viewer taps it, a
hosted form opens inside an SDK-owned secure web view. The form handles its own stages, validation,
submission and confirmation. Your app never sees what the viewer typed and never implements a
JavaScript bridge: you draw the creative, fire the creative's impression and click, and place the
form view where you want it.

### What you need

- **`apiVersion: "2025-11-01"` in `SDKConfig`**, as in [Quick Start](#1-initialize-the-sdk). Without
  it the engine does not serve Lead Generation, and the SDK logs a warning when you opt in without
  one.
- **Android**: the SDK adds `androidx.webkit` and advertises Lead Generation support **only when the
  device's WebView supports it**, so you are never served an ad the device cannot open.
- **iOS 14 or later.** Below that the SDK does not advertise support.
- **`url_launcher`** (or any way to open a browser) in your own `pubspec.yaml`: the form asks your
  app to open the privacy policy and the advertiser's website. It is your dependency, not the SDK's.

### 1. Opt in, with or without prefill

The SDK declares support to the engine only after your app calls `enableInteractiveExperiences` with
a `LeadFormValueProvider`. The provider answers one question: which of the viewer's details could
your app fill in for the form?

```dart
import 'package:admoai/admoai.dart';

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
    config: SDKConfig(baseUrl: 'https://your-decision-engine.example.com',
        apiVersion: '2025-11-01'),
  );
  sdk.enableInteractiveExperiences(RiderPrefillProvider(currentRider));
  // Or: sdk.enableInteractiveExperiences(NoPrefillProvider());
  return sdk;
}
```

How the two directions work, and what the SDK guarantees:

- **Keys only in the request.** The decision request carries the list of keys from `availableKeys`
  (for example `fullName`, `email`, `phone`), never a value. An empty set is valid: you are saying
  "I host the form, I cannot prefill".
- **Values only after the viewer taps.** `lookUpValues` is called only after the viewer opened a
  form and it activated, and only with the standard keys that form asked for. Answer from what the app
  already holds in memory; do not call a server.
- **The timeout.** If your answer takes longer than the lookup time (1.5 seconds today, set by the
  shared contract), throws, or arrives after the form was disposed, the SDK ignores it and the form
  opens empty. The viewer is never blocked.
- **Invalid values are dropped.** Blank values, values over the length bound and a `gender` outside
  the form's options are left out; the form validates everything else. The SDK never logs a value and
  does not keep it after handing it to the form.
- `disableInteractiveExperiences()` withdraws the opt-in. Passing a different provider to
  `enableInteractiveExperiences` replaces the first and closes the forms opened with it.

### 2. Request ads and find the Lead Generation creative

Request ads as you always do. A creative with a form carries `creative.interactiveExperience`:

| Value | Meaning |
|---|---|
| `LeadGenerationExperience` | A Lead Generation form. It exposes `formId`, `formInstanceId`, `preparedVersionId`, `prefillAttributeKeys` and `expiresAt`. |
| `UnsupportedInteractiveExperience` | An interactive experience this SDK does not understand, or a malformed one. **Do not show it as tappable.** Render it as an ordinary ad or skip it. |
| `null` | An ordinary creative. |

```dart
import 'package:admoai/admoai.dart';

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
```

### 3. Render the creative and fire the impression

The creative is yours to draw, from `creative.contents`, like any native format. Fire the impression
the way you do today, when the ad is on screen: `sdk.fireImpression(creative.tracking)`. The
examples below do it after the first frame.

### 4. Create the controller and prepare it early

`sdk.createLeadFormController(creative, presentation:, host:)` returns a `LeadFormController`. It
returns **`null`** when the app has not opted in, the device cannot host the form, or the creative has
no usable form: in every case, **do not offer the form** and render the creative as an ordinary ad.

Call `prepare()` as soon as the ad is shown. It loads the form hidden, so the tap that follows opens
it quickly. Create **one controller per served creative**.

`FormPresentation.inline` is for a form that sits inside your own card; `FormPresentation.fullScreen`
is for a form that fills a screen (a route). Tell the controller which one you use, because it
changes who draws the close button.

### 5. On tap: fire the click, `open()`, show `LeadFormView`

The SDK **never fires the creative's click for you**. On the tap, call
`sdk.fireClick(creative.tracking)` once, then `controller.open()`, then put
`LeadFormView(controller: controller)` on screen.

`LeadFormView` shows the native view the controller owns; a rebuild never recreates it or loses what
the viewer typed. Keyboard, insets and scrolling are **yours**: give the view a height inline, and put
it in a `Scaffold` full screen so the keyboard resizes it.

- **Full screen**: the form shows its **own close button**. It asks your app to close through
  `LeadFormHost.onRequestClose`.
- **Inline**: the form draws no close button. Closing is your card's job (collapse it, then dispose).

**Inline, inside the card**

```dart
import 'dart:async';

import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
```

**Full screen, as a route**

```dart
import 'dart:async';

import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
```

### 6. Tell the form when it is really on screen

Call `controller.setVisible(true)` when the form is **actually visible** to the viewer and
`setVisible(false)` when it stops being (a collapsed card, a route covered by another, the app in the
background). One **Form Open** is counted, on real visibility: if you never call `setVisible(true)`,
the form can be ready but nothing is counted, and the form stays hidden. Repeating the same value does
nothing.

### 7. The host: close and external links

`LeadFormHost` is the form's way of asking your app for what it cannot do itself:

- **`onRequestClose(controller)`**: the form asks to be closed (the close button full screen, or the
  end of the flow). Remove the view (pop the route, collapse the card) and dispose the controller.
- **`onOpenExternalLink(controller, purpose, url)`**: open `url` in a **separate browser surface**
  (for example `launchUrl(url, mode: LaunchMode.externalApplication)` from `url_launcher`), never
  inside the form, and without adding a token, a form value or an identifier to it. The `purpose` is
  `ExternalLinkPurpose.privacyPolicy`, available any time the form is visible, or
  `ExternalLinkPurpose.websiteCta`, the advertiser's website, which **only arrives after a
  submission**.

### 8. Observe the state

`controller.state` is a `ValueListenable<LeadFormState>`. The state is a sealed class, so a `switch`
tells you when you missed one:

```dart
import 'dart:async';

import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';

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
```

| State | What it means for you |
|---|---|
| `LeadFormIdle`, `LeadFormPreparing`, `LeadFormPrepared` | Loading in the background, or waiting for the tap. Nothing to show. |
| `LeadFormActivating` | The viewer tapped; the form is activating and prefill is applied. |
| `LeadFormReadyToShow` | Show the form, then call `setVisible(true)`. |
| `LeadFormVisible`, `LeadFormSubmitting` | The viewer is filling or submitting. |
| `LeadFormSubmitted` | The lead was accepted (`leadId`, `submittedAt`). The website link can now arrive. |
| `LeadFormFailed` | `retryable` true: offer `retry()`. False: stop offering the form on this ad. |
| `LeadFormExpired` | The preparation expired. The controller never opens: request a new ad. |
| `LeadFormDisposed` | Released. Every call is ignored. |

### 9. Dispose

- Dispose the controller when its owner UI goes away (`controller.dispose()` in your `State.dispose`).
  It is safe to call twice.
- `sdk.disposeAllLeadForms()` disposes every form the SDK handed out. Call it on sign-out or account
  switch if you do not use `setUserConfig`.
- Forms also close by themselves when `setUserConfig` is called with **another user id**, on
  `disableInteractiveExperiences()` and when `enableInteractiveExperiences` is given a different
  provider, so one person's form never outlives them. At most 2 forms stay loaded and hidden at once:
  a further `prepare()` stays idle, and `open()` loads it anyway.

```dart
import 'package:admoai/admoai.dart';

void signOut(AdMoai sdk) {
  sdk.disposeAllLeadForms();
  sdk.setUserConfig(id: 'another_user'); // a different id also disposes forms
}
```

### What the SDK does for you, and what stays yours

| The SDK does | You do |
|---|---|
| Declares support to the engine only when the device can host the form | Call `enableInteractiveExperiences` and send `apiVersion: "2025-11-01"` |
| Runs the form in a locked-down web view and speaks to it; no JavaScript bridge in your app | Render the native creative and fire its impression |
| Handles stages, validation, submit and confirmation inside the form | Fire the creative click once on tap, then `open()` |
| Asks you for values only after the tap, and drops invalid ones | Answer `lookUpValues` from memory, quickly |
| Fires the form's own events (form open, form start, website click), once each | Call `setVisible(true/false)` when the form is really on screen |
| Never logs the preparation token or any value | Open the privacy policy and website in a separate browser |
| Disposes forms on user change, disable or a new provider | Dispose the controller when its UI goes away; keyboard, insets and scrolling |

### Troubleshooting

**I get no Lead Generation ads.** In order of likelihood: you did not call
`enableInteractiveExperiences`; `apiVersion` is not `2025-11-01`; the device cannot host the form
(Android WebView without support, iOS below 14), in which case the SDK does not advertise support;
or Lead Generation is not yet turned on for your organization (ask your Admoai contact). It is an ordinary no-fill otherwise.

**The form is ready but never becomes visible.** `setVisible(true)` was not called, or was called
before the view was on screen. Call it from the frame after `LeadFormView` is attached.

**The form opens empty.** Prefill is optional. Check that your provider's `availableKeys` is not empty,
that `lookUpValues` answers within 1.5 seconds and does not throw, and that the values are not blank,
too long, or a `gender` the form does not offer. The SDK never logs values, so check on your side.

**`createLeadFormController` returned `null`.** The app has not opted in, the device cannot host the
form, or the creative is not a `LeadGenerationExperience`. Render it as an ordinary ad.

## Admoai standard formats

Admoai defines six standard ad formats. Each has a fixed set of content keys and a fixed set of
tracking events. The decision response tells your app what to show; your app draws it and reports
what the user did. **The SDK draws none of them**: it decodes the response and gives you the
tracking helpers.

| Format | Format key | What it is | Section |
|---|---|---|---|
| Native Display | `card` | One image with optional text and one destination. | [Native Display](#native-display) |
| Carousel | `carousel` | Two to ten slides, each with its own destination. | [Carousel](#carousel) |
| Tap-to-expand | `expandable_banner` | A small teaser that expands into a larger view. | [Tap-to-expand](#tap-to-expand) |
| Branded Assets | `branded_assets` | A transparent branded image, for example a vehicle marker on a map. | [Branded Assets](#branded-assets) |
| Standard Video | `standard_video` | A video with a poster image and playback tracking. | [Standard Video](#standard-video) |
| Sponsored Pin Locations | `sponsored_pin_location` | An advertiser's real places, shown as pins on your map. | [Sponsored Pin Locations](#sponsored-pin-locations) |

An operator can also create a template **based on** a standard and add fields of their own. See
[Templates based on a standard](#templates-based-on-a-standard).

### What you need

- **SDK 0.7.0 or newer.** Older versions decode the response but do not expose the format metadata
  or the Carousel slides, and have no slide, expand, close or asset-tap helpers.
- **`apiVersion: "2025-11-01"` in `SDKConfig`**, as in [Quick Start](#1-initialize-the-sdk). The SDK
  sends the version header only when `apiVersion` is set. Without it the engine answers with its
  default version: it skips standard-format campaigns (warning `10025`, so the placement returns no
  ad from them) and serves a template based on a standard without its format metadata.
- **`url_launcher`** (and `video_player` for Standard Video) in your own `pubspec.yaml`: the SDK
  opens nothing and plays nothing.

### Detecting the format

Every creative served as a standard format has these fields on `creative.metadata` (`Metadata`).
All are nullable.

| Property | Meaning |
|---|---|
| `effectiveStandardFormatKey` | The standard the creative follows: one of the format keys above. |
| `effectiveStandardFormatVersion` | The version of that standard, a whole number starting at 1. A published version never changes. |
| `templateSource` | `admoai_standard` (the standard itself) or `based_on_standard` (an operator's template built on it). |
| `assetContext` | Branded Assets only: what the asset is for, today `vehicle_marker`. |

Choose the renderer from the format key, and always have a default case:

```dart
Widget? adFor(Creative creative) {
  switch (creative.metadata?.effectiveStandardFormatKey) {
    case 'card':                   return NativeDisplayAd(creative: creative, sdk: sdk);
    case 'carousel':               return renderCarousel(creative);
    case 'expandable_banner':      return TapToExpandAd(creative: creative, sdk: sdk);
    case 'branded_assets':         return renderBrandedAsset(creative);
    case 'standard_video':         return StandardVideoAd(creative: creative, sdk: sdk);
    case 'sponsored_pin_location': return renderPins(creative);
    default:                       return renderExistingWay(creative); // absent, or a value this app does not know
  }
}
```

The fields are `null` on ads that do not use a standard format, so your existing rendering does not
change. For a template based on a standard, the key and version are the standard's, not the
operator's template's: a derived Carousel still reports `carousel`. In the default case do not
crash and do not throw; if your app cannot render the creative, show nothing for the slot and fire
no event. Do not branch on `templateSource` or the version to hide an ad.

### Optional content: absent means not set

Some content keys are optional. When an operator leaves one empty, Admoai leaves it out of the
response: it never sends an empty string, an empty image or a placeholder. So a missing key is
normal and never an error. Hide the widget for it; do not show a blank label, an empty image or a
default text, and lay the ad out so it looks right without each optional key.

The examples in the format sections use this helper. It returns a string value, or `null` when the
key is absent, empty or not a string:

```dart
import 'package:admoai/admoai.dart';

extension ContentText on List<Content> {
  String? text(String key) {
    final value = getContent(key)?.value;
    return value is String && value.isNotEmpty ? value : null;
  }
}

extension CreativeResponse on Creative {
  /// Changes with every decision response: the signed impression URL is new each time.
  String get responseId => tracking.impressions?.firstOrNull?.url ?? '';
}
```

`responseId` is how the widgets notice that a parent has swapped in a new ad at the same position
(Flutter then reuses the `State` and does not call `initState` again): `didUpdateWidget` resets
their own state when it changes.

### Who does what

| Admoai | Your app |
|---|---|
| Decides which ad is served and which format it uses. | Draws the format. |
| Sends the content for each key, and only the keys that have a value. | Treats a missing key as "not set". |
| Signs every tracking URL and removes duplicate events on the server. | Calls the tracking helper at the right moment, and passes it the object it received. |
| | Opens the destination when the user taps, and fires the click only when it opened. |

Never build or edit a tracking URL. Fire impressions from your own visibility callback, only when
the ad is really on screen.

### Tolerant-reader rules

1. **Ignore unknown fields.** Admoai adds fields over time without a new API version.
2. **Strings with a fixed set of values are open sets**: format keys, template sources, content types, styles and tracking keys. A value you do not know must not crash your app.
3. **A `switch` over a server string needs a `default`.**
4. **Absent is not an error.**
5. **Find a content entry by its `key`, never by its index.** The exception is Carousel slides, which you render in the order sent.
6. **One bad entry is not a bad ad.** The SDK drops a malformed entry and keeps the rest; do the same in your own parsing.

### Tracking at a glance

| Format | Fire | Never fire |
|---|---|---|
| Native Display | `fireImpression`, `fireClick` | |
| Carousel | `fireImpression`, `trackSlideView`, `trackSlideClick` | `fireClick` |
| Tap-to-expand | `fireImpression`, `fireExpand`, `fireClose`, `fireClick` | `fireClick` on expand |
| Branded Assets | `fireImpression`, `fireAssetTap`, `fireClick` | `fireClick` for a tap that opens nothing |
| Standard Video | `fireImpression`, `fireVideoEvent`, `fireClick` | a skip event, `fireClick` without a destination |
| Sponsored Pin Locations | see [Sponsored Pin Locations](#sponsored-pin-locations) | |

The SDK never fires anything on its own.

## Native Display

Native Display is one image with optional text and one destination. The format key is `card`.
It needs `apiVersion: "2025-11-01"`.

### Content keys

| Key | Type | Required |
|---|---|---|
| `image` | image | Yes |
| `destination_url` | url | Yes |
| `brand_logo` | image | No |
| `headline` | text | No |
| `supporting_text` | text | No |
| `cta_text` | text | No |

The simplest valid ad is an image and a destination. Hide any optional element whose key is absent.

`creative.template?.style` is `compact`, `default` or `tall`; each response carries exactly one.
An operator can allow several styles on one ad and each decision picks one, so support all three.
`style` is nullable: fall back to `default`.

### Tracking

| Event | When | Call |
|---|---|---|
| Impression | The ad is on screen. | `sdk.fireImpression(creative.tracking)` |
| Click | The user taps and the destination opens. | `sdk.fireClick(creative.tracking)` |

Native Display has one click, with the key `default`; `fireClick` uses it when you pass no key.

The examples fire the impression after the first frame in which the ad has what it needs to
render, which is the minimum visibility signal: it does not know whether the ad is in the
viewport. In a scrolling list use your own rule (for example a visibility package) and call the
same method from it.

```dart
import 'package:admoai/admoai.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class NativeDisplayAd extends StatefulWidget {
  const NativeDisplayAd({super.key, required this.creative, required this.sdk});
  final Creative creative;
  final AdMoai sdk;

  @override
  State<NativeDisplayAd> createState() => _NativeDisplayAdState();
}

class _NativeDisplayAdState extends State<NativeDisplayAd> {
  String? _impressionFor;

  @override
  void initState() {
    super.initState();
    _scheduleImpression();
  }

  @override
  void didUpdateWidget(NativeDisplayAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creative.responseId != widget.creative.responseId) {
      _scheduleImpression();                                 // a new ad in the same widget
    }
  }

  // Your visibility callback: replace the post-frame callback with your own rule.
  void _scheduleImpression() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final creative = widget.creative;
      final c = creative.contents;
      if (!mounted || c.text('image') == null || c.text('destination_url') == null) return;
      if (_impressionFor == creative.responseId) return;     // once for each served ad
      _impressionFor = creative.responseId;
      widget.sdk.fireImpression(creative.tracking);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.creative.contents;
    final image = c.text('image');
    final destination = c.text('destination_url');
    if (image == null || destination == null) return const SizedBox.shrink();
    final height = switch (widget.creative.template?.style) {
      'compact' => 120.0,
      'tall' => 360.0,
      _ => 220.0,
    };
    final logo = c.text('brand_logo');                       // hide when null
    final headline = c.text('headline');
    final body = c.text('supporting_text');
    final cta = c.text('cta_text');

    return GestureDetector(
      onTap: () async {
        final creative = widget.creative, sdk = widget.sdk;  // this ad, even if the parent swaps it
        if (await launchUrl(Uri.parse(destination))) {       // only when it opened
          sdk.fireClick(creative.tracking);
        }
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.network(image, height: height, width: double.infinity, fit: BoxFit.cover),
        if (logo != null) Image.network(logo, height: 24),
        if (headline != null) Text(headline),
        if (body != null) Text(body),
        if (cta != null) Text(cta),
      ]),
    );
  }
}
```

## Carousel

A Carousel is one ad with two to ten slides. Each slide has its own image, its own destination
and its own tracking. It needs `apiVersion: "2025-11-01"`; without it, standard-format ads are
skipped.

The examples below use the `text` helper from
[Optional content: absent means not set](#optional-content-absent-means-not-set).

### Reading the slides

`creative.slides` is the list of slides **in the order to render them**. That is the server's
order. Do not sort it by `position`: `position` is the slide's number for your information only.
The list is empty for any creative that is not a Carousel.

| Slide field | Type | Notes |
|---|---|---|
| `slideId` | String | Stable across requests and scrolling. Use it as the key of your list item. |
| `position` | int | The slide's number, starting at 1. Informational. |
| `contents` | `List<Content>` | `image` and `destination_url` always; `headline`, `supporting_text` and `cta_text` when the advertiser set them. |
| `tracking` | `SlideTracking?` | This slide's own view and click. A slide without tracking still renders. |

`brand_logo` and `disclaimer` are on the creative, not on the slides: show them once for the
whole Carousel, and hide them when absent. Fields an operator adds to a template based on
Carousel are on the creative too.

### Tracking a Carousel

| Event | When | Call |
|---|---|---|
| Impression | The Carousel is on screen. | `sdk.fireImpression(creative.tracking)` |
| Slide view | A slide is at least 50% visible for one continuous second. | `sdk.trackSlideView(slide)` |
| Slide click | The user taps a slide and its destination opens. | `sdk.trackSlideClick(slide, creative)` |

- **Your app decides when a slide was viewed.** The SDK never fires a slide view on its own:
  returning a slide is not showing it. If the slide drops below 50% before the second ends,
  start counting again the next time it is visible.
- **A slide view is sent once per decision response.** Scrolling back or redrawing sends
  nothing more; a new response has new signed URLs and counts again. `trackSlideViews(slides)`
  does the same for a list.
- **`trackSlideClick` sends the slide's view first** if it was not sent yet, then the slide's
  click, then the creative's third-party click trackers once. The view goes once per response;
  the click goes on every call, so a tap that came before the view rule was met still records
  the view. AdMoai counts one view and one click per slide for each served ad.
- **Never call `fireClick` for a Carousel.** A Carousel has no creative-level click, so it sends
  nothing.
- Pass the `Slide` you rendered, never the creative and never an index.

```dart
void renderCarousel(Creative creative) {
  for (final slide in creative.slides) {                  // server order
    addItem(id: slide.slideId,                            // identity = slideId
        image: slide.contents.text('image'),
        headline: slide.contents.text('headline'));
  }
}

// From your visibility callback, once the Carousel is on screen.
void carouselBecameVisible(Creative creative) {
  sdk.fireImpression(creative.tracking);
}

// When your visibility check passes: 50% visible for one continuous second.
void slideWasViewed(Slide slide) {
  sdk.trackSlideView(slide);
}

Future<void> slideTapped(Slide slide, Creative creative) async {
  final url = slide.contents.text('destination_url');
  if (url == null) return;
  if (await launchUrl(Uri.parse(url))) {                  // url_launcher package
    sdk.trackSlideClick(slide, creative);                 // not fireClick
  }
}
```

The visibility check depends on your list widget: use what it tells you about how much of an
item is visible, with a timer you cancel when the slide drops below 50%.

## Tap-to-expand

Tap-to-expand is a small teaser that the user can open into a larger view. The format key is
`expandable_banner`, the template style is `expandable`, and it needs `apiVersion: "2025-11-01"`.

### Content keys

| Key | Type | Required |
|---|---|---|
| `teaser_image` | image | Yes |
| `expanded_image` | image | Yes |
| `destination_url` | url | Yes |
| `teaser_headline` | text | No |
| `headline` | text | No |
| `supporting_text` | text | No |
| `cta_text` | text | No |
| `disclaimer` | text | No |

`teaser_image` and `teaser_headline` belong to the compact state. `expanded_image`, `headline`,
`supporting_text`, `cta_text` and `disclaimer` belong to the expanded state. Both states arrive in
the same creative.

### How to render it

1. Show the teaser in the compact state, with `teaser_image` and `teaser_headline` when present.
2. When the user taps the teaser, expand to the larger view with the expanded keys.
3. Give the user a way to close the expanded view.
4. Open `destination_url` only when the user taps the call to action or the expanded content, never
   when they expand.

You choose how the expansion looks and animates.

### Tracking

| Event | When | Call |
|---|---|---|
| Impression | The teaser is on screen. | `sdk.fireImpression(creative.tracking)` |
| Expand | The ad actually expanded. | `sdk.fireExpand(creative.tracking)` |
| Close | The expanded view actually closed. | `sdk.fireClose(creative.tracking)` |
| Click | The user taps through and the destination opens. | `sdk.fireClick(creative.tracking)` |

**Expanding is not a click.** `fireExpand` and `fireClose` are custom events (`expand`, `close`).
They send no click and are never billed as one. Only `fireClick` records a click, and only when the
destination opens. Call `fireExpand` and `fireClose` when the state has really changed, not when a
gesture starts that may be cancelled. Admoai counts at most one expand and one close for each
served ad, so a second call does no harm.

```dart
import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TapToExpandAd extends StatefulWidget {
  const TapToExpandAd({
    super.key,
    required this.creative,
    required this.sdk,
    this.expandedExtra,                                      // room for fields an operator adds
  });
  final Creative creative;
  final AdMoai sdk;
  final List<Widget>? expandedExtra;

  @override
  State<TapToExpandAd> createState() => _TapToExpandAdState();
}

class _TapToExpandAdState extends State<TapToExpandAd> {
  bool _expanded = false;
  String? _impressionFor;

  @override
  void initState() {
    super.initState();
    _scheduleImpression();
  }

  @override
  void didUpdateWidget(TapToExpandAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creative.responseId != widget.creative.responseId) {
      _expanded = false;                                     // never inherit the last ad's state
      _scheduleImpression();
    }
  }

  // Your visibility callback: replace the post-frame callback with your own rule.
  void _scheduleImpression() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final creative = widget.creative;
      final c = creative.contents;
      if (!mounted ||
          c.text('teaser_image') == null ||
          c.text('expanded_image') == null ||
          c.text('destination_url') == null) {
        return;
      }
      if (_impressionFor == creative.responseId) return;     // once for each served ad
      _impressionFor = creative.responseId;
      widget.sdk.fireImpression(creative.tracking);
    });
  }

  // Opens the destination; the click is recorded for the ad that was opened.
  Future<void> _open(String destination) async {
    final creative = widget.creative, sdk = widget.sdk;
    if (await launchUrl(Uri.parse(destination))) {           // only when it opened
      sdk.fireClick(creative.tracking);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.creative.contents;
    final teaser = c.text('teaser_image');
    final expandedImage = c.text('expanded_image');
    final destination = c.text('destination_url');
    if (teaser == null || expandedImage == null || destination == null) {
      return const SizedBox.shrink();
    }

    if (!_expanded) {
      final title = c.text('teaser_headline');
      return GestureDetector(
        onTap: () {
          setState(() => _expanded = true);
          widget.sdk.fireExpand(widget.creative.tracking);   // the view is now expanded
        },
        child: Column(children: [
          Image.network(teaser, height: 100, width: double.infinity, fit: BoxFit.cover),
          if (title != null) Text(title),
        ]),
      );
    }

    final headline = c.text('headline');
    final body = c.text('supporting_text');
    final cta = c.text('cta_text');
    final disclaimer = c.text('disclaimer');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // The expanded content opens the destination, so it works without cta_text.
      GestureDetector(
        onTap: () => _open(destination),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Image.network(expandedImage, width: double.infinity, fit: BoxFit.contain),
          if (headline != null) Text(headline),
          if (body != null) Text(body),
          ...?widget.expandedExtra,
        ]),
      ),
      if (cta != null)
        ElevatedButton(onPressed: () => _open(destination), child: Text(cta)),
      if (disclaimer != null) Text(disclaimer),
      TextButton(
        onPressed: () {
          setState(() => _expanded = false);
          widget.sdk.fireClose(widget.creative.tracking);    // the view is now closed
        },
        child: const Text('Close'),
      ),
    ]);
  }
}
```

Fire the impression when the teaser is first on screen, not while you build the widget. The
expanded content opens the destination too, so an ad without `cta_text` can still be opened.

## Branded Assets

Branded Assets is a transparent branded image that your app places in its own interface. The
first use is a vehicle marker on a map. It needs `apiVersion: "2025-11-01"`.

### Reading the asset

`creative.metadata?.assetContext` says what the asset is for: `vehicle_marker`. Treat an
unknown value as an asset you do not place.

The contents are read with the same lookup as any other key (the `text` helper is in
[Admoai standard formats](#optional-content-absent-means-not-set)):

| Key | Type | Required | Use |
|---|---|---|---|
| `branded_image` | image | Yes | Draw it where your interface needs the asset. It has transparency. |
| `accessible_label` | text | No | The image's accessibility label, when present. |
| `destination_url` | url | No | Where the asset leads, if anywhere. |

When `destination_url` is absent, the asset can be tapped but goes nowhere: do not show a button
that opens nothing.

### Tracking Branded Assets

| Event | When | Call |
|---|---|---|
| Impression | The asset is on screen. | `sdk.fireImpression(creative.tracking)` |
| Asset tap | The user tapped the asset. | `sdk.fireAssetTap(creative.tracking)` |
| Click | The user opens the destination. | `sdk.fireClick(creative.tracking)` |

**An asset tap is not a click.** `fireAssetTap` is a custom event; it sends no click and is
never billed as one. AdMoai counts at most one asset tap per served ad. When a tap opens the
destination straight away, call `fireAssetTap` and then `fireClick`. When a tap only shows your
own detail view, call `fireClick` later, only if the user opens the destination. Without a
destination there is no click tracker, and `fireClick` sends nothing.

```dart
void placeAsset(Creative creative) {
  if (creative.metadata?.assetContext != 'vehicle_marker') return;
  addVehicleMarker(
    image: creative.contents.text('branded_image'),
    semanticLabel: creative.contents.text('accessible_label'),
  );
}

// The user tapped the asset.
void onAssetTapped(Creative creative) {
  sdk.fireAssetTap(creative.tracking);                    // not a click
  showAssetDetail(creative);                              // what your interface does for a tap
}

// The user chose to open the destination, for example from the detail view.
Future<void> onDestinationChosen(Creative creative) async {
  final url = creative.contents.text('destination_url');
  if (url == null) return;                                // no destination, no click
  if (await launchUrl(Uri.parse(url))) {                  // url_launcher package
    sdk.fireClick(creative.tracking);
  }
}

// From your visibility callback, once the asset is on screen.
void assetBecameVisible(Creative creative) {
  sdk.fireImpression(creative.tracking);
}
```

## Standard Video

Standard Video is a video with a poster image and optional text. The format key is
`standard_video`, it has one style (`default`), and it needs `apiVersion: "2025-11-01"`. It is
delivered as JSON video, so everything in [Video Ad Support](#video-ad-support) and
[Video Tracking Events](#video-tracking-events) applies; this section lists only what the standard
adds. There is no VAST.

- `creative.metadata?.format` is `video` and `creative.delivery` is `json`. The file URL is in `video_asset`.
- The ad is never skippable: the response has no skippable setting and no skip offset. Add no skip control and fire no skip event.

| Key | Type | Required |
|---|---|---|
| `video_asset` | video | Yes |
| `poster_image` | image | Yes |
| `brand_logo` | image | No |
| `headline` | text | No |
| `supporting_text` | text | No |
| `cta_text` | text | No |
| `destination_url` | url | No |
| `disclaimer` | text | No |

`creative.metadata?.duration` and `aspectRatio` can also be present. Show `poster_image` first. If the
video cannot load or play, keep showing it instead of a black view, and fire only the events that
really happened.

| Event | When | Call |
|---|---|---|
| Impression | The ad is on screen, before playback starts. | `sdk.fireImpression(creative.tracking)` |
| `start`, `first_quartile`, `midpoint`, `third_quartile` | Playback reaches 0%, 25%, 50%, 75%. | `sdk.fireVideoEvent(creative.tracking, "<key>")` |
| `complete` | 98% played. | `sdk.fireVideoEvent(creative.tracking, "complete")` |
| Click | The user taps and the destination opens. | `sdk.fireClick(creative.tracking)` |

**No click without a destination.** When `destination_url` is absent the creative has no click
tracker: show no tappable call to action, and `fireClick` sends nothing. Admoai stores the events as
you send them and adds no `start` or quartile for you.

The example plays the file with the `video_player` package.

```dart
import 'package:admoai/admoai.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class StandardVideoAd extends StatefulWidget {
  const StandardVideoAd({super.key, required this.creative, required this.sdk});
  final Creative creative;
  final AdMoai sdk;

  @override
  State<StandardVideoAd> createState() => _StandardVideoAdState();
}

class _StandardVideoAdState extends State<StandardVideoAd> {
  VideoPlayerController? _player;
  var _fired = <String>{};
  String? _impressionFor;
  static const _steps = <String, double>{
    'start': 0.0, 'first_quartile': 0.25, 'midpoint': 0.5,
    'third_quartile': 0.75, 'complete': 0.98,
  };

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void didUpdateWidget(StandardVideoAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creative.responseId != widget.creative.responseId) {
      _end();                                                // drop the old ad's player and events
      _fired = <String>{};
      _begin();
    }
  }

  void _begin() {
    final creative = widget.creative, sdk = widget.sdk;      // this ad, even if the parent swaps it
    final video = creative.contents.text('video_asset');
    if (video == null || creative.contents.text('poster_image') == null) return;
    // Your visibility callback: replace the post-frame callback with your own rule.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.creative.responseId != creative.responseId) return;
      if (_impressionFor != creative.responseId) {
        _impressionFor = creative.responseId;                // once for each served ad
        sdk.fireImpression(creative.tracking);               // before playback
      }
      final player = VideoPlayerController.networkUrl(Uri.parse(video));
      _player = player;
      player.addListener(() => _onProgress(player, creative, sdk));
      try {
        await player.initialize();
        await player.play();
        if (mounted) setState(() {});
      } catch (_) {
        // Playback failed: the poster stays, and no playback event is sent.
      }
    });
  }

  void _end() {
    _player?.dispose();
    _player = null;
  }

  void _onProgress(VideoPlayerController player, Creative creative, AdMoai sdk) {
    if (player != _player) return;                           // an old ad's player
    final value = player.value;
    if (value.duration.inMilliseconds == 0) return;
    // Playback reached the end: the last update can arrive with isPlaying false, so check this
    // first. Every point before the end was played through, so report any that were missed.
    final progress = value.isCompleted
        ? 1.0
        : value.position.inMilliseconds / value.duration.inMilliseconds;
    if (!value.isCompleted && !value.isPlaying) return;      // paused: not playback
    _steps.forEach((key, threshold) {
      if (progress >= threshold && _fired.add(key)) {
        sdk.fireVideoEvent(creative.tracking, key);
      }
    });
  }

  @override
  void dispose() {
    _end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creative = widget.creative;
    final c = creative.contents;
    final poster = c.text('poster_image');
    if (poster == null || c.text('video_asset') == null) return const SizedBox.shrink();
    final destination = c.text('destination_url');           // null: no tap, no click
    final logo = c.text('brand_logo');                       // hide each optional element when null
    final headline = c.text('headline');
    final body = c.text('supporting_text');
    final cta = c.text('cta_text');
    final disclaimer = c.text('disclaimer');
    final player = _player;

    return GestureDetector(
      onTap: destination == null
          ? null
          : () async {
              final sdk = widget.sdk;                        // this ad, even if the parent swaps it
              if (await launchUrl(Uri.parse(destination))) {
                sdk.fireClick(creative.tracking);
              }
            },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          Image.network(poster, width: double.infinity, fit: BoxFit.contain),   // also the fallback
          if (player != null && player.value.isInitialized)
            AspectRatio(aspectRatio: player.value.aspectRatio, child: VideoPlayer(player)),
        ]),
        if (logo != null) Image.network(logo, height: 24),
        if (headline != null) Text(headline),
        if (body != null) Text(body),
        if (cta != null && destination != null) Text(cta),
        if (disclaimer != null) Text(disclaimer),
      ]),
    );
  }
}
```

## Templates based on a standard

An operator can create a template **based on** a standard and add fields of their own. The format
stays the standard's; the creative simply carries more keys. The response then has:

- every content key of the standard that is set, in the standard's order, and
- the operator's extra keys, after them.

The format key and version are the standard's, and `templateSource` is `based_on_standard`: a
derived Carousel reports `carousel`, a derived Tap-to-expand reports `expandable_banner`. The
standard's own keys and tracking events behave exactly as in its section above, and an extra key
never replaces a standard key. (`creative.template?.key` is the operator's template key, not the
standard's, so never choose a renderer from it.)

So your app should:

1. **Pick the renderer from `effectiveStandardFormatKey`**, as in [Detecting the format](#detecting-the-format), and render the standard part with that format's renderer.
2. **Read the extra keys by name** (`creative.contents.text('expanded_headline')`) and show the ones you know how to show. Extra keys use the same `key`, `type` and `value` shape as every other key; read `type` to decide how to show a value.
3. **Treat extra keys as optional**, unless your own template contract says otherwise.
4. **Ignore extra keys you do not know.** Do not fail, do not show an error and do not drop the ad.
5. **Leave custom tracking events alone** unless your app has a reason to fire one. Operators can add their own; fire one with `sdk.fireCustomEvent(creative.tracking, '<key>')` when the user does the matching action.

A template based on Sponsored Pin Locations works the same way: it reports `sponsored_pin_location`
and `creative.matchedPoints` carries the pins (see [Sponsored Pin Locations](#sponsored-pin-locations)), with the operator's extra keys in `creative.contents`.

### Worked example

An operator built the template `promo_expandable` on Tap-to-expand and added a text field
`expanded_headline` that should appear in the expanded view. The response contains the
Tap-to-expand keys that are set (the three required ones and any optional ones) followed by `expanded_headline`, with `effectiveStandardFormatKey` =
`expandable_banner` and `templateSource` = `based_on_standard`. `TapToExpandAd` is the widget from
[Tap-to-expand](#tap-to-expand); the extra key goes in its `expandedExtra` slot.

```dart
import 'package:admoai/admoai.dart';
import 'package:flutter/widgets.dart';

Widget adView(Creative creative, AdMoai sdk) {
  switch (creative.metadata?.effectiveStandardFormatKey) {
    case 'expandable_banner':
      // Standard part: the standard renderer. Extra part: read by name, shown only when set.
      final extra = creative.contents.text('expanded_headline');
      return TapToExpandAd(
        creative: creative,
        sdk: sdk,
        expandedExtra: [if (extra != null) Text(extra)],
      );
    default:
      return const SizedBox.shrink();                        // nothing to render: no widget, no event
  }
}
```

Because the format key is the standard's, the same case renders the plain standard Tap-to-expand
(no `expanded_headline`, so the extra widget is simply absent) and every operator template based
on it.

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

## Audience signals

Audience signals are eight standard attributes you already know about your user (age bracket,
subscription state, how many activities they completed, ...). The SDK sends them through `targeting.custom`, and
the engine matches them against Ads that were authored with **Standard presets** in the Ad
Manager. You compute the values; the SDK never derives or infers them.

> **Requires `apiVersion: '2025-11-01'`** in `SDKConfig` for the audience to be recorded as
> dimensions in reporting and tracking. On the default route the values are validated and matched,
> but they are **not** recorded as audience dimensions.
>
> **Requires Audience Signals enabled on your workspace.** A workspace without it refuses the
> request, so it gets no ad:
>
> - Standard keys or publisher segments: HTTP 422, code 10028, thrown as `ValidationError`.
> - Device `carrier` or `category`: HTTP 400, code 10009 ("The body contains an unknown field"),
>   thrown as `ClientError`. This includes values you set by hand with `setDeviceConfig`, which are
>   sent even without `collectDeviceSignals: true`.

| Wire key | Dart setter | Enum | Wire values |
|----------|-------------|------|-------------|
| `age_group` | `setAgeGroup` | `AgeGroup` | `under18` = `under_18`, `age18To24` = `18_24`, `age25To34` = `25_34`, `age35To44` = `35_44`, `age45To54` = `45_54`, `age55To64` = `55_64`, `age65Plus` = `65_plus` |
| `gender` | `setGender` | `Gender` | `female`, `male`, `other`, `preferNotToSay` = `prefer_not_to_say` |
| `account_type` | `setAccountType` | `AccountType` | `personal`, `business`, `family`, `student`, `other` |
| `subscription_status` | `setSubscriptionStatus` | `SubscriptionStatus` | `none`, `trial`, `active`, `paused`, `expired` |
| `account_tenure` | `setAccountTenure` | `AccountTenure` | `days0To30` = `0_30d`, `days31To90` = `31_90d`, `days91To365` = `91_365d`, `days366Plus` = `366d_plus` |
| `activity_frequency_30d` | `setActivityFrequency30d` | `ActivityFrequency30d` | `zero` = `"0"`, `times1To2` = `1_2`, `times3To9` = `3_9`, `times10Plus` = `10_plus` |
| `last_activity_recency` | `setLastActivityRecency` | `LastActivityRecency` | `never`, `days0To7` = `0_7d`, `days8To30` = `8_30d`, `days31To90` = `31_90d`, `days91Plus` = `91d_plus` |
| `publisher_segments` | `setPublisherSegments` | `List<String>` | your own segment codes (see below) |

```dart
final request = sdk
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
    .build();

final response = await sdk.requestAds(request);
// targeting.custom on the wire:
//   {"key": "age_group", "value": "25_34"}
//   {"key": "gender", "value": "female"}
//   {"key": "account_type", "value": "personal"}
//   {"key": "subscription_status", "value": "active"}
//   {"key": "account_tenure", "value": "31_90d"}
//   {"key": "activity_frequency_30d", "value": "0"}
//   {"key": "last_activity_recency", "value": "31_90d"}
//   {"key": "publisher_segments", "value": ["airport_commuter", "high_value"]}
```

Audience signals mix freely with your existing custom keys (`addCustomTargeting(key: 'category',
value: 'news')`). No aliases are translated: `25-34` is not `25_34`, and the engine rejects it.

### Rules

- **`"0"` is a string.** Every value is a string on the wire, including `ActivityFrequency30d.zero`.
- **The last setter wins per key.** Typed setters and `addCustomTargeting` share the same entry,
  so setting the same key twice leaves one value.
- **`null` removes a key**: `setAgeGroup(null)` drops `age_group`. A missing key means "no
  assertion"; the SDK never invents a value.
- **Unknown means not sent.** If you do not know a value, leave the setter unset or pass `null`.
  Never guess a bucket and never use a "none" value as a default for missing data.
- **Publisher segments have their own rules** (code format and length, the 20-code cap,
  duplicates, registration): see [Publisher segments](#publisher-segments).

### Publisher segments

Publisher segments are audiences you define and own (`airport_commuter`, `beach_goer`). You
register each code in the Ad Manager, then send the codes a user belongs to. An Ad targeting
segments is served when the request carries **any one** of its codes.

| Step | Call | On the wire |
|------|------|-------------|
| Set | `setPublisherSegments(['airport_commuter', 'beach_goer'])` | `{"key": "publisher_segments", "value": ["airport_commuter", "beach_goer"]}` |
| Clear | `setPublisherSegments(null)` or `setPublisherSegments([])` | no `publisher_segments` entry: the request asserts no segment |
| Reset | a new `createRequestBuilder()` | a fresh request with no segments; placements and the automatic `device` and `app` objects are as on any new request |

Segments live on the request builder, not on the SDK: each request sends exactly the codes
you set on it. Do not use the builder's `clearAll()` to drop segments: it also removes the
placements and turns off the `device` and `app` objects for that request.

- **A code matches `^[a-zA-Z0-9_]{1,32}$`: 1 to 32 letters, digits and underscores.** The SDK
  checks the character set only (`^[a-zA-Z0-9_]+$`): any other character throws `ArgumentError`
  and leaves the builder unchanged. The engine checks the length: the Ad Manager does not
  register a code longer than 32 characters, so the engine refuses one (422, code 10029).
- **Always an array**, even for a single code. Codes are sent as given: not trimmed, not
  case-folded.
- **At most 20 codes per request.** The engine refuses a longer list (422, code 10076) instead of
  truncating it, so the request gets no ad. Send the 20 most relevant codes.
- **Each code once.** `setPublisherSegments` drops duplicates for you. A raw
  `addCustomTargeting(key: 'publisher_segments', value: [...])` list is sent as given, and the
  engine refuses a repeated code (422, code 10073).
- **Register before you send.** An unregistered code is refused (422, code 10029). An archived
  code keeps matching.

### Request examples

One example per audience surface. Each matches a scenario every AdMoai SDK runs against a real
engine (`@admoai/sdk-scenarios` 3.1.0; the ids are in brackets).

**Standard attributes** (AS1): an Ad targeting `age_group` 25-34 is served.

```dart
final request = sdk
    .createRequestBuilder()
    .addPlacement(key: 'home')
    .setAgeGroup(AgeGroup.age25To34)
    .setActivityFrequency30d(ActivityFrequency30d.zero)
    .build();
// targeting.custom: [{"key": "age_group", "value": "25_34"},
//                    {"key": "activity_frequency_30d", "value": "0"}]
```

**Publisher segments** (AS9, AS10): an Ad targeting `airport_commuter` is served for either list.
`['beach_goer']` alone (AS11), or no segments (AS12), gets no ad.

```dart
final request = sdk
    .createRequestBuilder()
    .addPlacement(key: 'home')
    .setPublisherSegments(['airport_commuter', 'beach_goer'])
    .build();
// targeting.custom: [{"key": "publisher_segments", "value": ["airport_commuter", "beach_goer"]}]
```

**Device** (AS6, AS7, AS8): carrier and category never change which Ad is served. A tablet whose
carrier reads `wifi` (sent as no carrier) and a request with no device values are served the same way.

```dart
sdk.setDeviceConfig(carrier: 'Example Mobile', category: DeviceCategory.phone);
final request = sdk.createRequestBuilder().addPlacement(key: 'home').build();
// device: {..., "carrier": "Example Mobile", "category": "phone"}
```

### When the engine refuses a request

A refused request gets no ad. The typed setters prevent most of these. Code 10028 and the 422
codes below throw a `ValidationError`; code 10009 throws a `ClientError`. Both carry the engine's
entries in `errors`, each with a `code` and a `message`.

| Code | HTTP | Thrown as | Cause | Scenario |
|------|------|-----------|-------|----------|
| 10028 | 422 | `ValidationError` | Standard keys or publisher segments sent to a workspace without Audience Signals | |
| 10009 | 400 | `ClientError` | Device `carrier` or `category` sent to a workspace without Audience Signals ("The body contains an unknown field"), including values set by hand | |
| 10029 | 422 | `ValidationError` | A value outside the catalog (`25-34` instead of `25_34`), a malformed segment code (`airport-commuter`), or a segment code the workspace has not registered | AS5, AS18, AS14 |
| 10030 | 422 | `ValidationError` | A list for a single-value key (`age_group`), or a string for `publisher_segments` | AS15, AS16 |
| 10073 | 422 | `ValidationError` | The same segment code twice in a raw custom list | AS13 |
| 10076 | 422 | `ValidationError` | More than 20 segment codes | AS17 |

```dart
try {
  final response = await sdk.requestAds(request);
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
```

### What each value means

You compute the values from your own data; the SDK never derives them. In every row, if you do not
know the value, do not send the key.

| Key | Value | Meaning |
|-----|-------|---------|
| `age_group` | all | Age in completed years. `under18` means below 18. |
| `gender` | `preferNotToSay` | The user's recorded choice. Never a default for missing data. |
| `account_type` | `other` | A known account type outside the four named ones. |
| `subscription_status` | `none` | Known: no current or previous subscription. |
| `account_tenure` | all | Age of the user's account with you. Not the age of the app install or the SDK install. |
| `activity_frequency_30d` | all | Completed activities in the trailing 30 x 24 hours. An activity is one completed use of your service (a ride, a parking session, a ticket, a rental). A booking that was not used does not count. Cancelled, failed or only-booked activities do not count. |
| `activity_frequency_30d` | `zero` | Known: zero completed activities in the window. |
| `last_activity_recency` | all | Elapsed days since the last completed activity: completed 24-hour periods between UTC instants. |
| `last_activity_recency` | `never` | Known: no activity was ever completed. |

Choose the account context (the selected profile, the relevant subscription) yourself. If you
cannot pick one reliably, omit the field or use publisher segments. Register every segment code in
the Ad Manager before sending it.

## Device

By default the SDK collects a `device` object (id, model, manufacturer, OS, timezone, language).
Two coarse fields can be added. They are not targetable in V1: they are recorded for reporting,
and ads cannot target them yet.

| Field | Meaning |
|-------|---------|
| `carrier` | The registered mobile operator of the default data subscription. Never the Wi-Fi provider. |
| `category` | `DeviceCategory.phone`, `.tablet` or `.other` (a positively identified different class: TV, watch, automotive hardware, desktop). |

**Both are opt-in.** The default SDK never sends them. A workspace without audience signals
enabled rejects a request that carries them, so turn collection on only once your workspace has
audience signals. On a workspace without it, the engine answers HTTP 400, code 10009, and
`requestAds` throws a `ClientError` with `status == HTTPStatus.badRequest` and the entry in
`e.errors`. Values set by hand with `setDeviceConfig` are sent without the flag, so they get the
same answer:

```dart
final sdk = await AdMoai.initialize(
  config: SDKConfig(
    baseUrl: 'https://api.admoai.com',
    apiVersion: '2025-11-01',
    collectDeviceSignals: true, // read carrier and category from the device
  ),
);

// Or set them by hand (sent with or without collectDeviceSignals).
sdk.setDeviceConfig(carrier: 'Example Mobile', category: DeviceCategory.tablet);
```

What the request carries:

| Your app | `carrier` / `category` sent |
|----------|-----------------------------|
| Default SDK (`collectDeviceSignals` off), nothing set by hand | Absent. The request is exactly what it was before audience signals. |
| `collectDeviceSignals: true` | The values read from the device, through the SDK's platform channel to native Android and iOS code. A value the device cannot provide (a carrier on iOS, or on a device with no SIM) is absent. |
| `setDeviceConfig(carrier:, category:)` | Your value, with or without the flag. |
| After `sdk.clearDeviceConfig()` | Absent in requests built after the clear, until `await sdk.resetDeviceConfig()`, unless set again by hand with `setDeviceConfig`. A request built before the clear keeps the carrier and category it was built with. |

- Manual `setDeviceConfig(carrier:, category:)` values override the collected ones.
- Carriers are normalised: trimmed, and empty, `--`, `unknown`, `wifi` and `wi-fi`
  (case-insensitive) are treated as absent.
- `disableDeviceCollection()` on a builder omits the whole device object, manual values included.
- `sdk.clearDeviceConfig()` stops automatic collection; `await sdk.resetDeviceConfig()` resumes it.

| Platform | `carrier` | `category` |
|----------|-----------|------------|
| Android | Registered operator of the default data subscription. Android 7+ (API 24+), no new permission. | TV, watch, automotive or PC hardware, or a TV or watch UI mode, is `other`; a phone or tablet docked in car or desk mode keeps its class. Otherwise the smallest width of the full display decides: under 600 dp is `phone`, 600 dp or more is `tablet`. It is the device, not the app window, so rotation and split-screen do not change it. If the display cannot be read, `category` is absent. |
| iOS | Never sent: Apple returns static placeholder values since iOS 16.4. | From the device idiom. An iPhone-only app running on an iPad reports `phone`; Mac, Catalyst and Vision report `other`. |
| Other hosts | Absent | Absent |

The values are read at initialization and on `resetDeviceConfig()`, and refreshed by `requestAds`
within 300 ms, falling back to the last value read. `getHttpRequest` uses the value available when
it builds the request.

The SDK is now a Flutter plugin with native code for Android and iOS. It needs no new permissions
and raises no minimum versions.

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

### Running the host app

The package is a plugin with native code, so there is no tracked example app (#85). Generate a
throwaway host app, not tracked, in `build/host_app`:

```bash
tool/host_app.sh [dir]      # default: build/host_app; an existing dir is recreated
cd build/host_app
flutter run --dart-define=ADMOAI_BASE_URL=<your decision engine URL>
```

Without the define, the app uses `http://10.0.2.2:8080`, the Android emulator's loopback to the
host machine.

Before pushing, run what CI runs:

```bash
tool/format.sh                      # dart format (CI: tool/format.sh --check)
flutter analyze --fatal-infos       # infos fail CI too
flutter test --exclude-tags "live || e2e"
```

## When the API check fails

`api/admoai.api.txt` is the package's public API, one symbol per line with its signature,
and CI (`Public API check`) fails when the code no longer matches it. That is deliberate: a
removed or changed public symbol breaks every integrator's build on their next
`flutter pub upgrade`, so the change has to appear as a diff in the PR.

1. Run `tool/api.sh` (needs `dart pub global activate dart_apitool 0.23.2`) and commit
   `api/admoai.api.txt`.
2. Read the diff; the CI log and job summary also classify each change. Only `+` lines (new
   API) is a minor bump. Any `-` or changed line (removed, renamed, a signature change) is
   **breaking**: the version in `pubspec.yaml` needs a major bump (a minor one while `0.x`),
   and the PR says what integrators must change.
3. If the surface changed by accident (a helper that should not be exported), fix the export
   instead of updating the baseline.

## Example App

The example app was removed on 2026-10-21: it had fallen behind the SDK's features. This README
is the reference integration, and [`example/example.md`](example/example.md) (pub.dev's
*Example* tab) shows the smallest complete one. The app's last version is kept under the git tag
`sample-app-archive`; to bring it back:

```bash
git fetch origin tag sample-app-archive
git checkout sample-app-archive -- example
```

## Documentation

For detailed documentation, please visit our [documentation site](https://docs.admoai.com).

## Support

- **Issues**: [GitHub Issues](https://github.com/admoai/admoai-flutter/issues)
- **Email**: support@admoai.com

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ by the AdMoai Team**
