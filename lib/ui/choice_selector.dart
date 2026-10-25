import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'form_factor.dart';

/// One choice among a few [options] (value → Spanish label).
///
/// The desktop layout shows a [SegmentedButton]. Segments share the width
/// evenly and split or cut their labels on a phone, so the phone layout
/// shows [ChoiceChip]s that flow onto another row when needed.
class ChoiceSelector<T> extends StatelessWidget {
  const ChoiceSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.showSelectedIcon = true,
    this.segmentedStyle,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Whether the desktop segments show a check on the selected one.
  final bool showSelectedIcon;

  /// Style of the desktop segments; `null` for the theme's.
  final ButtonStyle? segmentedStyle;

  @override
  Widget build(BuildContext context) {
    if (usesPhoneLayout(context)) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final MapEntry(:key, value: label) in options.entries)
            ChoiceChip(
              label: Text(label),
              selected: key == value,
              onSelected: (_) => onChanged(key),
              side: _chipSide,
            ),
        ],
      );
    }
    return SegmentedButton<T>(
      showSelectedIcon: showSelectedIcon,
      style: segmentedStyle,
      segments: [
        for (final MapEntry(:key, value: label) in options.entries)
          ButtonSegment(value: key, label: Text(label)),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// Chip border: a light ring outside the chip when it has keyboard or D-pad
/// focus, visible on the lime selected chip too; the theme's border otherwise.
final _chipSide = WidgetStateBorderSide.resolveWith(
  (states) => states.contains(WidgetState.focused)
      ? const BorderSide(
          color: AppColors.text,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        )
      : const BorderSide(color: AppColors.border),
);
