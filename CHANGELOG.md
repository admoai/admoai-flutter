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
