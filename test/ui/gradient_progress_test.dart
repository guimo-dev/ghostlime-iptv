import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/backdrop.dart';

void main() {
  testWidgets('the fill is value times the track width and the full height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: GradientProgress(value: 0.25, height: 6),
          ),
        ),
      ),
    );
    final fill = tester.getRect(
      find.byKey(const Key('gradient-progress-fill')),
    );
    expect(fill.width, 50);
    expect(fill.height, 6);
    expect(fill.left, 0);
  });

  testWidgets('a value of 0 paints no fill and 1 fills the track', (
    tester,
  ) async {
    for (final (value, width) in [(0.0, 0.0), (1.0, 200.0)]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 200, child: GradientProgress(value: value)),
          ),
        ),
      );
      final fill = tester.getRect(
        find.byKey(const Key('gradient-progress-fill')),
      );
      expect(fill.width, width);
    }
  });
}
