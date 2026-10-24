/// Login data for an Xtream Codes account.
class XtreamCredentials {
  /// Creates credentials. [serverUrl] may be unnormalised (no scheme, trailing slash).
  const XtreamCredentials(this.serverUrl, this.username, this.password);

  final String serverUrl;
  final String username;
  final String password;

  /// Whether every field has a value.
  bool get isComplete =>
      serverUrl.trim().isNotEmpty && username.isNotEmpty && password.isNotEmpty;
}
