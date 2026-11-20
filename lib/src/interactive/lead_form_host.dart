import 'lead_form_controller.dart';

/// Why the form asks the app to open a link.
enum ExternalLinkPurpose {
  /// The advertiser's privacy policy; available any time the form is visible.
  privacyPolicy('privacy_policy'),

  /// The advertiser's website; offered only after the lead was submitted.
  websiteCta('website_cta');

  /// The exact value of the bridge's `request_external_url` purpose.
  final String wireName;

  const ExternalLinkPurpose(this.wireName);
}

/// The app's side of a [LeadFormController]: what the form cannot do by itself.
abstract interface class LeadFormHost {
  /// The form asks the app to open [url] for [purpose]. Open it in a separate
  /// browser surface, never inside the form, and without adding anything to the
  /// URL: no token, no form value, no identifier.
  void onOpenExternalLink(
    LeadFormController controller,
    ExternalLinkPurpose purpose,
    Uri url,
  );

  /// The form asks to be closed. Remove its view and call
  /// [LeadFormController.dispose].
  void onRequestClose(LeadFormController controller);
}
