import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the platform browser, as a separate surface and never inside
/// the form. The only file of the host app that imports `url_launcher`: the
/// generated host app's pubspec adds it (tool/host_app.sh), the package's own
/// pubspec never does, so this file is excluded from the package's analysis.
Future<bool> openExternalUrl(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
