import 'dart:async';

import 'package:iptv_player/ui/marquee_text.dart';

/// Runs before every test file in `test/`: the scrolling channel names never
/// stop, so they are switched off here or `pumpAndSettle` would time out.
/// `marquee_text_test.dart` switches them on where it checks the movement.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MarqueeText.enabled = false;
  await testMain();
}
