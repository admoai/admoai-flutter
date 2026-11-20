# Interactive experience fixtures

Verbatim copy of adhub `shared/interactiveexperience/contract/` (decision
fixtures, `standard-fields.json`, `bridge-messages.json` and `bridge/`, the
bridge message fixtures with `context.json` and `invalid/`). The source of truth
is the contract pack: refresh by copying, never hand-edit.

The bridge files are refreshed together with the embedded copy the SDK reads
(`lib/src/interactive/contract/bridge_messages.g.dart`):

    tool/sync_contract.sh <path to the contract pack directory>
    flutter test test/bridge_protocol_test.dart

The decision fixtures (`creative-descriptor.json`, `request-*.json`) are copied
by hand.
