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
- **Journey Ads** - Multi-stage, single-brand trip journeys via `sessionId` / `journeyOpt` and read-only `creative.journey` metadata (requires `apiVersion: "2025-11-01"`)
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
| `apiVersion` | String? | `null` | Engine API version. `"2025-11-01"` gates Journey Ads, video ads, POI / destination targeting, mid-flight campaign changes, Open Measurement and the `format` placement filter |
| `defaultLanguage` | String? | `null` | Sent as `Accept-Language` on every request |
| `requestTimeout` | Duration | 10s | Per-request timeout |
| `connectTimeout` | Duration | 10s | Connection timeout (default HTTP client only) |
| `receiveTimeout` | Duration | 10s | Idle timeout (default HTTP client only) |
| `logger` | Logger | SDK default | Custom logger instance |

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
