import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'lead_form_controller.dart';
import 'lead_form_state.dart';
import 'secure_form_surface.dart';

/// Shows the native secure form view of a [LeadFormController].
///
/// The native view belongs to the controller: it is created by
/// [LeadFormController.prepare] or [LeadFormController.open] and destroyed by
/// [LeadFormController.dispose]. This widget only attaches it, so a rebuild
/// never recreates the form and never loses what the viewer typed. Until the
/// native view exists (and after it is gone) the widget is empty.
///
/// Platform views exist on Android and iOS only; on any other platform the
/// widget is empty.
class LeadFormView extends StatefulWidget {
  const LeadFormView({super.key, required this.controller});

  final LeadFormController controller;

  @override
  State<LeadFormView> createState() => _LeadFormViewState();
}

class _LeadFormViewState extends State<LeadFormView> {
  late ValueListenable<bool> _ready;

  @override
  void initState() {
    super.initState();
    _ready = leadFormSurfaceReady(widget.controller);
  }

  @override
  void didUpdateWidget(LeadFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _ready = leadFormSurfaceReady(widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only this PopScope rebuilds when the state changes: the platform view
    // below sits in the child, which the state listener never rebuilds.
    return ValueListenableBuilder<LeadFormState>(
      valueListenable: widget.controller.state,
      child: _surface(context),
      builder: (context, _, child) => PopScope(
        canPop: !leadFormHandlesBack(widget.controller),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.controller.handleBack();
        },
        child: child!,
      ),
    );
  }

  Widget _surface(BuildContext context) {
    final id = leadFormSurfaceId(widget.controller);
    return ValueListenableBuilder<bool>(
      valueListenable: _ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        final generation = leadFormSurfaceGeneration(widget.controller);
        final params = <String, Object?>{'id': id, 'generation': generation};
        // The generation is part of the key: a replacement native surface (a
        // retry after a load failure) always gets a new platform view.
        final key = ValueKey<String>('admoai_lead_form_${id}_$generation');
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          return AndroidView(
            key: key,
            viewType: PlatformLeadFormSurface.viewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
          );
        }
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          return UiKitView(
            key: key,
            viewType: PlatformLeadFormSurface.viewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
