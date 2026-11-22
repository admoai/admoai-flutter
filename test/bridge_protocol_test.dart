import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:admoai/src/interactive/bridge_protocol.dart';
import 'package:admoai/src/interactive/contract/bridge_messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scenarios of `lib/src/interactive/bridge_protocol.feature`, one test per
/// scenario, named after it. `every scenario has a test` holds the binding.
/// Fixtures are the contract pack's, under `test/fixtures/interactive_experience`.
void main() {
  const dir = 'test/fixtures/interactive_experience';
  final scenarios = <String>{};

  void scenario(String title, void Function() body) {
    scenarios.add(title);
    test(title, body);
  }

  final contract = BridgeContract.shipped;
  final context =
      jsonDecode(File('$dir/bridge/context.json').readAsStringSync())
          as Map<String, dynamic>;
  final instanceId = context['instanceId'] as String;
  final channel = context['channel'] as String;

  BridgeSession session() =>
      BridgeSession(instanceId: instanceId, channel: channel);

  /// Raw text of every fixture under `bridge/<sub>`, by file name.
  Map<String, String> files(String sub) {
    final out = <String, String>{};
    final entries = Directory('$dir/bridge/$sub')
        .listSync()
        .whereType<File>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in entries) {
      out[f.uri.pathSegments.last] = f.readAsStringSync();
    }
    return out;
  }

  Map<String, dynamic> decode(String text) =>
      jsonDecode(text) as Map<String, dynamic>;

  final toApp = files('runtime-to-app');
  final toRuntime = files('app-to-runtime');
  final byType = <String, String>{
    for (final t in [...toApp.values, ...toRuntime.values])
      decode(t)['type'] as String: t,
  };

  /// Exchanges, on [s], the messages [type] needs (following the first `after`
  /// entry each time), using the valid fixtures.
  void prime(BridgeSession s, String type) {
    for (final after in contract.messages[type]!.after.take(1)) {
      prime(s, after);
      final text = byType[after]!;
      if (contract.messages[after]!.direction == 'runtime_to_app') {
        expect(s.accept(text), isA<BridgeMessage>(), reason: after);
      } else {
        s.encode(after, Map<String, Object?>.from(decode(text)['payload']));
      }
    }
  }

  BridgeSession primedFor(String type) => session()..let((s) => prime(s, type));

  BridgeRefusal? refusal(BridgeAcceptance a) =>
      a is BridgeRefused ? a.reason : null;

  test('every scenario has a test', () {
    final titles = File('lib/src/interactive/bridge_protocol.feature')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) =>
            l.startsWith('Scenario:') || l.startsWith('Scenario Outline:'))
        .map((l) => l.substring(l.indexOf(':') + 1).trim())
        .toSet();

    expect(titles, isNotEmpty);
    expect(titles, equals(scenarios));
  });

  scenario('Every message the form may send is accepted in its place', () {
    expect(toApp, isNotEmpty);
    toApp.forEach((name, text) {
      final type = decode(text)['type'] as String;
      final s = primedFor(type);
      final got = s.accept(text);
      expect(got, isA<BridgeMessage>(), reason: name);
      got as BridgeMessage;
      expect(got.type, type, reason: name);
      expect(got.payload, decode(text)['payload'], reason: name);
      expect(() => (got.payload as Map).clear(), throwsUnsupportedError);
    });
  });

  scenario('Every message the app may send is built as the contract describes',
      () {
    expect(toRuntime, isNotEmpty);
    toRuntime.forEach((name, text) {
      final fixture = decode(text);
      final type = fixture['type'] as String;
      final s = primedFor(type);
      final sent =
          s.encode(type, Map<String, Object?>.from(fixture['payload'] as Map));
      expect(decode(sent), equals(fixture), reason: name);
    });
  });

  /// Outcome of each invalid fixture, for the unit's report.
  final outcomes = <String, String>{};

  scenario('Messages the contract forbids are refused', () {
    files('invalid/runtime-to-app').forEach((name, text) {
      final type = decode(text)['type'] as String;
      final s = contract.messages.containsKey(type) &&
              contract.messages[type]!.direction == 'runtime_to_app'
          ? primedFor(type)
          : session();
      final got = refusal(s.accept(text));
      expect(got, isNotNull, reason: name);
      outcomes['runtime-to-app/$name'] = 'refused ${got!.name}';
    });
    // Each invalid app-to-runtime fixture starts from an explicit state and
    // must be refused by `encode` for the intended reason. Only the fixtures
    // listed in [envelopeFaults] reach the encoder fine (the app builds its own
    // identity) and are refused by the receiver instead.
    final start = <String, String>{
      // Primed up to just before became_visible, so back is out of order.
      'back-before-visible.json': 'became_visible',
      'back-with-payload.json': 'back',
      'initialize-missing-presentation.json': 'initialize',
      'initialize-unknown-presentation.json': 'initialize',
      'prefill-non-string-value.json': 'prefill',
    };
    final reason = <String, String>{
      'back-before-visible.json': 'out of order',
      'back-with-payload.json': 'bad payload',
      'initialize-missing-presentation.json': 'bad payload',
      'initialize-unknown-presentation.json': 'bad payload',
      'prefill-non-string-value.json': 'bad payload',
      'runtime-message-from-app.json': 'wrong direction',
      'unknown-type.json': 'unknown type',
    };
    // A repeated key cannot survive decoding into a Map, so its raw text is
    // judged through `accept`, like the identity fault.
    const envelopeFaults = {
      'wrong-instance.json': BridgeRefusal.wrongInstance,
      'prefill-repeated-key.json': BridgeRefusal.repeatedKey,
    };
    final invalid = files('invalid/app-to-runtime');
    expect(invalid.keys.toSet(), {...reason.keys, ...envelopeFaults.keys});
    invalid.forEach((name, text) {
      final fixture = decode(text);
      final type = fixture['type'] as String;
      final payload = Map<String, Object?>.from(fixture['payload'] as Map);
      if (envelopeFaults.containsKey(name)) {
        final got = refusal(primedFor(type).accept(text));
        expect(got, envelopeFaults[name], reason: name);
        outcomes['app-to-runtime/$name'] = 'receiver refuses ${got!.name}';
        return;
      }
      final s = start.containsKey(name) ? primedFor(start[name]!) : session();
      expect(
          () => s.encode(type, payload),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains(reason[name]!))),
          reason: name);
      outcomes['app-to-runtime/$name'] = 'encode refuses: ${reason[name]}';
    });
    expect(outcomes, isNotEmpty);
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(outcomes));
  });

  scenario('Prefill the form would only partly accept is never sent', () {
    final tolerated = files('tolerated/app-to-runtime');
    final fixtures = tolerated.keys.where((n) => !n.endsWith('.outcome.json'));
    expect(fixtures.toSet(), {
      'integer-like-key.json',
      'mixed-entries.json',
      'oversized-value.json',
      'unknown-prefill-key.json',
    });
    for (final name in fixtures) {
      // The form's own behaviour is described by the sibling outcome; the SDK
      // only has to never send what the form would have to drop.
      expect(tolerated.containsKey(name.replaceFirst('.json', '.outcome.json')),
          isTrue,
          reason: '$name has no outcome');
      final fixture = decode(tolerated[name]!);
      final s = primedFor('prefill');
      expect(
          () => s.encode(fixture['type'] as String,
              Map<String, Object?>.from(fixture['payload'] as Map)),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('bad payload'))),
          reason: name);
      // Refused, so nothing was recorded: the same session still prefills.
      expect(
          s.encode('prefill', {
            'values': {'email': 'alex@example.invalid'}
          }),
          contains('prefill'),
          reason: name);
    }
  });

  scenario('An oversized message is refused before it is read', () {
    final text = toApp['event.json']!;
    final padding =
        'x' * (contract.maxMessageBytes + 1 - utf8.encode(text).length);
    final big = text + padding;
    expect(utf8.encode(big).length, contract.maxMessageBytes + 1);
    expect(refusal(session().accept(big)), BridgeRefusal.tooLarge);
    // Counted in bytes, not characters: multi-byte text under the limit in
    // characters but over it in bytes is refused too.
    final wide = '€' * (contract.maxMessageBytes ~/ 3 + 1);
    expect(wide.length, lessThan(contract.maxMessageBytes));
    expect(refusal(session().accept(wide)), BridgeRefusal.tooLarge);
    expect(
        refusal(session().accept(
            files('invalid/runtime-to-app')['oversized-message.json']!)),
        BridgeRefusal.tooLarge);
  });

  scenario('A message that repeats a key is refused', () {
    final base = toApp['activated.json']!;
    BridgeRefusal? of(String text) =>
        refusal(primedFor('activated').accept(text));
    String edit(String from, String to) {
      expect(base, contains(from));
      return base.replaceFirst(from, to);
    }

    expect(of(base), isNull);
    // Envelope.
    expect(
        of(edit('"type": "activated",',
            '"type": "activated", "type": "activated",')),
        BridgeRefusal.repeatedKey);
    // Payload.
    expect(of(edit('"formVersionId":', '"events": [], "formVersionId":')),
        BridgeRefusal.repeatedKey);
    // An object nested in an array (events[1]).
    expect(
        of(edit('"name": "form_start",',
            '"url": "https://a.example.invalid/x", "name": "form_start",')),
        BridgeRefusal.repeatedKey);
    // Escaped spelling of the same key.
    expect(
        of(edit(
            '"type": "activated",', r'"type": "activated", "t\u0079pe": "x",')),
        BridgeRefusal.repeatedKey);
    // The same name in sibling objects of an array (`name` in each events[])
    // and in an outer and an inner object is not a repeat. These bodies fail
    // later, for their payload, so the reason must not be repeatedKey.
    String raw(String payload) =>
        '{"type":"activated","instanceId":"$instanceId","channel":"$channel",'
        '"payload":$payload}';
    expect(of(raw('{"a":{"a":1},"b":[{"a":1},{"a":2}]}')),
        BridgeRefusal.badPayload);
    expect(of(raw('{"a":{"a":1},"b":[{"a":1},{"a":2}],"a":3}')),
        BridgeRefusal.repeatedKey);
    // A string value that looks like a repeated key is not one.
    expect(of(raw('{"a":"a","b":"a"}')), BridgeRefusal.badPayload);
  });

  scenario('A timestamp that is not a real moment is refused', () {
    BridgeSession open() =>
        primedFor('submitted')..accept(toApp['submitting.json']!);
    String submitted(String at) {
      final m = decode(toApp['submitted.json']!);
      (m['payload'] as Map)['submittedAt'] = at;
      return jsonEncode(m);
    }

    for (final bad in [
      '2026-02-30T15:04:05Z',
      '2027-02-29T15:04:05Z',
      '2100-02-29T15:04:05Z',
      '2026-13-01T15:04:05Z',
      '2026-00-10T15:04:05Z',
      '2026-04-31T15:04:05Z',
      '2026-11-12T24:00:00Z',
      '2026-11-12T23:59:60Z',
      '2026-11-12T23:60:00Z',
      '2026-11-12T15:04:05+24:00',
      '2026-11-12T15:04:05+05:60',
    ]) {
      expect(refusal(open().accept(submitted(bad))), BridgeRefusal.badPayload,
          reason: bad);
    }
    for (final good in [
      '2026-11-12T15:04:05Z',
      '2028-02-29T15:04:05Z',
      '2000-02-29T15:04:05Z',
      '2026-11-12T23:59:59Z',
      '2026-11-12T15:04:05.123456Z',
      '2026-11-12T15:04:05+02:00',
      '2026-11-12T15:04:05-05:30',
    ]) {
      expect(open().accept(submitted(good)), isA<BridgeMessage>(),
          reason: good);
    }
  });

  scenario('A message the app builds that is over the size limit is not sent',
      () {
    // 4096 code points (the token's limit) of four UTF-8 bytes each.
    final token = '😀' * 4096;
    final s = primedFor('initialize');
    expect(
        () => s.encode('initialize',
            {'preparationToken': token, 'presentation': 'inline'}),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('initialize'))
            .having((e) => e.message, 'message', contains('too large'))
            .having((e) => e.message, 'message', isNot(contains('😀')))));
    // The session is as it was: not disposed, and the same encode works.
    expect(s.disposed, isFalse);
    final valid = decode(byType['initialize']!)['payload'] as Map;
    expect(s.encode('initialize', Map<String, Object?>.from(valid)),
        contains('initialize'));
    expect(s.accept(toApp['prepared.json']!), isA<BridgeMessage>());
  });

  scenario('A message for another form instance or channel is refused', () {
    final text = toApp['bridge-ready.json']!;
    final other = decode(text);
    other['instanceId'] = 'form_instance_01KG000000000000000000N999';
    expect(refusal(session().accept(jsonEncode(other))),
        BridgeRefusal.wrongInstance);
    final elsewhere = decode(text);
    elsewhere['channel'] = 'chan_example_0000000002';
    expect(refusal(session().accept(jsonEncode(elsewhere))),
        BridgeRefusal.wrongChannel);
    // A malformed identity is an envelope fault, not a mismatch.
    final broken = decode(text)..['channel'] = 'short';
    expect(refusal(session().accept(jsonEncode(broken))),
        BridgeRefusal.badEnvelope);
  });

  scenario('A message out of order is refused', () {
    final s = session();
    expect(
        refusal(s.accept(toApp['submitted.json']!)), BridgeRefusal.outOfOrder);
    expect(
        refusal(s.accept(toApp['submitting.json']!)), BridgeRefusal.outOfOrder);
    expect(
        refusal(s.accept(toApp['prepared.json']!)), BridgeRefusal.outOfOrder);
    expect(() => s.encode('prefill', {'values': <String, String>{}}),
        throwsStateError);
    expect(() => s.encode('activate', <String, Object?>{}), throwsStateError);
    // Refused messages are not recorded: still nothing exchanged.
    expect(
        refusal(s.accept(toApp['submitted.json']!)), BridgeRefusal.outOfOrder);
    expect(s.accept(toApp['bridge-ready.json']!), isA<BridgeMessage>());
    expect(s.bridgeReadyCount, 1);
    // A repeated bridge_ready is allowed and counted: the reload rule is the controller's.
    expect(s.accept(toApp['bridge-ready.json']!), isA<BridgeMessage>());
    expect(s.bridgeReadyCount, 2);
  });

  scenario('A submit answer with no open submitting is refused', () {
    BridgeSession visible() => primedFor('submitting');
    expect(refusal(visible().accept(toApp['submitted.json']!)),
        BridgeRefusal.outOfOrder);
    expect(refusal(visible().accept(toApp['submit-failed.json']!)),
        BridgeRefusal.outOfOrder);

    // The earlier submitting was already answered.
    final answered = visible();
    expect(answered.accept(toApp['submitting.json']!), isA<BridgeMessage>());
    expect(answered.accept(toApp['submit-failed.json']!), isA<BridgeMessage>());
    expect(refusal(answered.accept(toApp['submitted.json']!)),
        BridgeRefusal.outOfOrder);
    // A refusal never changes the count: a new submitting still opens one.
    expect(answered.accept(toApp['submitting.json']!), isA<BridgeMessage>());
    expect(answered.accept(toApp['submitted.json']!), isA<BridgeMessage>());

    // A retry starts with a new submitting.
    final retry = visible();
    expect(retry.accept(toApp['submitting.json']!), isA<BridgeMessage>());
    expect(retry.accept(toApp['submit-failed.json']!), isA<BridgeMessage>());
    expect(retry.accept(toApp['submitting.json']!), isA<BridgeMessage>());
    expect(retry.accept(toApp['submitted.json']!), isA<BridgeMessage>());
  });

  scenario('A failed submit names a reason the app accepts', () {
    for (final code in [
      'unauthorized',
      'form_not_available',
      'invalid_request'
    ]) {
      final s = primedFor('submitting');
      expect(s.accept(toApp['submitting.json']!), isA<BridgeMessage>());
      final failed = decode(toApp['submit-failed.json']!);
      (failed['payload'] as Map)['errorCode'] = code;
      expect(s.accept(jsonEncode(failed)), isA<BridgeMessage>(), reason: code);
    }
  });

  scenario('A page speaking an unknown bridge version gets no answer', () {
    final s = session();
    final text =
        files('invalid/runtime-to-app')['unknown-bridge-version.json']!;
    expect(decode(text)['payload']['bridgeVersion'], '2');
    expect(refusal(s.accept(text)), BridgeRefusal.badPayload);
    expect(s.bridgeReadyCount, 0);
    expect(
        () => s.encode('initialize', {
              'preparationToken': 't',
              'presentation': 'inline',
            }),
        throwsStateError);
  });

  scenario('Hostile text crosses the bridge as data', () {
    const hostile = 'a"b\\c</script><img src=x onerror=1>  😀\n\r\t\u0000end';
    final s = primedFor('prefill');
    final text = s.encode('prefill', {
      'values': {'fullName': hostile},
    });
    expect(decode(text)['payload']['values']['fullName'], hostile);
    expect(decode(text).keys.toSet(),
        {'type', 'instanceId', 'channel', 'payload'});
    // 256 code points (each an emoji of two UTF-16 units) is the limit.
    final atLimit = '😀' * 256;
    expect(
        primedFor('prefill').encode('prefill', {
          'values': {'fullName': atLimit}
        }),
        contains('prefill'));
    final over = '😀' * 257;
    expect(
        () => primedFor('prefill').encode('prefill', {
              'values': {'fullName': over}
            }),
        throwsStateError);
    // Not a catalog key, and gender outside the catalog's options.
    expect(
        () => primedFor('prefill').encode('prefill', {
              'values': {'homeAddress': 'x'}
            }),
        throwsStateError);
    expect(
        () => primedFor('prefill').encode('prefill', {
              'values': {'gender': 'other-thing'}
            }),
        throwsStateError);
  });

  scenario('Nothing is accepted after dispose', () {
    final s = primedFor('dispose');
    expect(s.accept(toApp['bridge-ready.json']!), isA<BridgeMessage>());
    s.encode('dispose', <String, Object?>{});
    expect(s.disposed, isTrue);
    for (final text in toApp.values) {
      expect(refusal(s.accept(text)), BridgeRefusal.afterDispose);
    }
    expect(refusal(s.accept('not json')), BridgeRefusal.afterDispose);
    expect(() => s.encode('dispose', <String, Object?>{}), throwsStateError);
    // The refusal after dispose never echoes the caller's type.
    expect(
        () => s.encode('SECRET-VALUE-9f3a', {}),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            isNot(contains('SECRET-VALUE-9f3a')))));
  });

  scenario('A refusal never contains message content', () {
    const secret = 'SECRET-VALUE-9f3a';
    final attempts = <String>[
      'not json $secret',
      jsonEncode([secret]),
      jsonEncode({'type': secret}),
      jsonEncode({
        'type': 'event',
        'instanceId': instanceId,
        'channel': channel,
        'payload': {'name': secret},
      }),
      jsonEncode({
        'type': secret,
        'instanceId': instanceId,
        'channel': channel,
        'payload': {},
      }),
      jsonEncode({
        'type': 'bridge_ready',
        'instanceId': secret,
        'channel': channel,
        'payload': {},
      }),
      jsonEncode({
        'type': 'activate',
        'instanceId': instanceId,
        'channel': channel,
        'payload': {secret: secret},
      }),
      'x' * (contract.maxMessageBytes + 1),
    ];
    for (final a in attempts) {
      final got = session().accept(a);
      expect(got, isA<BridgeRefused>());
      expect(got.toString(), isNot(contains(secret)));
      expect(got.toString(), isNot(contains('xxxx')));
    }
    final s = primedFor('prefill');
    for (final call in <void Function()>[
      () => s.encode(secret, {}),
      () => s.encode('prefill', {
            'values': {secret: secret}
          }),
      () => s.encode('prefill', {
            'values': {'fullName': 1},
            secret: secret
          }),
      () => s.encode(
          'initialize', {'preparationToken': secret, 'presentation': secret}),
    ]) {
      try {
        call();
        fail('expected a StateError');
      } on StateError catch (e) {
        expect(e.toString(), isNot(contains(secret)));
      }
    }
  });

  scenario('Channels are unguessable and valid', () {
    final seen = <String>{};
    for (var i = 0; i < 1000; i++) {
      final c = mintBridgeChannel();
      expect(c.length, 32);
      expect(contract.channelPattern.hasMatch(c), isTrue);
      seen.add(c);
    }
    expect(seen.length, 1000);
    expect(mintBridgeChannel(Random(1)), mintBridgeChannel(Random(1)));
  });

  scenario('The shipped contract is the shared contract', () {
    expect(bridgeMessagesJson,
        File('$dir/bridge-messages.json').readAsStringSync());
    expect(standardFieldsJson,
        File('$dir/standard-fields.json').readAsStringSync());
    expect(contract.maxMessageBytes, 16384);
    expect(contract.messages.length, 20);
    expect(contract.prefillKeys, contains('email'));

    final changed = decode(bridgeMessagesJson);
    final message = (changed['messages'] as List)
        .firstWhere((m) => (m as Map)['type'] == 'initialize') as Map;
    ((message['payload'] as Map)['presentation'] as Map)['type'] = 'ip_address';
    expect(() => BridgeContract.parse(jsonEncode(changed), standardFieldsJson),
        throwsStateError);

    final nested = decode(bridgeMessagesJson);
    final activated = (nested['messages'] as List)
        .firstWhere((m) => (m as Map)['type'] == 'activated') as Map;
    ((((activated['payload'] as Map)['events'] as Map)['items'] as Map)['url']
        as Map)['type'] = 'ip_address';
    expect(() => BridgeContract.parse(jsonEncode(nested), standardFieldsJson),
        throwsStateError);
  });
}

extension _Let<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
