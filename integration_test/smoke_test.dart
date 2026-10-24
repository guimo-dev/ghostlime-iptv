import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/golden.dart';
import 'support/harness.dart';

/// Proves the visual harness end to end: the app starts on throwaway data at
/// each size and its home screen matches the reference.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [smallSize, mediumSize]) {
    testWidgets('home screen at ${sizeName(size)}', (tester) async {
      final harness = await AppHarness.start(tester, size: size);
      addTearDown(harness.close);
      await settle(tester);
      expect(find.text('Añade tu primera lista'), findsOneWidget);
      await expectScreen(tester, 'home');
    });
  }

  testWidgets('masks paint their widgets black', (tester) async {
    final harness = await AppHarness.start(tester, size: smallSize);
    addTearDown(harness.close);
    await settle(tester);
    final title = find.text('Añade tu primera lista');
    final (width, height, plain) = await captureScreen(tester);
    final (_, _, masked) = await captureScreen(tester, masks: [title]);

    final diff = compareRgba(plain, masked, width, height);
    expect(diff.mismatchRatio, greaterThan(0));
    final rect = tester.getRect(title);
    final maskedPixels =
        (rect.right.ceil() - rect.left.floor()) *
        (rect.bottom.ceil() - rect.top.floor());
    final changed = maskedPixels / (width * height);
    expect(diff.mismatchRatio, lessThanOrEqualTo(changed));
    final center = rect.center;
    final i = (center.dy.toInt() * width + center.dx.toInt()) * 4;
    expect(masked.sublist(i, i + 4), [0, 0, 0, 255]);
  });
}
