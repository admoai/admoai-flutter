import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the platform browser, as a separate surface and never inside
/// the form. The only file of the host app that imports `url_launcher`: the
/// generated host app's pubspec adds it (tool/host_app.sh), the package's own
/// pubspec never does, so this file is excluded from the package's analysis.
/// Returns false when the platform cannot open it, whether it answers false or
/// throws.
Future<bool> openExternalUrl(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
