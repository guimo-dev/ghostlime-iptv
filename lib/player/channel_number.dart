import '../catalog/catalog_models.dart';

// Channels are numbered by their place in the list shown (1-based), as the
// rows of Directo already are. The catalog keeps no provider number: the
// M3U `tvg-chno` and the Xtream `num` would need a new column (a schema
// migration), both parsers and the sync, and Xtream's `num` runs across the
// whole account, so it would not match the rows of the group shown.

/// The number of [channel] in [visible] (the channels shown, in order):
/// its 1-based place, or 0 when it is not there.
int channelNumberOf(Channel channel, List<Channel> visible) =>
    visible.indexWhere((c) => c.key == channel.key) + 1;

/// Index in [visible] of the channel numbered [number], or `null` when no
/// channel has that number.
int? channelIndexForNumber(int number, List<Channel> visible) =>
    number >= 1 && number <= visible.length ? number - 1 : null;
