import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

/// One line of text that, when it does not fit, rests with an ellipsis and
/// then, after [restPause], scrolls sideways to show its end, waits
/// [endPause] and jumps back to the start, over and over.
///
/// It only moves while its ticker runs (not under a disabled [TickerMode],
/// e.g. a covered route) and never with [MediaQueryData.disableAnimations]
/// or with [enabled] off; then it is the plain ellipsised line.
class MarqueeText extends StatelessWidget {
  const MarqueeText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  /// Global switch, on in the app. Tests and golden captures turn it off so
  /// `pumpAndSettle` ends and captures always show the text at rest.
  static bool enabled = true;

  /// Time at rest (with the ellipsis) before each scroll.
  static const restPause = Duration(seconds: 2);

  /// Time showing the end of the text before jumping back.
  static const endPause = Duration(milliseconds: 1500);

  /// Scroll speed, in logical pixels per second.
  static const pixelsPerSecond = 30.0;

  @override
  Widget build(BuildContext context) {
    final lineStyle = DefaultTextStyle.of(context).style.merge(style);
    final still = Text(
      text,
      style: lineStyle,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    if (!enabled || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return still;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflow = _lineWidth(context, lineStyle) - constraints.maxWidth;
        if (!constraints.hasBoundedWidth || overflow <= 0) return still;
        return _ScrollingText(
          still: still,
          full: Text(
            text,
            style: lineStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          ),
          overflow: overflow,
        );
      },
    );
  }

  /// Width in logical pixels of [text] on one line in [lineStyle], with the
  /// direction and text scaling of [context].
  double _lineWidth(BuildContext context, TextStyle lineStyle) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: lineStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// The moving part of [MarqueeText]: one repeating controller per line that
/// overflows by [overflow] pixels.
class _ScrollingText extends StatefulWidget {
  const _ScrollingText({
    required this.still,
    required this.full,
    required this.overflow,
  });

  /// The ellipsised line, shown at rest.
  final Widget still;

  /// The whole line, shown while scrolling.
  final Widget full;

  /// How much wider than the available space the line is.
  final double overflow;

  @override
  State<_ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<_ScrollingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  )..repeat();

  /// Time spent scrolling from the start to the end of the line.
  Duration get _scrollTime => Duration(
    milliseconds: (widget.overflow / MarqueeText.pixelsPerSecond * 1000)
        .round(),
  );

  /// One full round: rest, scroll, wait at the end.
  Duration get _cycle =>
      MarqueeText.restPause + _scrollTime + MarqueeText.endPause;

  @override
  void didUpdateWidget(_ScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overflow != widget.overflow) {
      _controller
        ..duration = _cycle
        ..reset()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// How far the line is scrolled now, in logical pixels between 0 and the
  /// overflow.
  double _offset() {
    final elapsed = _controller.value * _cycle.inMilliseconds;
    final scrollStart = MarqueeText.restPause.inMilliseconds;
    final scrollTime = _scrollTime.inMilliseconds;
    if (elapsed <= scrollStart) return 0;
    if (elapsed >= scrollStart + scrollTime) return widget.overflow;
    return widget.overflow * (elapsed - scrollStart) / scrollTime;
  }

  @override
  Widget build(BuildContext context) {
    final towardsStart = Directionality.of(context) == TextDirection.rtl
        ? 1.0
        : -1.0;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final offset = _offset();
          if (offset == 0) return widget.still;
          return ClipRect(
            child: OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              maxWidth: double.infinity,
              fit: OverflowBoxFit.deferToChild,
              child: Transform.translate(
                offset: Offset(towardsStart * offset, 0),
                child: widget.full,
              ),
            ),
          );
        },
      ),
    );
  }
}
