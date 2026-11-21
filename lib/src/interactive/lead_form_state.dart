/// Where a [LeadFormController] is in the life of one form.
sealed class LeadFormState {
  const LeadFormState();
}

/// Nothing was loaded yet.
final class LeadFormIdle extends LeadFormState {
  const LeadFormIdle();

  @override
  String toString() => 'LeadFormIdle';
}

/// The form page is loading and preparing in the background.
final class LeadFormPreparing extends LeadFormState {
  const LeadFormPreparing();

  @override
  String toString() => 'LeadFormPreparing';
}

/// The form is prepared and waits for the viewer's tap.
final class LeadFormPrepared extends LeadFormState {
  const LeadFormPrepared();

  @override
  String toString() => 'LeadFormPrepared';
}

/// The form is being activated and its prefill applied.
final class LeadFormActivating extends LeadFormState {
  const LeadFormActivating();

  @override
  String toString() => 'LeadFormActivating';
}

/// The form is ready to be shown. Report it with [LeadFormController.setVisible].
final class LeadFormReadyToShow extends LeadFormState {
  const LeadFormReadyToShow();

  @override
  String toString() => 'LeadFormReadyToShow';
}

/// The app reported the form on screen.
final class LeadFormVisible extends LeadFormState {
  const LeadFormVisible();

  @override
  String toString() => 'LeadFormVisible';
}

/// The viewer submitted and the form waits for the outcome.
final class LeadFormSubmitting extends LeadFormState {
  const LeadFormSubmitting();

  @override
  String toString() => 'LeadFormSubmitting';
}

/// The lead was accepted: [leadId] and the [submittedAt] time (UTC) the form
/// reported.
final class LeadFormSubmitted extends LeadFormState {
  const LeadFormSubmitted(this.leadId, this.submittedAt);

  final String leadId;
  final DateTime submittedAt;

  @override
  bool operator ==(Object other) =>
      other is LeadFormSubmitted &&
      other.leadId == leadId &&
      other.submittedAt == submittedAt;

  @override
  int get hashCode => Object.hash(leadId, submittedAt);

  @override
  String toString() => 'LeadFormSubmitted(leadId: $leadId, '
      'submittedAt: ${submittedAt.toIso8601String()})';
}

/// The form failed with [errorCode]. When [retryable],
/// [LeadFormController.retry] tries again.
final class LeadFormFailed extends LeadFormState {
  const LeadFormFailed(this.errorCode, this.retryable);

  final String errorCode;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      other is LeadFormFailed &&
      other.errorCode == errorCode &&
      other.retryable == retryable;

  @override
  int get hashCode => Object.hash(errorCode, retryable);

  @override
  String toString() =>
      'LeadFormFailed(errorCode: $errorCode, retryable: $retryable)';
}

/// The preparation passed its expiry. The controller never opens.
final class LeadFormExpired extends LeadFormState {
  const LeadFormExpired();

  @override
  String toString() => 'LeadFormExpired';
}

/// The controller was disposed. Every call and message is ignored.
final class LeadFormDisposed extends LeadFormState {
  const LeadFormDisposed();

  @override
  String toString() => 'LeadFormDisposed';
}
