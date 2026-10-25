import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';

/// Pumps a screen of [size] that opens the playlist form on top and stores
/// what it pops in [popped].
Future<void> _pump(
  WidgetTester tester,
  Size size, {
  List<Object?>? popped,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(CatalogDb.inMemory()),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(builder: (_) => const PlaylistFormScreen()),
              );
              popped?.add(result);
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
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

  testWidgets('the bottom bar stays above the keyboard', (tester) async {
    const keyboard = 300.0;
    await _pump(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(TextFormField, 'Nombre'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      _button(tester, 'Guardar').bottom,
      lessThanOrEqualTo(844 - keyboard),
    );
    expect(
      _button(tester, 'Cancelar').bottom,
      lessThanOrEqualTo(844 - keyboard),
    );
  });

  testWidgets('Cancelar closes the form without a result', (tester) async {
    final popped = <Object?>[];
    await _pump(tester, const Size(390, 844), popped: popped);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistFormScreen), findsNothing);
    expect(popped, [null]);
  });

  testWidgets('the desktop keeps Guardar in the top bar', (tester) async {
    await _pump(tester, const Size(1280, 800));
    final bar = tester.getRect(find.byType(AppBar));
    expect(bar.contains(_button(tester, 'Guardar').center), isTrue);
    expect(find.text('Cancelar'), findsNothing);
  });

  testWidgets('a landscape phone keeps them in the top bar', (tester) async {
    await _pump(tester, const Size(844, 390));
    final bar = tester.getRect(find.byType(AppBar));
    expect(bar.contains(_button(tester, 'Guardar').center), isTrue);
  });
}
