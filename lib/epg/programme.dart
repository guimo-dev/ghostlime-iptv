/// One scheduled broadcast of a channel, as read from an XMLTV guide.
class Programme {
  const Programme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.description,
  });

  /// XMLTV channel id (matches a catalog channel's `epgId`).
  final String channelId;

  /// Start time, in UTC.
  final DateTime start;

  /// End time, in UTC.
  final DateTime stop;

  final String title;
  final String? description;
}
