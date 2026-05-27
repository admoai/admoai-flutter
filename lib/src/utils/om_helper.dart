import '../models/decision_response.dart';

extension OMHelper on Creative {
  List<VerificationScriptResource>? getVerificationResources() =>
      verificationScriptResources;

  bool hasOMVerification() =>
      verificationScriptResources != null &&
      verificationScriptResources!.isNotEmpty;
}
