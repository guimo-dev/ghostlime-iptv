import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Tappable, focusable container: on focus it shows an accent border with a
/// soft glow and grows slightly; on hover it lifts — the app's "TV" affordance.
class FocusCard extends StatefulWidget {
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.radius = 12,
    this.color,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.grow = true,
    this.shadow = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double radius;

  /// Background; transparent when `null`.
  final Color? color;

  /// Keeps the selected look without focus (e.g. the current channel).
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Whether to grow slightly when highlighted (off for wide list rows).
  final bool grow;

  /// Whether to cast a resting drop shadow (posters, cards).
  final bool shadow;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = _focused || _hovered;
    final palette = AccentPalette.of(context);
    final radius = BorderRadius.circular(widget.radius);
    final background = widget.selected
        ? palette.selected
        : highlight && !widget.grow
        ? Colors.white.withValues(alpha: 0.06)
        : widget.color;
    return AnimatedScale(
      scale: highlight && widget.grow ? 1.04 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.all(
            color: _focused ? palette.accent : Colors.transparent,
            width: 3,
          ),
          boxShadow: _focused
              ? palette.focusGlow
              : widget.shadow
              ? AppStyle.cardShadow
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onFocusChange: (value) => setState(() => _focused = value),
            onHover: (value) => setState(() => _hovered = value),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
