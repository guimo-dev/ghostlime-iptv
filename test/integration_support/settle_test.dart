import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/golden.dart';
import '../../integration_test/support/harness.dart';

void main() {
  testWidgets('settle returns at the timeout with a spinner on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: CircularProgressIndicator())),
    );
    final watch = Stopwatch()..start();
    await settle(tester, timeout: const Duration(milliseconds: 500));
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 500)),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  testWidgets('settle waits for images to load', (tester) async {
    final rgba = Uint8List.fromList([for (var i = 0; i < 4 * 4; i++) 200]);
    final png = (await tester.runAsync(() => encodePng(rgba, 2, 2)))!;
    await tester.pumpWidget(Image.memory(png));
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNull);
    await settle(tester);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });
}
