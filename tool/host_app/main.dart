// B5-flutter QA host app. NEVER committed: it replaces build/host_app/lib/main.dart after
// `tool/host_app.sh build/host_app`. Same SDK calls as tool/host_app/main.dart, plus what the QA
// run needs: a placement switch, a Send button that calls requestAds and logs the engine's answer
// (logcat tag "flutter", lines starting "B5QA"), and the manual / clear / reset / disable steps.
//
// Defines:
//   ADMOAI_BASE_URL  engine URL from the emulator (default http://10.0.2.2:43202, the b5fl instance)
//   QA_AUDIENCE      on (default) | off — off = an integration that never adopted audience signals
//   QA_PLACEMENT     sdk_e2e_audience (default) | sdk_e2e_audience_segments
import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Logs the exact body the SDK puts on the wire (logcat: "B5QA wire ...").
class WireLog extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request && request.url.path.contains('decision')) {
      debugPrint('B5QA wire ${request.method} ${request.url.path} ${request.body}');
    }
    return _inner.send(request);
  }
}

const String baseUrl = String.fromEnvironment(
  'ADMOAI_BASE_URL',
  defaultValue: 'http://10.0.2.2:43202',
);
const bool audienceOn =
    String.fromEnvironment('QA_AUDIENCE', defaultValue: 'on') != 'off';
const String placement = String.fromEnvironment(
  'QA_PLACEMENT',
  defaultValue: 'sdk_e2e_audience',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = await AdMoai.initialize(
    config: SDKConfig(
      baseUrl: baseUrl,
      apiVersion: '2025-11-01',
      collectDeviceSignals: audienceOn,
    ),
    httpClient: WireLog(),
  );
  runApp(MaterialApp(home: QaPage(sdk: sdk)));
}

class QaPage extends StatefulWidget {
  const QaPage({super.key, required this.sdk});
  final AdMoai sdk;
  @override
  State<QaPage> createState() => _QaPageState();
}

class _QaPageState extends State<QaPage> {
  bool disableDevice = false;
  String result = '-';

  DecisionRequest buildRequest() {
    final b = widget.sdk.createRequestBuilder()..addPlacement(key: placement);
    if (audienceOn) {
      b
        ..setAgeGroup(AgeGroup.age25To34)
        ..setActivityFrequency30d(ActivityFrequency30d.zero)
        ..setPublisherSegments(
            ['airport_commuter', 'airport_commuter', 'beach_goer']);
    }
    if (disableDevice) b.disableDeviceCollection();
    return b.build();
  }

  void log(String s) {
    debugPrint('B5QA $s');
    setState(() => result = s);
  }

  Future<void> send() async {
    final request = buildRequest();
    try {
      final r = await widget.sdk.requestAds(request);
      final data = r.body.data ?? [];
      final n = data.isEmpty ? 0 : (data.first.creatives?.length ?? 0);
      log('response ${r.response.statusCode} creatives=$n placement=$placement');
    } on ValidationError catch (e) {
      log('ValidationError ${e.errors.map((x) => '${x.code}: ${x.message}').join(' | ')}');
    } on APIError catch (e) {
      log('APIError ${e.message}');
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.sdk.deviceConfig;
    final json =
        const JsonEncoder.withIndent('  ').convert(buildRequest().toJson());
    Widget btn(String label, VoidCallback f) => Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: ElevatedButton(onPressed: f, child: Text(label)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('B5 Flutter QA')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Base URL: $baseUrl  ·  placement: $placement'),
          Text('Audience signals: ${audienceOn ? 'on' : 'off'}'
              '${disableDevice ? '  ·  device collection DISABLED' : ''}'),
          Text('carrier: ${device.carrier ?? '-'}   category: ${device.category?.value ?? '-'}',
              key: const Key('device-values'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Result: $result',
              key: const Key('result'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(children: [
            btn('Send', send),
            btn('Manual " Example Mobile "/tablet', () {
              widget.sdk.setDeviceConfig(
                  carrier: '  Example Mobile ', category: DeviceCategory.tablet);
              log('manual set');
            }),
            btn('Manual carrier WiFi', () {
              widget.sdk.setDeviceConfig(carrier: 'WiFi');
              log('manual WiFi');
            }),
            btn('Clear', () {
              widget.sdk.clearDeviceConfig();
              log('cleared');
            }),
            btn('Reset', () async {
              await widget.sdk.resetDeviceConfig();
              log('reset');
            }),
            btn(disableDevice ? 'Enable device' : 'Disable device', () {
              setState(() => disableDevice = !disableDevice);
            }),
            btn('Refresh view', () => setState(() {})),
          ]),
          const SizedBox(height: 8),
          SelectableText(json, key: const Key('request-json')),
        ],
      ),
    );
  }
}
