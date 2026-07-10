import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

const baseUrl = 'https://mock.api.admoai.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  hierarchicalLoggingEnabled = true;

  setUp(() {
    const MethodChannel channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getLocalTimezone') return 'UTC';
      return null;
    });
  });

  Future<AdMoai> newSdk({String? sessionId}) {
    return AdMoai.initialize(
      config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
      sessionId: sessionId,
    );
  }

  group('Journey request context — serialization', () {
    test('backward compatible: no Journey fields in body', () async {
      final sdk = await newSdk();
      final request = sdk.createRequestBuilder().addPlacement(key: 'home').build();
      final json = request.toJson();

      expect(json.containsKey('sessionId'), isFalse);
      expect(json.containsKey('journeyOpt'), isFalse);
      expect(request.sessionId, isNull);
      expect(request.journeyOpt, isNull);
    });

    test('sessionId and journeyOpt are top-level and correctly cased', () async {
      final sdk = await newSdk();
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setSessionId('sess_abc')
          .setJourneyOpt(JourneyOpt.optIn)
          .build();
      final json = request.toJson();

      expect(json['sessionId'], equals('sess_abc'));
      expect(json['journeyOpt'], equals('in'));
    });

    test('journeyOpt only serializes engine literals in/out', () async {
      final sdk = await newSdk();
      final inReq = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setJourneyOpt(JourneyOpt.optIn)
          .build();
      final outReq = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setJourneyOpt(JourneyOpt.optOut)
          .build();

      expect(inReq.toJson()['journeyOpt'], equals('in'));
      expect(outReq.toJson()['journeyOpt'], equals('out'));
      expect(JourneyOpt.optIn.value, equals('in'));
      expect(JourneyOpt.optOut.value, equals('out'));
    });

    test('blank sessionId is omitted from the wire', () async {
      final sdk = await newSdk();
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setSessionId('   ')
          .build();

      expect(request.toJson().containsKey('sessionId'), isFalse);
    });

    test('sessionId is trimmed on the wire', () async {
      final sdk = await newSdk();
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setSessionId('  sess_trim  ')
          .build();

      expect(request.toJson()['sessionId'], equals('sess_trim'));
    });

    test('over-length sessionId (>256 bytes) is sent as-is, not truncated',
        () async {
      final sdk = await newSdk();
      final long = 'x' * 300;
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setSessionId(long)
          .build();

      expect(request.toJson()['sessionId'], equals(long));
      expect((request.toJson()['sessionId'] as String).length, equals(300));
    });
  });

  group('Journey session guardrail — PII-safe warnings', () {
    test('over-length and blank warn with reason token only, never the value',
        () async {
      final records = <LogRecord>[];
      final logger = Logger('journey-test-warn')
        ..level = Level.ALL
        ..onRecord.listen(records.add);
      final sdk = await AdMoai.initialize(
        config: SDKConfig(baseUrl: baseUrl, logger: logger),
      );

      final secret = 'y' * 300; // the raw value must never be logged
      sdk.setSessionId(secret);
      sdk.setSessionId('   ');

      final warnings =
          records.where((r) => r.level >= Level.WARNING).toList();
      expect(warnings.length, equals(2));
      expect(warnings[0].message, contains('exceeds_256_bytes'));
      expect(warnings[1].message, contains('blank_after_trim'));
      for (final w in warnings) {
        expect(w.message.contains(secret), isFalse,
            reason: 'raw sessionId (PII) must never appear in logs');
      }
    });

    test('valid sessionId does not warn', () async {
      final records = <LogRecord>[];
      final logger = Logger('journey-test-ok')
        ..level = Level.ALL
        ..onRecord.listen(records.add);
      final sdk = await AdMoai.initialize(
        config: SDKConfig(baseUrl: baseUrl, logger: logger),
      );

      sdk.setSessionId('sess_ok');

      expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
    });

    test('journeySessionIdRejectionReason classifies by UTF-8 bytes', () {
      expect(journeySessionIdRejectionReason('ok'), isNull);
      expect(journeySessionIdRejectionReason('   '), equals('blank_after_trim'));
      expect(journeySessionIdRejectionReason('x' * 256), isNull);
      expect(journeySessionIdRejectionReason('x' * 257),
          equals('exceeds_256_bytes'));
      // Multi-byte: 200 emoji = 800 bytes > 256 even though 200 runes.
      expect(journeySessionIdRejectionReason('😀' * 200),
          equals('exceeds_256_bytes'));
    });
  });

  group('Journey sticky session', () {
    test('sticky session inherited by builders, rotatable, overridable',
        () async {
      final sdk = await newSdk();

      sdk.setSessionId('sess_1');
      var request = sdk.createRequestBuilder().addPlacement(key: 'p').build();
      expect(request.toJson()['sessionId'], equals('sess_1'));

      // Rotate.
      sdk.setSessionId('sess_2');
      request = sdk.createRequestBuilder().addPlacement(key: 'p').build();
      expect(request.toJson()['sessionId'], equals('sess_2'));

      // Per-request override wins.
      request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setSessionId('sess_override')
          .build();
      expect(request.toJson()['sessionId'], equals('sess_override'));

      // clearSessionId removes the sticky default.
      sdk.clearSessionId();
      request = sdk.createRequestBuilder().addPlacement(key: 'p').build();
      expect(request.toJson().containsKey('sessionId'), isFalse);
    });

    test('initialize(sessionId:) seeds the sticky default', () async {
      final sdk = await newSdk(sessionId: 'sess_init');
      final request =
          sdk.createRequestBuilder().addPlacement(key: 'p').build();
      expect(request.toJson()['sessionId'], equals('sess_init'));
    });
  });

  group('setSessionId normalization (field matches wire)', () {
    test('blank sessionId → field is null and key omitted', () async {
      final sdk = await newSdk();
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setSessionId('   ')
          .build();

      expect(request.sessionId, isNull,
          reason: 'field must reflect the wire (no session)');
      expect(request.toJson().containsKey('sessionId'), isFalse);
    });

    test('valid sessionId → field trimmed and equals wire value', () async {
      final sdk = await newSdk();
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'p')
          .setSessionId('  sess_x  ')
          .build();

      expect(request.sessionId, equals('sess_x'));
      expect(request.toJson()['sessionId'], equals('sess_x'));
    });

    test('sticky setSessionId(blank) disables session consistently', () async {
      final sdk = await newSdk(sessionId: 'sess_1');
      sdk.setSessionId('   ');
      final request =
          sdk.createRequestBuilder().addPlacement(key: 'p').build();
      expect(request.sessionId, isNull);
      expect(request.toJson().containsKey('sessionId'), isFalse);
    });
  });

  group('clearAll Journey semantics', () {
    test('clearAll clears per-request journeyOpt but preserves sticky sessionId',
        () async {
      final sdk = await newSdk(sessionId: 'sess_sticky');
      final builder = sdk.createRequestBuilder()
        ..addPlacement(key: 'p')
        ..setJourneyOpt(JourneyOpt.optOut);

      builder.clearAll();
      builder.addPlacement(key: 'p2'); // reuse after reset

      final json = builder.build().toJson();
      // journeyOpt must NOT leak across the reset.
      expect(json.containsKey('journeyOpt'), isFalse);
      // sticky sessionId is intentionally preserved.
      expect(json['sessionId'], equals('sess_sticky'));
    });

    test('clearSessionId drops the sticky session', () async {
      final sdk = await newSdk(sessionId: 'sess_sticky');
      final builder = sdk.createRequestBuilder()..addPlacement(key: 'p');
      builder.clearSessionId();
      expect(builder.build().toJson().containsKey('sessionId'), isFalse);
    });
  });

  group('Journey request — full body shape', () {
    test('serialized body carries top-level keys with a placement', () async {
      final sdk = await newSdk();
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'in_ride_map_banner')
          .setSessionId('sess_123')
          .setJourneyOpt(JourneyOpt.optIn)
          .build();

      final encoded = jsonDecode(jsonEncode(request.toJson()))
          as Map<String, dynamic>;
      expect(encoded['sessionId'], equals('sess_123'));
      expect(encoded['journeyOpt'], equals('in'));
      expect((encoded['placements'] as List).first['key'],
          equals('in_ride_map_banner'));
    });
  });
}
