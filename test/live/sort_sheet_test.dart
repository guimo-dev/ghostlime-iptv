import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/live/sort_sheet.dart';
import 'package:iptv_player/ui/app_theme.dart';

const _optionLabels = ['Original', 'A→Z', 'Z→A', 'Manual'];

/// Pumps a screen of [size] with a button that opens the sheet [open] builds,
/// and taps it.
Future<void> _openSheet(
  WidgetTester tester,
  Size size,
  void Function(BuildContext context) open,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

/// Expects every sort option label to be drawn whole, on one line, on screen.
///
/// A label narrower than its widest single-line width would wrap or be cut.
void _expectOptionsFit(WidgetTester tester, Size size) {
  expect(tester.takeException(), isNull);
  for (final label in _optionLabels) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
      reason: '"$label" wraps or is cut',
    );
    final rect = tester.getRect(find.text(label));
    expect((Offset.zero & size).contains(rect.bottomRight), isTrue);
  }
}

void _openChannelSheet(BuildContext context) =>
    showSortSheet(context, current: const ChannelSort(), isOwn: true);

void _openCategorySheet(BuildContext context) =>
    showCategorySortSheet(context, current: SortMode.original);

void main() {
  for (final size in const [Size(360, 640), Size(390, 844)]) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('channel sort options fit at $at', (tester) async {
      await _openSheet(tester, size, _openChannelSheet);
      _expectOptionsFit(tester, size);
    });

    testWidgets('category sort options fit at $at', (tester) async {
      await _openSheet(tester, size, _openCategorySheet);
      _expectOptionsFit(tester, size);
    });
  }

  testWidgets('Aplicar is the lowest, rightmost button on a phone', (
    tester,
  ) async {
    await _openSheet(tester, const Size(390, 844), _openChannelSheet);
    final apply = tester.getRect(find.widgetWithText(FilledButton, 'Aplicar'));
    for (final label in [
      'Ordenar a mano…',
      'Usar como predeterminado',
      'Volver al predeterminado',
    ]) {
      final other = tester.getRect(find.widgetWithText(OutlinedButton, label));
      expect(apply.top, greaterThanOrEqualTo(other.bottom), reason: label);
    }
    expect(apply.right, closeTo(390 - 16, 1));
  });

  testWidgets('choosing an option and applying returns it', (tester) async {
    SortSheetResult? result;
    await _openSheet(tester, const Size(360, 640), (context) async {
      result = await showSortSheet(
        context,
        current: const ChannelSort(),
        isOwn: false,
      );
    });
    await tester.tap(find.text('Z→A'));
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(result?.sort.mode, SortMode.alphaDesc);
  });

  testWidgets('the desktop sheet keeps its segmented control', (tester) async {
    await _openSheet(tester, const Size(1280, 800), _openChannelSheet);
    expect(find.byType(SegmentedButton<SortMode>), findsOneWidget);
  });
}
