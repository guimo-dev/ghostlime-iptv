import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/pin_scope.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';

import '../sync/fake_passwords.dart';

void main() {
  testWidgets('SettingsScreen creates the PIN in the injected store', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = CatalogDb.inMemory();
    final pins = MemoryPinStore();
    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(db),
        child: PinScope(
          store: pins,
          child: MaterialApp(
            home: SettingsScreen(db: db, passwords: FakePasswords()),
          ),
        ),
      ),
    );
    await tester.pump();
    Finder dialogField(int index) => find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .at(index);

    final lockSwitch = find.descendant(
      of: find
          .ancestor(
            of: find.text('Control parental con PIN'),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(lockSwitch);
    await tester.tap(lockSwitch);
    await tester.pumpAndSettle();
    await tester.enterText(dialogField(0), '1234');
    await tester.enterText(dialogField(1), '1234');
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(await pins.verify('1234'), isTrue);
  });
}
