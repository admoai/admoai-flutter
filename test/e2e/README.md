# Journey Ads — live E2E runner

Drives the **real** SDK against a **locally-running, seeded decision-engine**.

Unit tests can only prove the SDK parses fixtures we wrote ourselves. They cannot
prove the SDK and the engine agree — and Journey Ads is the first Admoai feature
where the publisher must do something in *every* call for a *sequence* of calls to
work, so a disagreement means journeys silently never progress or completions
silently never bill.

## Running it

```bash
tool/journey_e2e.sh                                    # the gate
flutter test test/e2e/journey_e2e_test.dart --reporter expanded   # raw output
```

| Env | Default |
|---|---|
| `ADMOAI_JOURNEY_E2E_BASE_URL` | `http://127.0.0.1:8080` |
| `ADMOAI_JOURNEY_E2E_VERSION` | `2025-11-01` |
| `ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD` | `0` — set to `1` for release sign-off, which turns a §K SKIP into a failure |

**For release sign-off, run it with the wizard gate on:**

```bash
ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD=1 tool/journey_e2e.sh
```

Without it a missing wizard fixture skips and the run exits `0` — correct for day-to-day
development, dangerous at sign-off. This is not hypothetical: the fixture was destroyed by
a `make db-reset` within an hour of this suite first passing with §K green.

**Exit codes** (same contract as the Android runner):

| Code | Meaning |
|---|---|
| `0` | pass — a documented SKIP is allowed |
| `1` | a scenario FAILED |
| `2` | preflight aborted — the environment is unusable, not the SDK |

`flutter test` only distinguishes pass/fail, so `tool/journey_e2e.sh` takes the
exit code from `build/journey-e2e/report.json`. That report is also what lets a
later round diff scenario-by-scenario after an engine change instead of re-reading
console output. `build/` is gitignored, so the last passing run is committed
alongside this file as `report.json` — diff a fresh run against it.

**The offline gate stays offline.** This suite is tagged `e2e` and excluded from it:

```bash
flutter test --exclude-tags "live || e2e"
```

## Environment requirements

Boot is **owner-operated** — ask, do not attempt it unprompted.

- `make start` from the adhub root brings up the stack (engine, Redis, libSQL).
- Statsig gate `is_journey_ads_enabled = true` — **default OFF**. With it off,
  every journey call silently falls back to normal ads.
- A 32-char `TRACKING_KEY`; VAST env vars for §G.
- Mock seeds load **only into an empty DB**.
- ⚠️ **`make db-reset` destroys all locally-created platform data, including the
  hand-built §K wizard fixture.** Warn the owner before suggesting it. See
  `fixtures/README.md`.

Read-only DB inspection is available over the libSQL HTTP endpoint on `:8081`
(`POST /v2/pipeline`) — useful for confirming fixture state before blaming the SDK.

## Design decisions

Each exists because the naive alternative produced a wrong or useless result.
Most were earned on the Android runner; two are specific to Flutter.

1. **Black-box only.** Assertions cover the SDK result and the `/decision`
   transport. Engine internals — Redis keys, decoded token identity, billing
   dedupe and totals, reporting, concurrency — are **out of scope by design** and
   owned by adhub's Go tests. Asserting them from an SDK is impossible; pretending
   otherwise produces false confidence.
2. **Every no-ad assertion needs a competing normal ad as a positive control.**
   Without one, "no ad" is indistinguishable from "empty placement" and the test
   proves nothing.
3. **Controls send no session at all.** Sending a session with `journeyOpt`
   *omitted* is effectively opt-in, so such a "control" starts and holds its own
   journey and can never serve the competing ad.
4. **Dedicated placements per fixture.** The seeded fixtures live on their own
   `sdk_e2e_*` placements so priority tie-breaks cannot mask the fixture under
   test. §B is the exception — it drives the shipped demo journey on shared demo
   placements, which is exactly why preflight proves that ownership.
5. **A unique session id per scenario, and a unique user id per cap scenario.**
   This makes the suite **re-runnable with no reseed and no Redis flush**:
   runtime-state and `fc_journey:` keys can never collide across runs. It is the
   difference between a usable gate and a one-shot.
6. **Missing fixture ⇒ SKIP, not FAIL.** A fixture that was never seeded is an
   environment fact, not a defect.
7. **Environment problems abort in preflight with a precise diagnosis (exit 2)**,
   not as N assertion failures. Preflight proves connectivity, that a journey
   serves at all (catching gate-off / Redis-down / seeds-missing), and that the
   demo placement is owned by the expected definition — turning four cryptic
   failures into one line naming the offending definition.
8. **Negative targeting cases use real but non-matching values.** `geoname_id = 1`
   is absent from the engine's geoname set entirely, so it makes the engine
   *error* rather than cleanly not-match.
9. **Real networking must be re-enabled explicitly.**
   `TestWidgetsFlutterBinding` installs an `HttpOverrides` that answers every
   request with a mocked **HTTP 400** without touching the network. `preflight`
   asserts it is cleared, because otherwise every scenario fails identically and
   meaninglessly. `test/integration_live_test.dart` shipped in exactly that state.
10. **The suite drives the real `AdMoai.initialize`**, not the `forTesting` seam —
    only the platform channels are stubbed. A runner that exercises a test-only
    entry point cannot prove the publisher's path works.
11. **A `§Self-check` group proves the harness forwards config.** The Android
    runner's worst bug was a helper that silently dropped every caller's
    `setUserId` and targeting — which looked exactly like an engine bug.

## Scenario groups

| Group | Covers |
|---|---|
| `§Self-check` | the harness forwards user id and targeting to the wire |
| `§K` | **wizard parity** — a journey authored in the Ad Manager UI |
| `§A` | request forwarding, wire shape, version header, sticky session |
| `§B` | stage progression, multi-node, metadata coherence |
| `§C` | opt-in / opt-out, and that opt-out *ends* rather than pauses |
| `§D` | tracking transport, verbatim firing, no-ad, ingestion smoke |
| `§E` | frequency cap: new-entry gating, and never blocking continuation |
| `§H` | CPT pricing, exact fallback mode, both completion strategies |
| `§J` | mandatory hold vs optional skip, geo/location/destination targeting |
| `§F` | runtime-state TTL expiry and refresh (spends real wall-clock) |
| `§G` | video delivery: JSON beacons exposed, VAST beacons *not* surfaced |

§K runs early on purpose: it is the only platform-authored fixture and cannot be
recreated from code.

## Before signing off

- [ ] **Three consecutive runs with no reseed, identical results.** Otherwise it
      is not a gate.
- [ ] **§K is PASS, not SKIP** — enforce it with
      `ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD=1`. The fixture is hand-built, so a
      `db-reset` makes §K skip while the summary still reads "0 failed" and looks
      green, leaving the platform→engine seam unverified with nothing signalling it.
- [ ] Every other SKIP is deliberate and explained in the output.
- [ ] The offline suite is still green and hermetic.

## Deliberately out of scope

Owned by adhub's Go service-layer tests: billing and reporting interpretation, CPT
accounting, completion dedupe and charge counts, decoded tracking-token identity,
Redis runtime-state internals, concurrency and atomicity, mid-flight mutation.

Needs a harness this one cannot be:

- **Widget-lifecycle duplication** — rebuilds, hot reload, repeated `FutureBuilder`
  / stream collection, and retries must never duplicate a `/decision`, impression
  or completion. Needs a widget-test or driver harness.
- **Real video playback callbacks** fired from an actual player. This suite proves
  the SDK *exposes* delivery data and does *not* auto-fire; it cannot drive
  playback.

Per-node pricing overrides are **not SDK-observable** — the response's
`pricingModel` always comes from the deal default and the override is propagated
separately to billing, so it stays with the Go tests.
