import 'dart:convert';
import 'dart:math';

import 'contract/bridge_messages.g.dart';

/// The Lead Generation bridge rules of the shared contract pack, read as data
/// from the embedded `bridge-messages.json` and `standard-fields.json`. No limit,
/// pattern or message shape is written in code. Internal: not exported.
///
/// This is a trust boundary (the form page is untrusted web content), so every
/// check fails closed: anything that is not exactly what the contract describes
/// is refused, and a refusal never carries the message.

/// How one payload field is checked.
class BridgeFieldSpec {
  BridgeFieldSpec._({
    required this.type,
    required this.required,
    this.maxLength,
    this.pattern,
    this.enumValues,
    this.allowedItems,
    this.uniqueBy,
    this.items,
  });

  factory BridgeFieldSpec._parse(
      Map<String, dynamic> json, Map<String, Set<String>> lists) {
    final type = json['type'];
    if (!_fieldTypes.contains(type)) {
      throw StateError('bridge contract: unsupported field type');
    }
    Set<String>? named(String key) {
      final name = json[key];
      if (name == null) return null;
      return lists[name] ?? (throw StateError('bridge contract: unknown list'));
    }

    final itemSpecs = json['items'];
    return BridgeFieldSpec._(
      type: type as String,
      required: json['required'] == true,
      maxLength: json['maxLength'] as int?,
      pattern:
          json['pattern'] == null ? null : RegExp(json['pattern'] as String),
      enumValues: (json['enum'] as List?)?.cast<String>().toSet(),
      allowedItems: named('itemsFrom') ?? named('keysFrom'),
      uniqueBy: json['uniqueBy'] as String?,
      items: itemSpecs == null
          ? null
          : {
              for (final e in (itemSpecs as Map<String, dynamic>).entries)
                e.key: BridgeFieldSpec._parse(
                    e.value as Map<String, dynamic>, lists),
            },
    );
  }

  static const _fieldTypes = {
    'string',
    'boolean',
    'string_list',
    'string_map',
    'object_list',
    'https_url',
    'timestamp',
  };

  final String type;
  final bool required;
  final int? maxLength;
  final RegExp? pattern;
  final Set<String>? enumValues;

  /// `itemsFrom` (string_list) or `keysFrom` (string_map): the allowed values.
  final Set<String>? allowedItems;
  final String? uniqueBy;
  final Map<String, BridgeFieldSpec>? items;
}

/// One message type of the contract.
class BridgeMessageSpec {
  const BridgeMessageSpec(this.type, this.direction, this.after, this.fields);

  final String type;
  final String direction;
  final List<String> after;
  final Map<String, BridgeFieldSpec> fields;
}

/// The parsed contract. Parsing throws [StateError] on anything it does not
/// implement, so a pack change never gets silently accepted.
class BridgeContract {
  BridgeContract._({
    required this.maxMessageBytes,
    required this.maxHiddenPreparedForms,
    required this.prefillLookupTimeoutMs,
    required this.instanceIdPattern,
    required this.channelPattern,
    required this.messages,
    required this.prefillKeys,
    required this.genderValues,
  });

  factory BridgeContract.parse(String bridgeJson, String fieldsJson) {
    final bridge = jsonDecode(bridgeJson) as Map<String, dynamic>;
    final fields = jsonDecode(fieldsJson) as Map<String, dynamic>;
    final prefillKeys = (fields['prefillKeys'] as List).cast<String>().toSet();
    final genderValues = {
      for (final o in fields['genderOptions'] as List)
        (o as Map<String, dynamic>)['value'] as String,
    };
    final lists = {'prefillKeys': prefillKeys};
    final envelope = bridge['envelope'] as Map<String, dynamic>;
    RegExp envelopePattern(String key) =>
        RegExp((envelope[key] as Map<String, dynamic>)['pattern'] as String);

    final messages = <String, BridgeMessageSpec>{};
    for (final m in bridge['messages'] as List) {
      final json = m as Map<String, dynamic>;
      final type = json['type'] as String;
      final direction = json['direction'] as String;
      if (direction != _toApp && direction != _toRuntime) {
        throw StateError('bridge contract: unknown direction');
      }
      if (messages.containsKey(type)) {
        throw StateError('bridge contract: duplicate message type');
      }
      messages[type] = BridgeMessageSpec(
        type,
        direction,
        (json['after'] as List).cast<String>(),
        {
          for (final e in (json['payload'] as Map<String, dynamic>).entries)
            e.key:
                BridgeFieldSpec._parse(e.value as Map<String, dynamic>, lists),
        },
      );
    }
    for (final m in messages.values) {
      if (m.after.any((a) => !messages.containsKey(a))) {
        throw StateError('bridge contract: after names an unknown type');
      }
    }
    return BridgeContract._(
      maxMessageBytes: bridge['maxMessageBytes'] as int,
      maxHiddenPreparedForms: bridge['maxHiddenPreparedForms'] as int,
      prefillLookupTimeoutMs: bridge['prefillLookupTimeoutMs'] as int,
      instanceIdPattern: envelopePattern('instanceId'),
      channelPattern: envelopePattern('channel'),
      messages: messages,
      prefillKeys: prefillKeys,
      genderValues: genderValues,
    );
  }

  static final BridgeContract shipped =
      BridgeContract.parse(bridgeMessagesJson, standardFieldsJson);

  static const _toApp = 'runtime_to_app';
  static const _toRuntime = 'app_to_runtime';

  final int maxMessageBytes;
  final int maxHiddenPreparedForms;
  final int prefillLookupTimeoutMs;
  final RegExp instanceIdPattern;
  final RegExp channelPattern;
  final Map<String, BridgeMessageSpec> messages;

  /// The catalog's prefill keys, in no particular order.
  final Set<String> prefillKeys;
  final Set<String> genderValues;

  /// The name of the first payload field that breaks the contract, or null when
  /// [payload] is valid. Never returns a value the sender chose.
  String? firstFault(BridgeMessageSpec spec, Map<Object?, Object?> payload) =>
      _fault(spec.fields, payload, prefill: spec.type == 'prefill');

  String? _fault(Map<String, BridgeFieldSpec> specs, Map<Object?, Object?> m,
      {bool prefill = false}) {
    if (m.keys.any((k) => k is! String || !specs.containsKey(k))) {
      return 'unknown field';
    }
    for (final e in specs.entries) {
      if (!m.containsKey(e.key)) {
        if (e.value.required) return e.key;
        continue;
      }
      if (!_valid(e.value, m[e.key], prefill && e.key == 'values')) {
        return e.key;
      }
    }
    return null;
  }

  bool _valid(BridgeFieldSpec s, Object? v, [bool isPrefill = false]) {
    switch (s.type) {
      case 'string':
        return v is String && _validString(s, v);
      case 'boolean':
        return v is bool;
      case 'https_url':
        return v is String && _isHttpsUrl(v);
      case 'timestamp':
        return v is String && _isTimestamp(v);
      case 'string_list':
        return v is List &&
            v.every((i) =>
                i is String &&
                (s.allowedItems == null || s.allowedItems!.contains(i)));
      case 'string_map':
        if (v is! Map) return false;
        return v.entries.every((e) {
          final k = e.key, value = e.value;
          if (k is! String || value is! String) return false;
          if (s.allowedItems != null && !s.allowedItems!.contains(k)) {
            return false;
          }
          if (s.maxLength != null && value.runes.length > s.maxLength!) {
            return false;
          }
          // The one value with a closed set: gender is a catalog option.
          return !(isPrefill && k == 'gender' && !genderValues.contains(value));
        });
      case 'object_list':
        if (v is! List) return false;
        final seen = <Object?>{};
        for (final item in v) {
          if (item is! Map || _fault(s.items!, item) != null) return false;
          if (s.uniqueBy != null && !seen.add(item[s.uniqueBy])) return false;
        }
        return true;
    }
    return false;
  }

  bool _validString(BridgeFieldSpec s, String v) =>
      (s.maxLength == null || v.runes.length <= s.maxLength!) &&
      (s.pattern == null || s.pattern!.hasMatch(v)) &&
      (s.enumValues == null || s.enumValues!.contains(v));

  static bool _isHttpsUrl(String v) {
    final uri = Uri.tryParse(v);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !v.contains(RegExp(r'\s'));
  }

  static final _rfc3339 =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
          r'(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$');

  /// An RFC 3339 timestamp whose every component is in range, so a date Dart
  /// would silently normalise (`02-30`) or a leap second is refused, like Go's
  /// RFC 3339 parse does.
  static bool _isTimestamp(String v) {
    final m = _rfc3339.firstMatch(v);
    if (m == null) return false;
    int n(int g) => int.parse(m.group(g)!);
    final year = n(1), month = n(2), day = n(3);
    if (month < 1 || month > 12) return false;
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    final inMonth = month == 2 && leap ? 29 : days[month - 1];
    if (day < 1 || day > inMonth) return false;
    if (n(4) > 23 || n(5) > 59 || n(6) > 59) return false;
    if (m.group(7) != null && (n(7) > 23 || n(8) > 59)) return false;
    return true;
  }
}

const _channelAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';

/// A fresh bridge channel: 32 characters of `[A-Za-z0-9_-]` (192 bits) from a
/// cryptographically secure source. [random] is for tests only.
String mintBridgeChannel([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes(
      List.generate(32, (_) => _channelAlphabet.codeUnitAt(r.nextInt(64))));
}

/// Why a message was refused. A reason code only: it never carries content.
enum BridgeRefusal {
  tooLarge,
  notJson,
  badEnvelope,
  wrongInstance,
  wrongChannel,
  unknownType,
  wrongDirection,
  badPayload,
  outOfOrder,
  afterDispose,
}

/// The outcome of [BridgeSession.accept].
sealed class BridgeAcceptance {
  const BridgeAcceptance();
}

/// A valid message from the form. [payload] is an unmodifiable deep copy.
class BridgeMessage extends BridgeAcceptance {
  const BridgeMessage(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;

  @override
  String toString() => 'BridgeMessage($type)';
}

/// A refused message: only the [reason].
class BridgeRefused extends BridgeAcceptance {
  const BridgeRefused(this.reason);

  final BridgeRefusal reason;

  @override
  String toString() => 'BridgeRefused(${reason.name})';
}

/// One bridge instance: the identity every message must carry and the message
/// types exchanged so far (accepted inbound or encoded outbound), which the
/// contract's `after` lists are checked against. Not thread-safe.
class BridgeSession {
  BridgeSession({
    required this.instanceId,
    required this.channel,
    BridgeContract? contract,
  }) : contract = contract ?? BridgeContract.shipped {
    if (!this.contract.instanceIdPattern.hasMatch(instanceId) ||
        !this.contract.channelPattern.hasMatch(channel)) {
      throw ArgumentError('bridge identity does not match the contract');
    }
  }

  final String instanceId;
  final String channel;
  final BridgeContract contract;

  final Set<String> _exchanged = {};
  int _bridgeReadyCount = 0;

  /// `submitting` messages accepted and not yet answered. Each `submitted` /
  /// `submit_failed` answers exactly one of them; a retry starts with a new
  /// `submitting`. Mirrors the engine's `ValidateBridgeSequence`.
  int _openSubmissions = 0;
  bool _disposed = false;

  /// True once the session sent `dispose`.
  bool get disposed => _disposed;

  /// How many valid `bridge_ready` the page sent (a second one is a reload).
  int get bridgeReadyCount => _bridgeReadyCount;

  static const _envelopeKeys = {'type', 'instanceId', 'channel', 'payload'};

  /// Checks one message from the form. Refuses anything that is not exactly
  /// what the contract allows, without echoing it.
  BridgeAcceptance accept(String text) {
    if (_disposed) return const BridgeRefused(BridgeRefusal.afterDispose);
    if (utf8.encode(text).length > contract.maxMessageBytes) {
      return const BridgeRefused(BridgeRefusal.tooLarge);
    }
    final Object? root;
    try {
      root = jsonDecode(text);
    } catch (_) {
      return const BridgeRefused(BridgeRefusal.notJson);
    }
    if (root is! Map<String, dynamic>) {
      return const BridgeRefused(BridgeRefusal.notJson);
    }
    if (root.length != _envelopeKeys.length ||
        !root.keys.every(_envelopeKeys.contains)) {
      return const BridgeRefused(BridgeRefusal.badEnvelope);
    }
    final type = root['type'], id = root['instanceId'];
    final chan = root['channel'], payload = root['payload'];
    if (type is! String ||
        id is! String ||
        chan is! String ||
        payload is! Map<String, dynamic> ||
        !contract.instanceIdPattern.hasMatch(id) ||
        !contract.channelPattern.hasMatch(chan)) {
      return const BridgeRefused(BridgeRefusal.badEnvelope);
    }
    if (id != instanceId) {
      return const BridgeRefused(BridgeRefusal.wrongInstance);
    }
    if (chan != channel) return const BridgeRefused(BridgeRefusal.wrongChannel);
    final spec = contract.messages[type];
    if (spec == null) return const BridgeRefused(BridgeRefusal.unknownType);
    if (spec.direction != BridgeContract._toApp) {
      return const BridgeRefused(BridgeRefusal.wrongDirection);
    }
    if (contract.firstFault(spec, payload) != null) {
      return const BridgeRefused(BridgeRefusal.badPayload);
    }
    if (!_afterSatisfied(spec)) {
      return const BridgeRefused(BridgeRefusal.outOfOrder);
    }
    if (type == 'submitting') {
      _openSubmissions++;
    } else if (type == 'submitted' || type == 'submit_failed') {
      if (_openSubmissions == 0) {
        return const BridgeRefused(BridgeRefusal.outOfOrder);
      }
      _openSubmissions--;
    }
    _exchanged.add(type);
    if (type == 'bridge_ready') _bridgeReadyCount++;
    return BridgeMessage(type, _freeze(payload) as Map<String, Object?>);
  }

  /// The JSON envelope for a message the app sends to the form. Validates
  /// direction, payload and `after` exactly like [accept]; throws [StateError]
  /// naming the rule (never a value, and the type only once it is known to be one
  /// the contract defines) on a violation.
  String encode(String type, Map<String, Object?> payload) {
    if (_disposed) throw StateError('bridge: refused: after dispose');
    final spec = contract.messages[type];
    if (spec == null) throw StateError('bridge: refused: unknown type');
    if (spec.direction != BridgeContract._toRuntime) {
      throw StateError('bridge: $type refused: wrong direction');
    }
    final fault = contract.firstFault(spec, payload);
    if (fault != null) {
      throw StateError('bridge: $type refused: bad payload field $fault');
    }
    if (!_afterSatisfied(spec)) {
      throw StateError('bridge: $type refused: out of order');
    }
    final text = jsonEncode({
      'type': type,
      'instanceId': instanceId,
      'channel': channel,
      'payload': payload,
    });
    if (utf8.encode(text).length > contract.maxMessageBytes) {
      throw StateError('bridge: $type refused: too large');
    }
    _exchanged.add(type);
    if (type == 'dispose') _disposed = true;
    return text;
  }

  bool _afterSatisfied(BridgeMessageSpec spec) =>
      spec.after.isEmpty || spec.after.any(_exchanged.contains);

  static Object? _freeze(Object? v) => switch (v) {
        Map() => Map<String, Object?>.unmodifiable(
            {for (final e in v.entries) e.key as String: _freeze(e.value)}),
        List() => List<Object?>.unmodifiable(v.map(_freeze)),
        _ => v,
      };
}
