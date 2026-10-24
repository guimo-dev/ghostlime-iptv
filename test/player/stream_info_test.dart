import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/stream_info.dart';

void main() {
  test('parses mpv properties', () {
    final info = StreamInfo.fromMpvProperties({
      'video-format': 'hevc',
      'audio-codec-name': 'ac3',
      'width': '1920',
      'height': '1080',
      'container-fps': '25.000000',
      'file-format': 'mpegts',
    });
    expect(info.videoCodec, 'hevc');
    expect(info.audioCodec, 'ac3');
    expect(info.width, 1920);
    expect(info.height, 1080);
    expect(info.fps, 25.0);
    expect(info.container, 'mpegts');
  });

  test('empty or non-numeric values become null', () {
    final info = StreamInfo.fromMpvProperties({
      'video-format': '',
      'width': '',
      'container-fps': 'unavailable',
    });
    expect(info.videoCodec, isNull);
    expect(info.width, isNull);
    expect(info.fps, isNull);
  });

  test('toRows shows labels and placeholders', () {
    final rows = StreamInfo.fromMpvProperties({
      'video-format': 'hevc',
      'width': '1920',
      'height': '1080',
    }).toRows();
    expect(rows, contains(('Vídeo', 'hevc')));
    expect(rows, contains(('Resolución', '1920×1080')));
    expect(rows, contains(('Audio', '—')));
  });
}
