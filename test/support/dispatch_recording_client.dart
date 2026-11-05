import 'package:http/http.dart' as http;

/// Records every request in the order the SDK hands it to its HTTP client.
///
/// [send] runs synchronously inside the SDK's call, before any await, so [dispatched] is the
/// SDK's dispatch order — the contract (a slide's view goes out before its click) — and not
/// the order a mock handler happens to run in.
class DispatchRecordingClient extends http.BaseClient {
  final http.Client _inner;
  final List<String> dispatched = [];

  DispatchRecordingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    dispatched.add(request.url.toString());
    return _inner.send(request);
  }
}
