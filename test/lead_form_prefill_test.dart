import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/interactive/bridge_protocol.dart';
import 'package:admoai/src/interactive/contract/bridge_messages.g.dart';
import 'package:admoai/src/interactive/lead_form_prefill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lead_form_support.dart';

/// The scenarios of `lib/src/interactive/lead_form_prefill.feature`, one test per
/// scenario, named after it, plus the contract-number and pure-prefill checks
/// they rest on. Time is a fake: no test waits for the real lookup time.
void main() {
  final scenarios = <String>{};

  void scenario(String title, Future<void> Function() body) {
    scenarios.add(title);
    test(title, body);
  }

  final fixtures = leadFormBridgeFixtures();
  final contract = BridgeContract.shipped;
  final beforeExpiry = DateTime.utc(2026, 11, 12, 15, 0);

  LeadGenerationExperience descriptor() =>
      InteractiveExperience.tryFromJson(leadFormDescriptorJson())
          as LeadGenerationExperience;

  FakeRig rig(LeadFormValueProvider provider) =>
      FakeRig(descriptor(), fixtures, beforeExpiry, provider: provider);

  Future<void> prepared(FakeRig r) async {
    await r.controller.prepare();
    r.say('bridge_ready');
    r.say('prepared');
  }

  /// Opens the form and plays the page's `activated` requesting [keys].
  Future<void> activate(FakeRig r, List<String> keys) async {
    await prepared(r);
    await r.controller.open();
    r.say('activated', {'requestedAttributeKeys': keys});
  }

  Map<String, dynamic> prefillValues(FakeRig r) =>
      (r.surface.posts.singleWhere((p) => p['type'] == 'prefill')['payload']
          as Map)['values'] as Map<String, dynamic>;

  ScriptedProvider answering(Map<StandardAttributeKey, String> held) =>
      ScriptedProvider(
        (keys) async => {
          for (final e in held.entries)
            if (keys.contains(e.key)) e.key: e.value,
        },
        keys: held.keys.toSet(),
      );

  test('every scenario has a test', () {
    final titles = File('lib/src/interactive/lead_form_prefill.feature')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('Scenario:'))
        .map((l) => l.substring('Scenario:'.length).trim())
        .toSet();

    expect(titles, isNotEmpty);
    expect(titles, equals(scenarios));
  });

  scenario('the app is asked only for the keys the activated form requests',
      () async {
    final p = answering({
      StandardAttributeKey.firstName: 'Alex',
      StandardAttributeKey.email: 'alex@example.invalid',
      StandardAttributeKey.phone: '+15550100',
    });
    final r = rig(p);

    await activate(r, ['fullName', 'email']);
    await pumpEventQueue();

    expect(p.asked, [
      {StandardAttributeKey.fullName, StandardAttributeKey.email}
    ]);
    expect(prefillValues(r), {'email': 'alex@example.invalid'});
  });

  scenario('the app is never asked before activation', () async {
    final p = answering({StandardAttributeKey.email: 'alex@example.invalid'});
    final r = rig(p);

    await prepared(r);
    expect(p.asked, isEmpty);
    await r.controller.open();
    expect(p.asked, isEmpty);
    expect(r.sent, isNot(contains('prefill')));
  });

  scenario(
      'a form that requests no key is prefilled with nothing, without asking the app',
      () async {
    final p = answering({StandardAttributeKey.email: 'alex@example.invalid'});
    final r = rig(p);

    await activate(r, []);

    expect(p.asked, isEmpty);
    expect(prefillValues(r), isEmpty);
  });

  scenario('a slow app does not hold the form back', () async {
    final pending = Completer<Map<StandardAttributeKey, String>>();
    final p = ScriptedProvider((_) => pending.future);
    final r = rig(p);

    await activate(r, ['fullName', 'email']);
    r.timers.advance(contract.prefillLookupTimeoutMs - 1);
    expect(r.sent, isNot(contains('prefill')));
    r.timers.advance(1);
    expect(prefillValues(r), isEmpty);

    pending.complete({StandardAttributeKey.email: 'late@example.invalid'});
    await pumpEventQueue();
    expect(r.sent.where((t) => t == 'prefill'), hasLength(1));
  });

  scenario('an app that fails leaves the fields empty', () async {
    const secret = 'secret@example.invalid';
    for (final answer in <Future<Map<StandardAttributeKey, String>> Function(
        Set<StandardAttributeKey>)>[
      (_) => throw StateError(secret),
      (_) async => throw StateError(secret),
    ]) {
      final r = rig(ScriptedProvider(answer));

      await activate(r, ['fullName', 'email']);
      await pumpEventQueue();

      expect(prefillValues(r), isEmpty);
      expect(r.logs, ['Lead Generation value lookup failed: StateError']);
      expect(r.logs.join(), isNot(contains(secret)));
    }
  });

  scenario('values the contract does not allow are left out', () async {
    final tooLong = '1' * (contract.prefillValueMaxLength + 1);
    final r = rig(ScriptedProvider((_) async => {
          StandardAttributeKey.email: '   ',
          StandardAttributeKey.phone: tooLong,
          StandardAttributeKey.gender: 'not-an-option',
          StandardAttributeKey.firstName: 'Alex',
        }));

    await activate(r, ['email', 'phone', 'gender']);
    await pumpEventQueue();

    expect(prefillValues(r), isEmpty);
  });

  scenario('a value with quotes, newlines and Unicode reaches the form as data',
      () async {
    const name = 'Alex "Al" O\'Neil\nMorgan \u{1F600}';
    final r = rig(answering({StandardAttributeKey.fullName: name}));

    await activate(r, ['fullName']);
    await pumpEventQueue();

    expect(prefillValues(r), {'fullName': name});
  });

  scenario('the controller and its state never show a prefilled value',
      () async {
    const email = 'alex.private@example.invalid';
    final r = rig(answering({StandardAttributeKey.email: email}));

    await activate(r, ['email']);
    await pumpEventQueue();
    r.say('prefill_applied');

    expect(prefillValues(r), {'email': email});
    final shown = [r.controller.toString(), r.state.toString(), ...r.logs];
    for (final t in shown) {
      expect(t, isNot(contains(email)));
      expect(t, isNot(contains('alex.private')));
    }
  });

  group('beyond the scenarios', () {
    test('the contract numbers are the ones of the vendored JSON', () {
      final bridge = jsonDecode(bridgeMessagesJson) as Map<String, dynamic>;
      final fields = jsonDecode(standardFieldsJson) as Map<String, dynamic>;
      expect(contract.maxHiddenPreparedForms, bridge['maxHiddenPreparedForms']);
      expect(contract.prefillLookupTimeoutMs, bridge['prefillLookupTimeoutMs']);
      final prefill = (bridge['messages'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((m) => m['type'] == 'prefill');
      expect(contract.prefillValueMaxLength,
          (prefill['payload']['values'] as Map)['maxLength']);
      expect(contract.genderValues, {
        for (final o in fields['genderOptions'] as List) (o as Map)['value'],
      });
    });

    test(
        'the prefill keeps requested, trimmed, allowed values in catalog order',
        () {
      final gender = contract.genderValues.first;
      final shown = leadFormPrefillValues(
        {
          StandardAttributeKey.gender: ' $gender ',
          StandardAttributeKey.email: ' a@b.invalid ',
          StandardAttributeKey.phone: '+1',
        },
        {StandardAttributeKey.gender, StandardAttributeKey.email},
        contract,
      );
      expect(shown.keys.toList(), ['email', 'gender']);
      expect(shown, {'email': 'a@b.invalid', 'gender': gender});
      expect(
          leadFormPrefillValues(null, {StandardAttributeKey.email}, contract),
          isEmpty);
    });

    test('the length bound counts code points, not UTF-16 units', () {
      final max = contract.prefillValueMaxLength;
      final atBound = '\u{1F600}' * max;
      final over = '\u{1F600}' * (max + 1);
      final shown = leadFormPrefillValues(
        {StandardAttributeKey.fullName: atBound},
        {StandardAttributeKey.fullName},
        contract,
      );
      expect(shown['fullName'], atBound);
      expect(
          leadFormPrefillValues({StandardAttributeKey.fullName: over},
              {StandardAttributeKey.fullName}, contract),
          isEmpty);
    });
  });
}
