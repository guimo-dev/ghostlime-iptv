import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tv_device.dart';

/// Logical size the app is laid out at on a TV: the desktop layout was
/// designed for at least 1024 wide, and a 1080p TV at density 2 only gives
/// 960x540.
const tvCanvasSize = Size(1280, 720);

/// Overscan margin of a TV, in canvas units: many TVs crop the edges of the
/// picture, so interactive content stays this far inside. It is added to the
/// canvas padding, so `SafeArea`, app bars and lists keep clear of it while
/// backgrounds and video stay full-bleed.
const tvSafeMargin = EdgeInsets.symmetric(horizontal: 64, vertical: 36);

/// On a TV, lays [child] out on a [tvCanvasSize] canvas scaled uniformly to
/// the real screen, with a [MediaQuery] that matches the canvas (size,
/// insets and pixel ratio in canvas units) and at least [tvSafeMargin] of
/// padding. Elsewhere it returns [child] untouched.
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
            padding: _atLeastSafe(media.padding / scale),
            viewPadding: _atLeastSafe(media.viewPadding / scale),
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }

  /// [insets] grown, side by side, to at least [tvSafeMargin].
  static EdgeInsets _atLeastSafe(EdgeInsets insets) => EdgeInsets.fromLTRB(
    math.max(insets.left, tvSafeMargin.left),
    math.max(insets.top, tvSafeMargin.top),
    math.max(insets.right, tvSafeMargin.right),
    math.max(insets.bottom, tvSafeMargin.bottom),
  );
}
