import 'bridge_protocol.dart';
import 'lead_form_controller.dart';

/// The live [LeadFormController]s of one `AdMoai` instance: it bounds how many
/// hidden forms are loaded at once and closes every one when the user or the
/// value provider changes. Holds weak references, so it never keeps a form
/// alive. Internal: not exported.
class LeadFormRegistry {
  LeadFormRegistry({BridgeContract? contract})
      : _contract = contract ?? BridgeContract.shipped;

  final BridgeContract _contract;
  final List<WeakReference<LeadFormController>> _controllers = [];

  /// Adds [controller], forgetting those that are gone or disposed.
  void register(LeadFormController controller) {
    _controllers.removeWhere((r) {
      final c = r.target;
      return c == null || leadFormIsDisposed(c);
    });
    _controllers.add(WeakReference(controller));
  }

  /// Forgets [controller] (it was disposed).
  void remove(LeadFormController controller) {
    _controllers.removeWhere((r) => identical(r.target, controller));
  }

  /// True when nothing is registered.
  bool get isEmpty => _controllers.isEmpty;

  /// True when [controller] may load now: fewer other hidden loaded forms than
  /// the contract allows. A form that is refused stays idle; the viewer's tap
  /// loads it anyway.
  bool mayPrepare(LeadFormController controller) {
    final hidden = _live()
        .where((c) => !identical(c, controller) && leadFormCountsAsHidden(c))
        .length;
    return hidden < _contract.maxHiddenPreparedForms;
  }

  /// Disposes every live controller.
  void disposeAll() {
    final live = _live();
    _controllers.clear();
    for (final c in live) {
      // dispose() marks the controller disposed before it first yields.
      c.dispose().catchError((Object _) {});
    }
  }

  /// Forgets every controller without disposing them.
  void clear() => _controllers.clear();

  List<LeadFormController> _live() => [
        for (final r in _controllers)
          if (r.target case final c?) c,
      ];
}
