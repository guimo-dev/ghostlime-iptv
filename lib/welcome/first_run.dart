import '../legal/legal_info.dart';

/// What the app shows before the playlists screen when it starts.
enum FirstRunStep {
  /// The full welcome: what the app is, the terms and the account options.
  welcome,

  /// Only the terms to accept: an existing installation, or terms that
  /// changed since they were accepted.
  acceptTerms,

  /// Nothing: straight to the playlists.
  none,
}

/// The step to show at start. The welcome appears once per installation and
/// never where the app was already in use ([hasPlaylists] or [signedIn]);
/// those only accept the terms. Terms accepted in a version older than
/// [termsVersion] ([acceptedTerms], 0 when never) are asked again.
FirstRunStep firstRunStep({
  required bool welcomeDone,
  required int acceptedTerms,
  required bool hasPlaylists,
  required bool signedIn,
}) {
  if (!welcomeDone && !hasPlaylists && !signedIn) return FirstRunStep.welcome;
  if (acceptedTerms < termsVersion) return FirstRunStep.acceptTerms;
  return FirstRunStep.none;
}
