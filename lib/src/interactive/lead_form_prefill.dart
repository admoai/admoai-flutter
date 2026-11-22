import '../models/interactive_experience.dart';
import 'bridge_protocol.dart';

/// Turns what the app answered into the `values` of the `prefill` message: only
/// the keys the form asked for, trimmed, never blank, within the contract's
/// length (in code points) and, for gender, within its options. The form
/// validates everything else. Pure; it never logs a value. Internal: not
/// exported.
Map<String, String> leadFormPrefillValues(
  Map<StandardAttributeKey, String>? raw,
  Set<StandardAttributeKey> requested,
  BridgeContract contract,
) {
  if (raw == null) return const <String, String>{};
  final maxLength = contract.prefillValueMaxLength;
  final out = <String, String>{};
  for (final key in StandardAttributeKey.values) {
    if (!requested.contains(key)) continue;
    final answered = raw[key];
    if (answered is! String) continue;
    final value = answered.trim();
    if (value.isEmpty) continue;
    if (value.runes.length > maxLength) continue;
    if (key == StandardAttributeKey.gender &&
        !contract.genderValues.contains(value)) {
      continue;
    }
    out[key.wireName] = value;
  }
  return out;
}
