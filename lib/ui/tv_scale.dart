import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tv_device.dart';

/// Logical size the app is laid out at on a TV: the desktop layout was
/// designed for at least 1024 wide, and a 1080p TV at density 2 only gives
/// 960x540.
const tvCanvasSize = Size(1280, 720);

/// On a TV, lays [child] out on a [tvCanvasSize] canvas scaled uniformly to
/// the real screen, with a [MediaQuery] that matches the canvas (size,
/// insets and pixel ratio in canvas units). Elsewhere it returns [child]
/// untouched.
///
/// Wrap `MaterialApp.builder` with it, so routes, dialogs and overlays are
/// scaled too.
class TvScale extends StatelessWidget {
  /// Scales [child] on a TV.
  const TvScale({super.key, required this.child});

  /// The app to scale.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return child;
    final media = MediaQuery.of(context);
    final scale = math.min(
      media.size.width / tvCanvasSize.width,
      media.size.height / tvCanvasSize.height,
    );
    if (scale <= 0) return child;
    return FittedBox(
      child: SizedBox.fromSize(
        size: tvCanvasSize,
        child: MediaQuery(
          data: media.copyWith(
            size: tvCanvasSize,
            devicePixelRatio: media.devicePixelRatio * scale,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
