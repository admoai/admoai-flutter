# Journey E2E fixtures

## `wizard_scooter_journey.json`

A read-only snapshot of the **hand-built wizard fixture** that drives the
wizard-parity scenario group (`K1`–`K4`) in `test/e2e/journey_e2e_test.dart`.

### Why this fixture exists at all

Every other fixture the E2E suite drives is written by the decision-engine's Go
mock seed. A seeded fixture encodes **what the engine expects**, so it can never
catch a mismatch between what the **Ad Manager UI writes** and what the **engine
reads**. Both real bugs of the Android verification rounds lived in exactly that
seam, and **both survived a fully green suite**:

- **adhub #2459** — the wizard always persists a `{"enabled":bool,"payload":{…}}`
  targeting envelope, even with the toggle off. The engine unwrapped it for
  geo/location/destination but passed `custom_targeting` through raw, so every
  wizard-created journey deal was dropped from every shortlist. No UI-created
  journey ever served.
- **adhub #2483** — the platform writes template fields in **camelCase**
  (`destinationUrl`, `urlSlide1..3`) while the click resolver matched a
  hand-maintained **snake_case** list. `tracking.clicks` was `[]` on **every**
  journey serve for weeks; journey CTR was unmeasurable.

This fixture is the only thing in the suite that covers that seam, which is why
it must stay **platform-authored**. Promoting it to a Go seed would make it
reproducible and simultaneously destroy the property that makes it valuable.

### The trap

Because it is hand-built, **`make db-reset` destroys it**. The `K` scenarios then
report **SKIP**, and the summary still reads `0 failed` and looks green — the
platform→engine seam goes unverified with nothing signalling it.

**Before signing off a release, confirm the `K` scenarios are `PASS`, not `SKIP`** —
enforce it mechanically with `ADMOAI_JOURNEY_E2E_REQUIRE_WIZARD=1 tool/journey_e2e.sh`,
which turns a §K SKIP into a failure.

> This is not hypothetical. The fixture was destroyed by a `make db-reset` **within an
> hour** of the suite first passing with §K green, and had to be rebuilt from this file.
> Expect to rebuild it.

### Config as captured (2026-07-30, engine DB on `:8081`)

| Thing | Value |
|---|---|
| Definition key | `scooter_journey` |
| Deal | any `jad_…` deal on that definition ("nike scooter ride"), `status=active`. The public id is NOT pinned — every rebuild mints a new ULID. |
| Stages (in order) | `pre_ride` → `post_ride` → `summary_ride` |
| Active node placements | `promotions` → `waiting` → `poi` |
| Templates | `carousel3Slides`, `carousel3Slides`, `imageWithText` |
| Pricing | `cpt`, fallback `bill_per_stage`, pricing overrides off |
| Completion | `final_stage` → `summary_ride` (the **last** stage) |
| Stage requirement | all three `optional` |
| Targeting | all four toggles **off** — the envelopes are still persisted (that is the point) |
| Frequency cap | off |
| Parting | `active: false` |
| Locale | `en` only |
| Template field keys | camelCase, incl. `destinationUrl` and `urlSlide1..3` |

The snapshot also contains six `journey_stage_nodes` rows, three of them
`status=deleted` — leftovers from building the journey in the UI. They are kept
deliberately: a real wizard-authored graph carries that history, and the engine
must ignore deleted nodes.

### Rebuilding it after a `db-reset`

Recreate it **in the Ad Manager UI** (not by seeding), matching the table above.
Rules that are easy to get subtly wrong:

1. **Build the entire stage/node graph before activating the deal.** Activation
   auto-locks the definition (a DB invariant) and structural edits are then
   rejected.
2. The deal must be **active** with a live flight window, and its locale must
   include the locale the runner requests (`en`). A creative without an `en`
   variant will not resolve.
3. Pick placements **no other active journey deal uses**, or priority masks the
   fixture.
4. Choose a template with a **url-type field**, or there is no click destination
   for `K1` to assert.
5. Leave frequency cap and parting **off** — both make runs non-deterministic
   (parting is wall-clock/timezone dependent).
6. Fill **every** creative field, including the click destination URL.

Then re-capture this snapshot so it reflects what actually passed.

### Re-capturing

The snapshot is produced by read-only `SELECT`s against the local libSQL HTTP
endpoint (`POST http://127.0.0.1:8081/v2/pipeline`), scoped by definition key so
it can never bleed rows from the seeded demo/`e2e_*` journeys. See
`tool/dump_wizard_fixture.py`.

The runner does **not** read this file to make its assertions — it asserts against
what the SDK observes from a live engine. The snapshot is documentation of the
fixture's shape, so a future round can diff what changed rather than guess.
