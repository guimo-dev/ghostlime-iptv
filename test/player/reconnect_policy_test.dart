import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/player_screen.dart';

void main() {
  /// A policy whose give-up reasons end up in the returned list.
  (ReconnectPolicy, List<String>) policy({
    bool isLive = true,
    bool autoReconnect = true,
  }) {
    final reasons = <String>[];
    return (
      ReconnectPolicy(
        isLive: isLive,
        autoReconnect: autoReconnect,
        onGiveUp: reasons.add,
      ),
      reasons,
    );
  }

  test('a VOD that ends or fails is not reopened and logs no give-up', () {
    final (vod, reasons) = policy(isLive: false);
    expect(vod.next(stable: false), isNull);
    expect(vod.next(stable: false), isNull);
    expect(reasons, isEmpty);
  });

  test('a live stream reconnects with growing delays, then gives up', () {
    final (live, reasons) = policy();
    expect([
      for (var i = 0; i < reconnectDelays.length; i++) live.next(stable: false),
    ], reconnectDelays);
    expect(live.next(stable: false), isNull);
    expect(reasons, ['attempts exhausted']);
  });

  test('error and end of the same failure log the give-up once', () {
    final (live, reasons) = policy();
    for (var i = 0; i < reconnectDelays.length; i++) {
      live.next(stable: false);
    }
    live.next(stable: false); // error
    live.next(stable: false); // completed
    expect(reasons, ['attempts exhausted']);

    final (off, offReasons) = policy(autoReconnect: false);
    off.next(stable: false);
    off.next(stable: false);
    expect(offReasons, ['auto-reconnect off']);
  });

  test('a stable stream counts failures from the first attempt again', () {
    final (live, reasons) = policy();
    for (var i = 0; i < reconnectDelays.length; i++) {
      live.next(stable: false);
    }
    expect(live.next(stable: true), reconnectDelays.first);
    expect(live.attempts, 1);
    expect(reasons, isEmpty);
  });

  test('a new give-up after a later reconnection is logged again', () {
    final (live, reasons) = policy();
    for (var i = 0; i <= reconnectDelays.length; i++) {
      live.next(stable: false);
    }
    live.next(stable: true);
    for (var i = 0; i < reconnectDelays.length; i++) {
      live.next(stable: false);
    }
    expect(reasons, ['attempts exhausted', 'attempts exhausted']);
  });
}
