## 0.2.0

### Breaking changes
- `Placement.count` and `Placement.format` are now nullable (`int?`, `Format?`) and no longer have default values. Reading these fields may now return `null`.
- `DecisionRequestBuilder.addPlacement`: `count` and `format` parameters are nullable without defaults, matching `Placement`.
- `TrackingType` enum gained a new `videoEvent` value — exhaustive switches over `TrackingType` will need to add a case.

### Features
- Video ads support: new `delivery` and `vast` fields on `Creative`; new `VastData` model (`tagUrl`, `xmlBase64`).
- New `VideoHelper` extension on `Creative`: `isVastTagDelivery`, `isVastXmlDelivery`, `isJsonDelivery`, `getVastTagUrl`, `getVastXmlBase64`, `isSkippable`, `getSkipOffset`.
- New `videoEvents` tracking list and `getVideoEventUrl({required key})` on `Tracking`; new `fireVideoEvent(tracking, key)` on `AdMoai`.
- New optional `apiVersion` on `SDKConfig`, sent as `X-Decision-Version` header on `/v1/decision` requests.

## 0.1.1

- Fix: Special characters like £ now display correctly in ad content by properly implementing UTF-8 encoding for API responses

## 0.1.0

- Initial release
