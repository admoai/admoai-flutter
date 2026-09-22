import 'dart:async';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:logging/logging.dart';

import 'models/decision_response.dart';

/// The event a `fireImpression`/`fireClick` invocation reports, used to select
/// which third-party trackers fan out. Internal: publishers never address
/// trackers directly.
sealed class ThirdPartyTrackerEvent {
  const ThirdPartyTrackerEvent();
}

class ThirdPartyImpressionEvent extends ThirdPartyTrackerEvent {
  const ThirdPartyImpressionEvent();
}

class ThirdPartyClickEvent extends ThirdPartyTrackerEvent {
  final String key;
  const ThirdPartyClickEvent(this.key);
}

/// Credential-isolated dispatcher for third-party event trackers (E06 of the
/// Third-party Event Trackers mission).
///
/// Agencies count these GETs on their own ad servers, so the dispatch contract
/// is strict:
/// - **Own HTTP client**, fully separate from the SDK client used for Admoai
///   API calls: no `User-Agent: AdMoaiSDK/…`, no `X-Decision-Version`/
///   `X-Tracking-Version`, no `Accept-Language`, no auth, and no cookies
///   (`dart:io` keeps no cookie jar for `http` requests).
/// - **GET only**, requesting the stored URL byte-for-byte. A URL the
///   platform's `Uri` cannot round-trip byte-identically (e.g. a raw
///   `%%MACRO%%`, an invalid percent-sequence) is discarded at validation —
///   firing normalized/re-encoded bytes would corrupt what the agency counts.
/// - **3xx terminal**: `followRedirects` is disabled per request — a redirect
///   target runs logic outside our contract, so it is never requested.
/// - **Cache bypass**: `dart:io` performs no HTTP caching.
/// - **Failure isolation**: every dispatch is independent fire-and-forget; a
///   slow or failing tracker never delays canonical tracking, never affects
///   sibling trackers, and never surfaces an error to the publisher. No
///   retries — exactly one attempt per matching tracker per helper invocation,
///   so agency counts reconcile.
/// - **Sanitized logging**: outcomes reference `trackerId` only; tracker URLs
///   never reach any log sink (they can carry campaign-identifying query
///   data).
class ThirdPartyTrackerDispatcher {
  /// Mirror of the engine-side limit. More than this many valid entries can
  /// only mean a serving bug or a tampered response; firing a partial subset
  /// would make the agency's numbers quietly disagree with ours, so the whole
  /// collection is discarded instead.
  static const int maxTrackers = 10;

  static const Duration requestTimeout = Duration(seconds: 10);

  final http.Client _client;
  final Logger _logger;

  /// Whether [_client] was built here. A test-injected client is shared with
  /// the SDK's API client, so [close] must never close it — the SDK owns it.
  final bool _ownsClient;

  /// [httpClient] is a test seam; when omitted the dispatcher builds its own
  /// dedicated client so nothing is shared with the SDK's API client.
  ThirdPartyTrackerDispatcher({required Logger logger, http.Client? httpClient})
      : _logger = logger,
        _client = httpClient ?? _defaultClient(),
        _ownsClient = httpClient == null;

  static http.Client _defaultClient() {
    final ioHttpClient = io.HttpClient()
      ..connectionTimeout = requestTimeout
      ..idleTimeout = requestTimeout
      // dart:io injects `User-Agent: Dart/x.y (dart:io)` by default — an
      // identity header this dispatcher must not carry. null omits it.
      ..userAgent = null;
    return http_io.IOClient(ioHttpClient);
  }

  /// Dispatches every tracker matching [event], exactly once each per
  /// invocation.
  ///
  /// Order of operations mirrors the E06 spec: semantic validation drops
  /// invalid entries individually; the defensive limit then applies to the
  /// count of VALID entries; matching and per-invocation exact-URL dedupe
  /// decide what actually fires.
  void dispatch(List<ThirdPartyTracker> trackers, ThirdPartyTrackerEvent event) {
    final valid = <ThirdPartyTracker>[];
    for (final tracker in trackers) {
      final reason = rejectionReason(tracker);
      if (reason == null) {
        valid.add(tracker);
      } else {
        _logger.fine(
          'Discarding third-party tracker "${tracker.trackerId}": $reason',
        );
      }
    }
    if (valid.isEmpty) return;
    if (valid.length > maxTrackers) {
      _logger.warning(
        'Discarding ALL third-party trackers for this creative: '
        '${valid.length} valid entries exceed the limit of $maxTrackers.',
      );
      return;
    }

    final dispatchedUrls = <String>{};
    for (final tracker in valid) {
      if (!matches(tracker, event)) continue;
      final uri = Uri.tryParse(tracker.url);
      // Validation already required a verbatim-round-tripping HTTPS URL, so
      // this guard cannot fail; it exists so a future validation change
      // cannot introduce a null-assertion crash.
      if (uri == null) continue;
      if (!dispatchedUrls.add(tracker.url)) {
        _logger.fine(
          'Skipping third-party tracker "${tracker.trackerId}": duplicate URL '
          'already dispatched in this invocation.',
        );
        continue;
      }
      unawaited(() async {
        try {
          final request = http.Request('GET', uri)..followRedirects = false;
          // Note: on timeout the wrapping future fails but the socket request
          // is not aborted — the tracker may still count server-side. That
          // keeps the ≤1-attempt-per-invocation guarantee intact (we never
          // re-fire), which is the property agency reconciliation needs.
          final response =
              await _client.send(request).timeout(requestTimeout);
          // Drain the body so the connection is released immediately instead
          // of pinning a socket until the idle timeout.
          await response.stream.drain<void>();
          _logger.fine(
            'Third-party tracker "${tracker.trackerId}" completed '
            '(${response.statusCode}).',
          );
        } catch (error) {
          // Failure isolation: a failed tracker is a completed attempt.
          // Nothing is retried, nothing propagates, and the URL is never
          // logged — only the error TYPE (an http ClientException
          // stringifies with the URI, so `$error` would leak it).
          _logger.fine(
            'Third-party tracker "${tracker.trackerId}" failed '
            '(${error.runtimeType}).',
          );
        }
      }());
    }
  }

  /// Closes the dispatcher's own client. A test-injected (shared) client is
  /// left alone — the SDK owns its lifecycle.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Why an entry cannot be served, or `null` when it is valid. Reasons are
  /// stable, URL-free strings — they go straight into logs.
  static String? rejectionReason(ThirdPartyTracker tracker) {
    if (tracker.trackerId.isEmpty) return 'missing trackerId';
    switch (tracker.eventType) {
      case 'impression':
        break;
      case 'click':
        switch (tracker.matchType) {
          case 'any':
            break;
          case 'specific':
            if (tracker.eventKey == null || tracker.eventKey!.isEmpty) {
              return 'specific click tracker without an eventKey';
            }
          default:
            return 'unknown matchType';
        }
      default:
        return 'unknown eventType';
    }
    final uri = Uri.tryParse(tracker.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'url is not an absolute https URL';
    }
    // Defense in depth (the Ad Manager already rejects these at creation): a
    // tracker URL must carry no embedded credentials — they would travel in
    // cleartext through proxies and land in the agency server's access logs —
    // and no fragment, which is client-side-only and never part of a fixed
    // measurement URL.
    if (uri.userInfo.isNotEmpty) {
      return 'url embeds credentials (userinfo)';
    }
    if (uri.hasFragment) {
      return 'url carries a fragment';
    }
    // The wire request is built from the parsed Uri, and Dart's Uri (like the
    // URL types on iOS and Android) normalizes what it cannot represent
    // verbatim — an invalid percent-sequence such as a raw %%MACRO%% would be
    // re-escaped and reach the agency corrupted. Never fire mutated bytes:
    // a URL the parser cannot round-trip byte-identically is unservable.
    if (uri.toString() != tracker.url) {
      return 'url does not round-trip verbatim through the URL parser';
    }
    return null;
  }

  /// E06 matching: impressions fire on `fireImpression`; any-click trackers
  /// fire on every valid click; specific-click trackers fire only when the
  /// reported key equals theirs.
  static bool matches(ThirdPartyTracker tracker, ThirdPartyTrackerEvent event) {
    return switch (event) {
      ThirdPartyImpressionEvent() => tracker.eventType == 'impression',
      ThirdPartyClickEvent(:final key) => tracker.eventType == 'click' &&
          (tracker.matchType == 'any' ||
              (tracker.matchType == 'specific' && tracker.eventKey == key)),
    };
  }
}
