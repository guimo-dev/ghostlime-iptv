import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/live/reorder_screen.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/backdrop.dart';
import 'package:iptv_player/ui/content_width.dart';

void main() {
  testWidgets('sits on the app background with a width-limited list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 900);
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
    expect(
      find.ancestor(
        of: find.byType(AppBar),
        matching: find.byType(AppBackground),
      ),
      findsOneWidget,
    );
    final row = tester.getRect(find.widgetWithText(ListTile, 'Canal A'));
    expect(row.width, lessThanOrEqualTo(ContentWidths.reading));
    expect(row.center.dx, closeTo(1000, 1));
    // The list itself spans the window, so the wheel works over the margins.
    expect(tester.getRect(find.byType(ReorderableListView)).width, 2000);
  });
}
