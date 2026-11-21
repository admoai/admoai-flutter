/// How the app shows a Lead Generation form. The form draws its own close
/// button only on [fullScreen]; on [inline] closing is left to the app's own
/// card.
enum FormPresentation {
  /// The form sits inside the app's own card or screen.
  inline('inline'),

  /// The form fills the screen and shows its own close button.
  fullScreen('full_screen');

  /// The exact value the bridge's `initialize` message carries.
  final String wireName;

  const FormPresentation(this.wireName);
}
