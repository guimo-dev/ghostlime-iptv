import 'package:media_kit/media_kit.dart';

/// How long a stream may take to start playing before the player gives up
/// and shows an error instead of loading forever.
const streamStartTimeout = Duration(seconds: 20);

/// media_kit's `demuxer-lavf-o` without `strict=experimental`. With that flag
/// FFmpeg 6.0 (bundled libmpv) reads the WebVTT subtitle renditions of HLS,
/// and on a live playlist (RTVE's La 1, La 2) opening never finishes: the
/// subtitle demuxer keeps waiting for the end of a list that has none.
const demuxerLavfOptions =
    'seg_max_retry=5,allowed_extensions=ALL,'
    'protocol_whitelist=[udp,rtp,tcp,tls,data,file,http,https,crypto]';

/// Replaces media_kit's FFmpeg demuxer options with [demuxerLavfOptions] on
/// [player]; call it before `open`. Does nothing on non-mpv backends.
Future<void> useSafeDemuxerOptions(Player player) async {
  final platform = player.platform;
  if (platform is NativePlayer) {
    await platform.setProperty('demuxer-lavf-o', demuxerLavfOptions);
  }
}
