import '../models/decision_request.dart' show JourneyOpt;
import '../models/decision_response.dart';

/// Convenience read-only accessors for Journey Takeover Ads metadata on a
/// [Creative]. Follows the same extension pattern as `VideoHelper` /
/// `OMHelper`, keeping [Creative] lean. All getters are null-safe and expose
/// server-owned values only — the SDK never mutates Journey state or infers
/// progression/completion/billing from them.
extension JourneyHelper on Creative {
  /// Whether this creative was served as part of a Journey (i.e. the response
  /// carried a `journey` block).
  bool isJourneyAd() => journey != null;

  String? get journeyDealId => journey?.dealId;
  String? get journeyInstanceId => journey?.instanceId;
  String? get journeyDefinitionKey => journey?.definitionKey;
  String? get journeyStageId => journey?.stageId;
  String? get journeyStageKey => journey?.stageKey;
  String? get journeyStageNodeId => journey?.stageNodeId;
  String? get journeySessionId => journey?.sessionId;
  JourneyOpt? get journeyOptStatus => journey?.optStatus;
  String? get journeyPricingModel => journey?.pricingModel;
  String? get journeyFallbackBillingMode => journey?.fallbackBillingMode;

  /// True only on the serve that completes a `final_stage` Journey. Purely
  /// informational — completion is recorded server-side; the SDK fires no
  /// extra URL for this mode.
  bool get isJourneyCompletion => journey?.isCompletion ?? false;
}
