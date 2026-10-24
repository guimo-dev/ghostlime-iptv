/// mpv properties read to fill [StreamInfo].
const mpvInfoProperties = [
  'video-format',
  'audio-codec-name',
  'width',
  'height',
  'container-fps',
  'file-format',
];

/// Replaces every URL in [text] with `[URL]`, so player errors shown on screen
/// never expose the credentials embedded in Xtream stream URLs.
String redactUrls(String text) =>
    text.replaceAll(RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://\S+'), '[URL]');

/// Technical details of the stream being played, for diagnosing playback issues.
class StreamInfo {
  const StreamInfo({
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.fps,
    this.container,
  });

  /// Builds the info from raw mpv property values keyed by [mpvInfoProperties].
  ///
  /// Empty or unparsable values become `null`.
  factory StreamInfo.fromMpvProperties(Map<String, String> props) {
    String? text(String key) {
      final value = props[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return StreamInfo(
      videoCodec: text('video-format'),
      audioCodec: text('audio-codec-name'),
      width: int.tryParse(text('width') ?? ''),
      height: int.tryParse(text('height') ?? ''),
      fps: double.tryParse(text('container-fps') ?? ''),
      container: text('file-format'),
    );
  }

  final String? videoCodec;
  final String? audioCodec;
  final int? width;
  final int? height;
  final double? fps;
  final String? container;

  /// Label/value pairs for display; missing values show as `—`.
  List<(String, String)> toRows() {
    const missing = '—';
    final resolution = width != null && height != null
        ? '$width×$height'
        : missing;
    return [
      ('Vídeo', videoCodec ?? missing),
      ('Audio', audioCodec ?? missing),
      ('Resolución', resolution),
      ('FPS', fps?.toStringAsFixed(2) ?? missing),
      ('Contenedor', container ?? missing),
    ];
  }
}
