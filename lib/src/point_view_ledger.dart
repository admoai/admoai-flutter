import 'dart:collection';

/// Remembers which Sponsored Pin view URLs this SDK instance has already fired,
/// so a map re-rendering the same decision response does not fire them again.
///
/// Keyed on the view URL itself, never on the point id. The engine mints every
/// view URL with its own event id, one per `(request, creative, location)`, so
/// "this URL was fired" is exactly "this pin was reported for this decision
/// response" — the key E10 dedups `pin_view` on server-side. A pin id repeats
/// across responses; keying on it would swallow the view a new response is
/// owed.
///
/// Bounded: it holds the last [capacity] URLs and evicts the least recently
/// claimed. A URL that was evicted and is claimed again simply fires again,
/// which the engine already drops (`SETNX` on the event id), so forgetting is
/// never wrong — only a wasted request.
///
/// No lock: an isolate runs one piece of Dart at a time and [claim] never
/// awaits, so the check and the record cannot interleave. Each isolate that
/// builds its own `AdMoai` has its own ledger, as it has its own everything.
class PointViewLedger {
  /// Ten full decision responses at the engine's 50-point ceiling, one view URL
  /// per point on the standard template.
  static const defaultCapacity = 500;

  final int capacity;

  /// Iterates least → most recently claimed.
  final LinkedHashSet<String> _urls = LinkedHashSet<String>();

  PointViewLedger({int capacity = defaultCapacity})
      : capacity = capacity < 1 ? 1 : capacity;

  /// Records [url] as fired and returns `true` the first time it is seen.
  /// Returns `false` for a URL already fired, and refreshes it so a pin still on
  /// screen is not the one evicted next.
  bool claim(String url) {
    if (_urls.remove(url)) {
      _urls.add(url);
      return false;
    }
    _urls.add(url);
    if (_urls.length > capacity) _urls.remove(_urls.first);
    return true;
  }

  /// How many URLs are remembered right now — the observable side of the bound.
  int get length => _urls.length;
}
