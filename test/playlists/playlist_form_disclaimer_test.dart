import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';

void main() {
  testWidgets('add-playlist form shows the no-content disclaimer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(CatalogDb.inMemory()),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const PlaylistFormScreen(),
        ),
      ),
    );
    expect(
      find.text(
        'Ghostlime no proporciona contenido. Añade solo listas que tengas '
        'derecho a usar.',
      ),
      findsOneWidget,
    );
  });
}
