import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/live/live_tv_screen.dart';

void main() {
  test('loads until something plays', () {
    expect(
      previewOverlay(width: null, position: Duration.zero),
      PreviewOverlay.loading,
    );
    expect(
      previewOverlay(width: 0, position: Duration.zero),
      PreviewOverlay.loading,
    );
  });

  test('a decoded picture needs no overlay', () {
    expect(
      previewOverlay(width: 1920, position: Duration.zero),
      PreviewOverlay.none,
    );
    expect(
      previewOverlay(width: 1920, position: const Duration(seconds: 3)),
      PreviewOverlay.none,
    );
  });

  test('playback without a picture is audio only (radio)', () {
    expect(
      previewOverlay(width: null, position: const Duration(seconds: 1)),
      PreviewOverlay.audioOnly,
    );
  });
}
