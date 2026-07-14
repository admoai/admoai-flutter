## Unreleased

### Fixes

- Fix: Tracking requests (`fireImpression`, `fireClick`, `fireCustom`, `fireVideoEvent`, `fireTracking`) now send the `X-Tracking-Version` header when `apiVersion` is configured, instead of `X-Decision-Version`. Decision requests keep sending `X-Decision-Version`.

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
