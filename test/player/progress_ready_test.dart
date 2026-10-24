import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/player_screen.dart';

void main() {
  const start = Duration(minutes: 45);

  test('never reports while position or duration is zero', () {
    expect(
      progressReady(Duration.zero, const Duration(hours: 1), null),
      isFalse,
    );
    expect(
      progressReady(const Duration(seconds: 5), Duration.zero, null),
      isFalse,
    );
  });

  test('without resume, any real position is reported', () {
    expect(
      progressReady(const Duration(seconds: 5), const Duration(hours: 1), null),
      isTrue,
    );
  });

  test('when resuming, waits until playback reaches the start point', () {
    const hour = Duration(hours: 1);
    expect(progressReady(const Duration(seconds: 3), hour, start), isFalse);
    expect(
      progressReady(const Duration(minutes: 44, seconds: 58), hour, start),
      isTrue,
    );
  });
}
