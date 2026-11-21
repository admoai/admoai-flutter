## Unreleased

### Added

- E2E runner: scenarios schemaVersion 7 — `request.interactiveExperience` sent through the opt-in.
- **Experimental: Lead Generation opt-in, keys-only availability and
  interactive experience decode.** `AdMoai.enableInteractiveExperiences(provider)`
  declares that the app hosts the Lead Generation form and
  `disableInteractiveExperiences()` withdraws it. The `LeadFormValueProvider`
  lists the `StandardAttributeKey`s the app could fill (keys only; the value
  lookup is added when forms can open). The request carries an
  `InteractiveExperienceCapability` (`supported`, `availableAttributeKeys`) only
  when the app enabled it. This version never advertises support because the
  form surface is not in it yet, so enabling has no effect on requests until the
  form controller ships. Each `Creative` exposes `interactiveExperience`: a
  `LeadGenerationExperience` descriptor (type, formId, formInstanceId,
  preparedVersionId, prefillAttributeKeys, expiresAt; the launch URL and
  preparation token are not public), an `UnsupportedInteractiveExperience` for an
  unknown or malformed one (treat the creative as not openable), or `null` for an
  ordinary creative. Lead Generation ads are served on `apiVersion` `2025-11-01`
  or later; the SDK warns when enabled without one.

## 0.8.0 - 2026-11-18

### Added

- **Typed audience signals.** One setter per Standard key on the request
  builder (`setAgeGroup`, `setGender`, `setAccountType`,
  `setSubscriptionStatus`, `setAccountTenure`, `setActivityFrequency30d`,
  `setLastActivityRecency`), each taking an enum of the catalog's values, and
  `setPublisherSegments` (always an array; duplicates dropped; codes checked
  against `^[a-zA-Z0-9_]+$`). `null` removes a key. `Device` gains `carrier`
  and `category` (`DeviceCategory.phone`, `.tablet`, `.other`). An app that
  sets none of them sends exactly what it sent before. Audience signals need
  Audience Signals enabled on the workspace and `apiVersion` `2025-11-01` to be
  recorded in reporting. (#105)
- **Device carrier and category, opt-in.** `SDKConfig(collectDeviceSignals: true)`
  reads the mobile carrier (Android only, from the default data subscription)
  and the device category (`phone`, `tablet` or `other`) and sends them as
  `device.carrier` / `device.category`. Off by default: a workspace without
  audience signals enabled rejects requests that carry these fields, so an app
  that upgrades and changes nothing sends exactly what it sent before. Values
  set by hand with `setDeviceConfig(carrier:, category:)` are sent either way.
  The package is now a Flutter plugin (Android and iOS native code, no new
  permissions). (#108)
- **Fresh carrier and category on every request (opted-in apps).** `requestAds`
  waits at most 300 ms for a fresh native read and otherwise sends the last
  values read; concurrent requests share one read. A value set by hand is never
  overwritten, `clearDeviceConfig()` stops collection until
  `resetDeviceConfig()`, and a read that lands after either never undoes it.
  `getHttpRequest` stays synchronous and uses the values from build time. (#109)
- **Audience signals guide in the README.** Publisher segments (set, clear,
  reset; 1–32 character codes; at most 20 per request), device carrier and
  category (opt-in collection, a value set by hand, or absent), one request
  example per audience surface, and the validation codes the engine can return.
  (#112) The guide states that the Standard keys and publisher segments also
  need Audience Signals enabled on the workspace (otherwise 422, code 10028).
  (#115)
- **docs: README sections for Carousel and Branded Assets.** Carousel: render
  `creative.slides` in the order given (never re-sorted by `position`), read
  each slide's `contents`, and report with `trackSlideView` / `trackSlideViews`
  / `trackSlideClick` (never `fireClick`). Branded Assets:
  `metadata.assetContext` (`vehicle_marker`), `branded_image`,
  `accessible_label` and `destination_url` through the content lookup, and
  `fireAssetTap`, which is not a click. Sponsored Pin Locations now says
  `pinImage` is a creative-level content key read the same way. (#122)
- **The engine's error code on every 4xx.** `ClientError` and
  `UnexpectedStatusError` gain `errors`: the engine's `{code, message}` entries
  from the response body (empty when it has none), also in the error's
  message. A device `carrier` or `category` sent to a workspace without
  Audience Signals now shows code 10009 on the 400 instead of only "Client
  error: 400". A 422 with errors is still a `ValidationError`, and a malformed
  entry is dropped instead of failing the whole parse. (#124, fixes #113)
- **A warning when audience signals are sent without `apiVersion`.** Like the
  Journey warning: a request that carries a Standard key, publisher segments,
  or a device carrier or category while `SDKConfig.apiVersion` is null logs one
  warning, because the default route matches the values but does not record
  them as audience dimensions. (#124)
- **A debug line when a native read fails.** A failed carrier/category read
  logs one `fine` line on `SDKConfig.logger` (Dart) and a `Log.d` line tagged
  `AdMoai` (Android), with the failure's type only, never a device value.
  `DeviceConfig.systemDefault` takes an optional `logger`. (#124)
- **The iOS plugin is tested.** An XCTest runs the category rule (idiom, iPad
  app on a Mac, Catalyst) and checks that no carrier is ever returned, on an
  iPhone and an iPad simulator in CI. (#124)
- **docs: what each audience value means**, in the README and the dartdoc
  (completed years, a recorded choice, the account's age, one completed
  activity, the 30 x 24 h window, elapsed days, and what `never`, `none`,
  `zero` and `other` mean); carrier and category are not targetable yet; the
  README example shows all seven setters; the refusal table gives the HTTP
  status and the thrown type, with 10028 (422) and 10009 (400). (#124)

### Changed

- **Trip presets renamed to activity.** `trip_frequency_30d` and
  `last_trip_recency` are now `activity_frequency_30d` and
  `last_activity_recency` ("Activity in 30 days" and "Last activity" in the Ad
  Manager), because they count any completed activity: parking sessions,
  rentals, train rides, flights. The Dart names follow:
  `setActivityFrequency30d(ActivityFrequency30d)` and
  `setLastActivityRecency(LastActivityRecency)`, with `times1To2`, `times3To9`
  and `times10Plus` in place of `trips1To2`, `trips3To9` and `trips10Plus`. The
  wire values are unchanged. These setters have not shipped in a release, so
  there is no deprecated alias. (#122)
- The contract tests adopt `@admoai/sdk-scenarios` 2.0.0 (schemaVersion 6): the
  runner sends a scenario's manual `device` and list values in `custom`. (#112)
- The contract tests adopt `@admoai/sdk-scenarios` 3.0.0 (still schemaVersion
  6): the live audience scenarios send `activity_frequency_30d` and
  `last_activity_recency`. (#122)
- The contract tests adopt `@admoai/sdk-scenarios` 3.1.0 (still schemaVersion
  6): AS1, AS20 (device) and AS21 (segments) run with no version header
  (`"apiVersion": "none"`, which the runner already sends as no header), and
  AS6/AS9 pin 2025-11-01. (#124)
- The contract tests adopt `@admoai/sdk-scenarios` 3.2.0 (still schemaVersion
  6): SP16, a Journey screen on a template based on Sponsored Pin Location
  serves the advertiser's matched shops. (#125)

## 0.7.0 - 2026-11-10

### Added

- **Standard formats.** `creative.metadata` exposes `effectiveStandardFormatKey`,
  `effectiveStandardFormatVersion`, `templateSource` and `assetContext`
  (`"vehicle_marker"` on Branded Assets), all `null` when the engine does not
  send them. (#93, #98)
- **Carousel slides.** `creative.slides` lists a Carousel's slides in order,
  each with its id, position, contents and trackers. `trackSlideView` /
  `trackSlideViews` send a slide's `slide_view` once per decision response,
  among the last 500 slide-view URLs the SDK fired (the same bound as pin
  views); `trackSlideClick` sends that view first if it is still pending, then the
  slide's `default` click, and fires the creative's third-party click trackers
  once. A Carousel has no creative-level click: use `trackSlideClick`, not
  `fireClick`. (#95, #99)
- **Custom events.** `fireExpand`, `fireClose` and `fireAssetTap`. (#95)

## 0.6.1 - 2026-10-20

### Fixed

- **A re-rendered pin no longer re-sends its view beacon.** `trackPointViews`
  used to de-duplicate only within one call, so a map re-rendering the same
  response on every zoom or pan sent the same view URLs again. The SDK now
  remembers the last 500 pin-view URLs it fired and sends each one once per
  decision response; a new response returning the same location is still
  reported. `trackPointView` follows the same rule; `trackPointTap` and
  `trackPointClick` are unchanged, and nothing is retried. **Reported
  `pin_view` counts do not change** — the server was already de-duplicating;
  this only removes the wasted requests. Calling `trackPointViews` on every
  render is now the intended integration; an app-side "already viewed" set is
  no longer needed. (#63)

## 0.6.0 - 2026-10-13

### Added

- **Sponsored Pin Locations** — a distance search on the request
  (`setDistanceTargeting` with `Distance.radius` or `Distance.bounds`, never
  both, plus an optional `limit`), typed access to the places that answered it
  (`creative.matchedPoints`, nearest first, tolerant per entry), and point-level
  tracking (`trackPointView` / `trackPointViews` / `trackPointTap` /
  `trackPointClick`). Nothing fires automatically: the SDK draws no map and
  cannot know which pins the user saw. A tap is free; a click is billable and
  *replaces* `fireClick` for that gesture. Requires decision-engine API version
  `2025-11-01`. (#56)

### Fixed

- `fireClick` no longer follows the tracking endpoint's `302`. The redirect is
  meant for browsers that navigate with the tracking URL; a beacon takes the
  first response as final and never requests the advertiser's landing page.
  Opening the destination is the app's job, from the creative's contents. (#59)

### Documentation

- A Sponsored Pin campaign needs a distance search on the request to serve. (#57)

## 0.5.1 - 2026-09-22

### Fixed

- Third-party tracker URLs with embedded credentials (`user:pass@`) or a
  fragment are now discarded at dispatch validation with sanitized, URL-free
  reasons — defense in depth alongside the Ad Manager's creation-time
  rejection, matching the iOS and Android SDKs.

## 0.5.0 - 2026-09-21

### Added

- **Third-party event trackers** — `fireImpression`/`fireClick` automatically fan
  out the fixed agency tracking URLs the engine serves under
  `tracking.thirdPartyTrackers` (`X-Decision-Version: 2025-11-01`), with public
  signatures unchanged. Impression trackers fire on `fireImpression`; *any*-click
  trackers on every valid click; *specific* trackers only when the reported key
  equals their `eventKey`. Exactly one attempt per matching tracker per
  invocation, byte-identical URLs deduplicated per invocation, and more than 10
  valid entries discards the whole collection. Dispatch uses a dedicated
  credential-isolated client (plain GET, no identity headers, redirects
  terminal, per-tracker failure isolation) and tracker URLs are never logged.
  A URL the platform parser cannot round-trip byte-identically (e.g. a raw
  `%%MACRO%%`) is discarded rather than fired mutated. Decoding is tolerant
  per entry; older SDK versions ignore the field.

### Tests

- Test: Live third-party tracker E2E runner
  (`test/e2e/third_party_tracker_e2e_test.dart`, tag `e2e`) — 8 scenarios driving
  the real SDK against a locally-seeded decision-engine and Turso, self-seeding
  its tracker fixtures and asserting the wire byte-identically. Excluded from the
  offline gate.

## 0.4.0 - 2026-08-06

Adds **Journey Takeover Ads** support — additive and backward-compatible. Requires decision-engine API version **`2025-11-01`** or later (set `SDKConfig.apiVersion = "2025-11-01"`); older versions ignore the Journey fields and behave exactly as before.

Also carries the cross-SDK parity pass: the divergences from the Android reference
implementation found by a line-by-line contract review, plus the live end-to-end
verification that proves the SDK and the decision-engine actually agree. Signed off
with three consecutive runs of the 70-scenario live E2E suite against a local
decision-engine — 70 passed, 0 failed, 0 skipped each, with the wizard-parity group
mechanically enforced (`ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD=1`) so the
platform-writes/engine-reads seam could not silently go unverified.

### Features — Journey Takeover Ads

- Feat: Journey request context — top-level `sessionId` and `journeyOpt` (`JourneyOpt.optIn` / `optOut`) on the request; builder `setSessionId` / `clearSessionId` / `setJourneyOpt` / `clearJourneyOpt`; sticky-but-rotatable session via `AdMoai.initialize(sessionId:)` + `AdMoai.setSessionId` / `clearSessionId` (per-request builder override wins). `sessionId` is trimmed and omitted when blank; over-length values (> 256 UTF-8 bytes) are sent as-is with a PII-safe warning (reason token only).
- Feat: Read-only Journey response metadata — `Creative.journey` (`CreativeJourney`: `dealId`, `instanceId`, `definitionKey`, `stageId`, `stageKey`, `stageNodeId`, `sessionId`, `optStatus`, `isCompletion`, `pricingModel`, `fallbackBillingMode`) and `JourneyHelper` extension (`isJourneyAd`, read-only getters, `isJourneyCompletion`, `hasCompletionUrl`).
- Feat: Journey tracking — `Tracking.completions` + `getCompletionUrl` + `TrackingType.completion`, and `AdMoai.fireCompletion(tracking, key:)` for `custom_event` completion deals.
- Feat: No-ad helpers — `Decision.hasCreative` / `isNoAd` treat `creatives: []` (single-brand takeover protection) and `creatives: null` (no-fill) uniformly as no-ad; the SDK never substitutes a local/cached/competing ad.
- Feat: Deprecation-aware logging — a single warning is logged when a response carries `X-API-Deprecated: true` (with sunset date when present).

### Fixes — Journey Takeover Ads

- Fix: Tracking requests now send `X-Tracking-Version` (from `apiVersion`) instead of `X-Decision-Version`. The engine's tracking endpoint version-routes on `X-Tracking-Version` only; the previous header silently routed Journey callbacks to a handler that skipped Journey enrichment and custom-event completion.

### Features — cross-SDK parity

- Feat: `AdMoai.fireCustomEvent(tracking, key)` — matches the Android SDK's name.
  `fireCustom` is kept as a `@Deprecated` alias that forwards to it, so existing
  integrations keep compiling; it will be removed in 1.0.0.

### Fixes — cross-SDK parity

- Fix: `Creative.isJourneyAd()` now requires a real server-issued `dealId` or
  `instanceId` instead of merely a non-null `journey` block. The Tolerant Reader
  decodes `"journey": {}` (or a block whose fields are all missing/retyped) into a
  non-null `CreativeJourney` with every field `null`, so a normal ad could report
  `isJourneyAd() == true` while every accessor returned `null`. Matches the Android
  SDK.
- Fix: `fireCompletion` now warns when `SDKConfig.apiVersion` is `null`. The
  tracking endpoint version-routes on `X-Tracking-Version` (derived from
  `apiVersion`); without it the callback hits the legacy handler and the completion
  is **not recorded**, so CPT revenue was silently lost while the fire looked
  successful.
- Fix: A warning is now logged when a request carries Journey context
  (`sessionId` / `journeyOpt`) but `apiVersion` is `null` — the engine silently
  ignores the Journey fields and serves normal ads, which is otherwise invisible.
- Fix: `fireTracking` now requires an absolute `http`/`https` URL with a non-empty
  host. The previous check accepted any value with a scheme, admitting `mailto:`,
  `file:`, `ftp://` and hostless strings. The rejection warning remains PII-safe
  (reason only, never the URL).
- Fix: `test/integration_live_test.dart` made no network calls at all.
  `TestWidgetsFlutterBinding` installs an `HttpOverrides` that answers every request
  with a mocked HTTP 400, and the suite soft-logged those as warnings — so it passed
  green while covering nothing. It now clears the override.
- Fix: `Creative.isSkippable()` always returned `false` and
  `Creative.getSkipOffset()` always returned `null`. Both matched the content keys
  `isSkippable` / `skipOffset` in camelCase, while the platform creates template
  fields in snake_case and a live serve returns `is_skippable` / `skip_offset` — so
  neither could ever match. The tests that covered them used camelCase fixtures, so
  they encoded the same wrong assumption as the code and passed throughout. Both now
  prefer the engine-owned `metadata.isSkippable` / `metadata.skipOffsetSeconds`
  (the only source the iOS SDK reads) and accept either casing in the content
  fallback. The identical fix is applied to the Android SDK, which had the same
  mismatch.
- Fix: `Metadata` dropped three fields the engine's `2025-11-01` contract sends and
  that both iOS and Android model: `impId`, `skipOffsetSeconds` and `endCardMode`.
  Since the Tolerant Reader discards unknown fields by design, they were silently
  lost — and the engine emits `impId`, the render-level attribution key, on **every**
  journey serve. A Flutter publisher could not read a value their iOS and Android
  counterparts could.

### Tests

- Test: Live Journey E2E runner (`test/e2e/journey_e2e_test.dart`, tag `e2e`,
  driven by `tool/journey_e2e.sh`) — 37 scenarios driving the real SDK against a
  locally-seeded decision-engine, covering request forwarding, stage progression and
  multi-node, opt-in/opt-out, tracking transport and ingestion, frequency capping,
  both completion strategies, mandatory-hold vs optional-skip, geo/location/
  destination targeting, runtime-state TTL expiry and refresh, video delivery, and
  a wizard-parity group driven by a journey authored in the Ad Manager UI. Preflight
  aborts with a diagnosis (exit 2) when the environment is unusable; a missing
  fixture SKIPs rather than FAILs; results are written to
  `build/journey-e2e/report.json`. Excluded from the offline gate
  (`flutter test --exclude-tags "live || e2e"`). For release sign-off,
  `ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD=1` turns a skipped wizard-parity group into a
  failure, so a destroyed hand-built fixture cannot read as green.
- Test: Parity regression guards (`test/journey_parity_test.dart`) for each fix
  above, and a compile-check (`test/doc_examples_compile_test.dart`) that fails the
  build if the README documents an API symbol that does not exist.

- Test: the live E2E runner's ingestion path now sends `X-Tracking-Version` on every
  fired tracking URL, via a single `fireTracking` helper in the harness. `GET
  /v1/tracking` version-routes on that header: without it the callback lands on the
  `v20250101` handler, which has no Journey enrichment, so the row reaches Tinybird
  with an empty `jy` block and is invisible to every Journey KPI — while still
  answering 202, so the scenario passed anyway. §D6 previously fired with a bare
  client and no headers, verifying strictly less than it claimed
  (see admoai-android#80, the same defect on the Android runner; iOS was unaffected).
  Redirects are controlled per-request so a click's 302 is success and is not chased
  to the advertiser URL.
- Test: §Y metric-emission group (Y1/Y2/Y3), ported from the Android runner. These
  procedurally FIRE tracking rather than only asserting a URL was exposed: Y1 fires an
  impression and a click so CTR has data at all; Y2 emits one journey clicked three
  times and another never clicked, which is the acceptance case for adhub#2580
  (impression CTR and Journey CTR must diverge); Y3 spans 3s of real wall-clock before
  completing, so Avg Duration and the Avg Attention Time derived from it are non-zero
  rather than floored at ~0. Verified end to end against a local tinybird-local: all
  rows landed with Journey context, and the deal Y2 targets reported CTR 66.67% against
  Journey CTR 16.67% — the first time that divergence has been demonstrated from the
  Flutter SDK.

### Docs

- Docs: Rewrote the README's Journey Takeover Ads guide — the SDK's ownership split
  as a table, the one-session-every-call rule with both failure modes, the full
  `sessionId` contract (ownership, stickiness, per-request override, when to rotate,
  the 256-byte cap, and that it is PII and not a user id), the three `journeyOpt`
  states with the **omitted-vs-`optOut` permissive trap** called out, that opt-out
  *ends* rather than pauses a journey, all thirteen metadata accessors with a warning
  not to branch UI on stage keys, both completion modes, no-ad as correct takeover
  behaviour, two worked examples, the VAST double-count rule, a common-mistakes
  table, and two self-checks.
- Docs: Corrected "The SDK fires tracking beacons via HTTP requests automatically"
  — it never fires anything automatically. Added the missing `fireCompletion` /
  `fireTracking` / `fireCustomEvent` to the tracking reference, completed the
  response-structure tree (`journey`, `verificationScriptResources`, the five
  tracking lists), and completed the `SDKConfig` table.

### Compatibility

- All changes are additive; existing non-Journey integrations continue to work unchanged.
- The **entire decision response is now parsed as a Tolerant Reader** (docs.admoai.com): unknown fields are ignored, retyped/missing fields degrade to safe defaults (`null`, or `''`/empty for currently non-null fields — a non-breaking choice over widening the public API), and malformed list entries (contents, tracking, verifications, creatives) are dropped instead of throwing. One bad field can no longer drop the whole response, so the SDK survives additive engine evolution without a version bump. Applies to the response envelope, `Creative` shell, `Metadata`, `Content`, `Advertiser`, `Template`, `VastData`, tracking, and Journey blocks.

## 0.3.0

Brings the Flutter SDK to feature parity with iOS v1.4.0 and Android v1.2.0+ and fixes a set of production crash bugs around partial server responses.

### Features

- Feat: `SDKConfig.defaultLanguage` — sets `Accept-Language` header on decision and tracking requests
- Feat: Granular network timeouts — `SDKConfig.requestTimeout`, `connectTimeout`, `receiveTimeout` (Duration, default 10 s each); `AdMoai.initialize` now accepts an optional `http.Client` for cert pinning, proxies, etc.
- Feat: `User-Agent: AdMoaiSDK/{version}` header on decision + tracking requests
- Feat: `Format.video` placement format (requires `apiVersion = "2025-11-01"+`)
- Feat: Destination targeting — `Destination(latitude, longitude, minConfidence)`, builder methods `addDestinationTargeting` / `setDestinationTargeting` / `clearDestinationTargeting`, dedup, `[0.0, 1.0]` validation
- Feat: Video metadata fields on `Metadata` — `duration`, `aspectRatio`, `isSkippable`, `format`, `style`
- Feat: `Advertiser.id` field
- Feat: Open Measurement verification — `VerificationScriptResource` model, `Creative.verificationScriptResources`, `getVerificationResources()` and `hasOMVerification()` helpers, README OM section

### Fixes

- Fix: `Advertiser.name/legalName/logoUrl`, `Template.style`, `Tracking.impressions` relaxed to nullable; partial responses no longer crash on parse
- Fix: `Metadata.advertiserId` and `Metadata.language` relaxed to nullable
- Fix: `getContent`, `getImpressionUrl`, `getClickUrl`, `getCustomUrl`, `getVideoEventUrl` now return `null` instead of throwing `StateError` when the requested key is not present
- Fix: Unmapped HTTP status codes now surface as `UnexpectedStatusError(int statusCode)` instead of being collapsed into a generic `NetworkError`
- Fix: `AdMoaiClient` no longer rewraps typed `APIError`s into `NetworkError` — `ClientError`, `ServerError`, `ValidationError`, `UnexpectedStatusError` now propagate to callers as declared
- Fix: `ServerError` now covers the full 5xx range (was only `500` exactly)

## 0.2.1

- Fix: Tracking requests (`fireImpression`, `fireClick`, `fireCustom`, `fireVideoEvent`) now send the `X-Decision-Version` header when `apiVersion` is configured, matching the decision request

## 0.2.0

- Feat: Video ads support across JSON, VAST Tag, and VAST XML delivery methods
- Feat: Helper methods to detect video ads, extract video URLs, and track video events
- Feat: Skippable ads handling
- Feat: Example app screen for testing video ads

## 0.1.1

- Fix: Special characters like £ now display correctly in ad content by properly implementing UTF-8 encoding for API responses

## 0.1.0

- Initial release
