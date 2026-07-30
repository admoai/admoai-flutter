# Journey Ads — Flutter parity & verification findings

Round completed **2026-07-30** against `admoai-flutter@chore/tolerant-response-shell`,
reference implementation `admoai-android@test/journey-sdk-e2e-runner`, engine
`adhub@feat/journey-ads-e02-impl` running locally.

## Result

| | |
|---|---|
| Static parity (Tier 1) | 5 divergences found, all fixed; 1 naming difference resolved without a break |
| Offline suite (Tier 2) | **173 passed**, fully hermetic (`flutter test --exclude-tags "live \|\| e2e"`, ~2 s) |
| Live E2E (Tier 3) | **37 passed, 0 failed, 0 skipped** — identical across **three consecutive runs with no reseed** |
| Wizard parity (§K) | **PASS, not SKIP** |
| Docs | Journey guide rewritten to all twelve required points; every documented symbol compile-checked |

## The most valuable finding

**`test/integration_live_test.dart` had never made a single network call.**

`TestWidgetsFlutterBinding.ensureInitialized()` installs an `HttpOverrides` that
answers every `HttpClient` request with a mocked **HTTP 400** and an empty body,
without touching the network. That suite never cleared it. It is also written to
*soft-log* client errors as warnings rather than fail — so 610 lines of "live
integration" coverage against `api.mock.admoai.com` reported green while asserting
nothing about a real server.

It was found only because the new E2E runner hit the same wall: preflight reported
"the engine rejected a plain decision request: 400" while `curl` against the same
endpoint with the same headers and body returned 200.

This is the handoff's central lesson in a new form. The Android rounds found that
*an assertion that was never written is indistinguishable from a passing one*. The
corollary: **an assertion that never executes is indistinguishable from one that
passes.** Both suites looked like coverage and were not.

Fixed (`HttpOverrides.global = null`), and the E2E runner now asserts the override
is cleared during preflight, so it can never silently come back. With real
networking the live suite reports 17 × HTTP 200 and 2 × HTTP 422 — both 422s are
`placement key vast_xml_native_endcard was not found` on the hosted mock, an
environment fact rather than an SDK defect.

## Static parity divergences (Tier 1)

Every line of the platform-agnostic contract was walked against the source. The
request side (R1–R9), response side (P1–P5), tracking (T1–T8), completion (C1–C3)
and no-ad (N1–N2) rules were otherwise present and correct. Five items diverged:

| # | Contract | Divergence | Fix |
|---|---|---|---|
| D1 | **P2** — journey metadata on a normal ad must be `null`/`false`, never a default object | `isJourneyAd()` was `journey != null` (`lib/src/utils/journey_helper.dart:12`). The Tolerant Reader decodes `"journey": {}` — or a block with every field retyped — into a **non-null** `CreativeJourney` with all-null fields, so a normal ad reported `isJourneyAd() == true` while all thirteen accessors returned `null`. Android guards this explicitly. | Require a non-blank `dealId` **or** `instanceId` |
| D2 | **T7** — firing a completion without an `apiVersion` is billing-critical and must warn | `fireCompletion` was silent. `/v1/tracking` version-routes on `X-Tracking-Version` (derived from `apiVersion`); without it the callback hits the legacy handler and does **not record**, so CPT revenue is lost while the fire looks successful. | Warn, then still fire |
| D3 | **R1** — a missing version header means journeys are silently ignored | No warning when a request carried `sessionId`/`journeyOpt` with `apiVersion == null`. Android warns in its request-prepare step. | Warn from both `requestAds` and `getHttpRequest` |
| D4 | **T1** — tracking URLs are absolute | `fireTracking` accepted anything with a scheme (`uri.hasScheme`), admitting `mailto:`, `file:`, `ftp://`, and hostless strings. Android requires `http`/`https` + a non-empty host. | Match Android; keep the warning PII-safe |
| D5 | **T2** — URLs are fired verbatim | Firing goes through `Uri`, which uppercases percent-escape hex digits. **Not a live defect**: engine-minted `?e=` tokens are base64url (verified against a live serve — no `%`, no `+`, no `=`), so the round-trip is byte-identical. | Kept `Uri`-based per owner's call, with a regression test pinning both halves |

Each guard was verified to **bite**: reverting each fix individually makes the
corresponding group in `test/journey_parity_test.dart` fail (D1: 3 failures, D2: 1,
D3: 2, D4: 2). A guard that cannot fail is not a guard.

### Naming difference, resolved without a break

Android exposes `fireCustomEvent`; Flutter and iOS expose `fireCustom`
(`admoai-ios/Sources/AdMoai/AdMoai.swift:205`). Renaming outright would stop
existing `0.4.0` integrations from compiling on upgrade, so `fireCustomEvent` is now
canonical and `fireCustom` remains a `@Deprecated` forwarding alias, removable at
1.0.0.

**Open item for the owner:** iOS still exposes only `fireCustom`. Until the same
alias lands there, the odd-one-out has moved from Android to iOS rather than being
removed. All three should converge on `fireCustomEvent`.

### Deliberate platform idiom, not defects

- Journey accessors are **getters** in Flutter and **extension functions** in Kotlin.
- `isJourneyAd()` is a method while the other accessors are getters — a Flutter-internal
  inconsistency, but renaming it is a public API break and it is already documented
  and used as `isJourneyAd()`. Left alone; flagged for a future major.
- `AdMoai` is instance-based; Android's `Admoai` is a singleton.

## Live E2E verification (Tier 3)

`test/e2e/journey_e2e_test.dart` (tag `e2e`), driven by `tool/journey_e2e.sh`, which
maps the report to Android's exit-code contract (`0` pass / `1` failure / `2`
preflight abort). Report at `build/journey-e2e/report.json`.

All 37 scenarios pass. Notable results:

- **§K wizard parity — PASS.** The hand-built `scooter_journey` fixture
  (`jad_01KYSSB2ND61HZFP3KRG9NET3X`) was still present and active, so the
  platform→engine seam is genuinely verified rather than skipped. It serves stage 1
  with exactly the config the wizard wrote (`cpt` / `bill_per_stage` /
  `final_stage` → `summary_ride`), holds one instance across
  `pre_ride → post_ride`, flips `isCompletion` with **no** beacon on the final
  stage, does not re-serve a served node, and — the #2483 guard — **exposes a click
  URL derived from the wizard's camelCase `urlSlide1..3` fields**.
- **§D6 ingestion — HTTP 202.** The engine accepts a token it minted itself, with
  only scheme/host/port normalized onto the local base URL and the `?e=` token left
  untouched.
- **§H5 completion beacon** — the CPT billing trigger. Exposed, keyed
  `journey_complete`, `isCompletion` stays `false`, and `fireCompletion` dispatches
  exactly one byte-identical request.
- **§H1/H2** assert the **exact** fallback billing mode (`no_charge`, and
  `bill_per_stage` for the `final_stage` deal), not merely a non-blank value — a
  non-blank check passes on any wrong value.
- **§G2** confirms VAST tag/xml expose their payload and surface **zero**
  VAST-owned video-event beacons, so a publisher wiring up both cannot double-count.
- **§Self-check S1** proves the harness forwards `setUserId` and targeting to the
  wire. This exists because the Android runner's worst bug was a config-lambda
  parameter shadowing `build()`, silently dropping every caller's user and
  targeting — which looked exactly like an engine bug.

### Determinism

Three consecutive runs, no reseed, no Redis flush: identical scenario-by-scenario
outcomes (`37/0/0`, exit `0` each time). Session ids are unique per scenario per run
and cap scenarios additionally use unique user ids, so runtime-state and
`fc_journey:` keys can never collide across runs.

### Fixture snapshot

The wizard fixture is hand-built and one `make db-reset` from destruction, so it was
captured read-only to `test/e2e/fixtures/wizard_scooter_journey.json` (with a rebuild
recipe in `test/e2e/fixtures/README.md`) before anything else was done. The snapshot
confirms the seam it exists to cover: all four targeting envelopes are persisted with
`"enabled": false` (the #2459 shape), and the creative content is keyed by camelCase
template fields (`destinationUrl`, `urlSlide1..3` — the #2483 shape).

The runner does **not** read the snapshot to make assertions; it asserts against what
the SDK observes from a live engine. The snapshot is documentation of the fixture's
shape so a later round can diff rather than guess.

## Documentation

The Journey guide now covers all twelve required points, including the two most
likely to cause a broken integration: the **omitted-vs-`optOut` permissive trap**
(previously not mentioned at all) and that **`custom_event` completion only bills if
the publisher fires the beacon**.

Defects found while auditing the existing docs, each of which would have caused a
wrong integration:

- "The SDK fires tracking beacons via HTTP requests automatically" — it never fires
  anything automatically. Directly contradicted contract rule T4.
- `fireCompletion`, `fireTracking` and `fireCustomEvent` were absent from the
  tracking reference — including `fireCompletion`, which is the CPT billing trigger.
- The response-structure tree omitted `journey`, `verificationScriptResources`, and
  the five tracking lists (so `completions` was undiscoverable).
- Five of the thirteen journey accessors were undocumented.
- The `SDKConfig` table listed 3 of 7 parameters.
- No worked examples, no common-mistakes table, no self-checks.

Mechanical audit: fences balanced (44), no duplicate headings, the one anchor
resolves, no broken relative links, published version matches `pubspec.yaml`
(`0.4.0`), and **every** API symbol referenced in the README is compile-checked by
`test/doc_examples_compile_test.dart` — so a documented method that does not exist
now fails the build rather than a publisher's first integration.

## Out of scope, and why

Owned by adhub's Go service-layer tests — not assertable from any SDK: billing and
reporting interpretation, CPT accounting, completion dedupe and charge counts,
decoded tracking-token identity, Redis runtime-state internals, concurrency and
atomicity, mid-flight mutation semantics.

Not SDK-observable at all: **per-node pricing overrides**. The response's
`pricingModel` always comes from the deal default; the override is propagated
separately to billing.

Needs seed data before it can be asserted here: **verification / Open Measurement
inheritance on journey serves** (adhub #2383). The SDK models
`verificationScriptResources`, but the mock seed inserts no verification rows, so a
live journey serve returns `null` and there is nothing to assert.

### Follow-ups for this platform (flagged, not faked)

1. **Widget-lifecycle duplication.** Rebuilds, hot reload, repeated `FutureBuilder`
   or stream collection, and retries must never duplicate a `/decision`, an
   impression, or a completion. A headless runner cannot drive this; it needs a
   widget-test or driver harness. This is the Flutter analogue of Android's
   Activity-recreation gap.
2. **Real video playback callbacks.** This suite proves the SDK *exposes* delivery
   data and does *not* auto-fire. Proving that events fire correctly from an actual
   player's callbacks needs a real player.
3. **iOS `fireCustomEvent` alias**, so all three SDKs converge (see above).
4. **§B still depends on the shipped demo journey** on shared demo placements rather
   than a dedicated `sdk_e2e_*` fixture. Preflight diagnoses drift in one line, so
   this is no longer a correctness risk — but a dedicated 3-stage fixture would make
   the suite fully independent of demo data. Requires adhub seed work.
5. **Where the gate runs.** This is a local, manual pre-release check. Making it CI
   would require orchestrating engine + Redis + libSQL + seeds in CI.

## Unasserted surfaces closed this round

Listed explicitly, because these are the ones that were invisible:

- `isJourneyAd()` against a tolerant-decoded empty/retyped `journey` block (D1).
- `fireCompletion` with no `apiVersion` — the billing-critical path (D2).
- Journey context sent without an `apiVersion` (D3).
- `fireTracking`'s URL guard against non-http schemes and hostless URLs (D4).
- Verbatim firing against a percent-escape-hostile URL, and the token alphabet
  assumption that makes it safe (D5).
- `X-Decision-Version` present on a **journey** decision request (previously
  asserted only for its *absence* on the tracking path).
- Whether the "live" suite reached the network **at all**.
