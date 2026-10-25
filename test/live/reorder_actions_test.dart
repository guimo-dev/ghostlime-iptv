import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/live/reorder_screen.dart';
import 'package:iptv_player/ui/app_theme.dart';

/// Pumps a [ReorderScreen] of two channels on a screen of [size].
Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const ReorderScreen(
        title: 'Ordenar',
        items: [
          ReorderItem(id: 'a', label: 'Canal A'),
          ReorderItem(id: 'b', label: 'Canal B'),
        ],
      ),
    ),
  );
}

Rect _button(WidgetTester tester, String label) => tester.getRect(
  find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  ),
);

void main() {
  testWidgets('phones get Cancelar and Guardar at the bottom', (tester) async {
    await _pump(tester, const Size(390, 844));
    final cancel = _button(tester, 'Cancelar');
    final save = _button(tester, 'Guardar');
    expect(cancel.top, greaterThan(844 * 2 / 3));
    expect(save.top, greaterThan(844 * 2 / 3));
    expect(save.left, greaterThan(cancel.right));
    expect(save.right, closeTo(390 - 16, 1));
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
  });

  testWidgets('the desktop keeps them in the top bar', (tester) async {
    await _pump(tester, const Size(1280, 800));
    final bar = tester.getRect(find.byType(AppBar));
    expect(bar.contains(_button(tester, 'Cancelar').center), isTrue);
    expect(bar.contains(_button(tester, 'Guardar').center), isTrue);
  });

  testWidgets('a landscape phone keeps them in the top bar', (tester) async {
    await _pump(tester, const Size(844, 390));
    final bar = tester.getRect(find.byType(AppBar));
    expect(bar.contains(_button(tester, 'Guardar').center), isTrue);
  });
}
