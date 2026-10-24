import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/shell/app_shell.dart';
import 'package:iptv_player/ui/app_theme.dart';

/// Pumps the shell (showing its error panel, so no section loads) at [size].
Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  final unsaved = Playlist(
    name: 'Lista',
    type: PlaylistType.m3uFile,
    source: 'no-existe.m3u',
  );
  final playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
  db.saveSyncError(playlist.id!, 'Error de prueba.');
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: AppShell(
          db: db,
          playlist: playlist,
          passwords: MemoryPasswordStore(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('side bar has no guide or search: Live and Home have them', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(1024, 700));
    for (final label in ['Inicio', 'Directo', 'Películas', 'Series']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Buscar'), findsNothing);
    expect(find.text('Guía'), findsNothing);
  });

  for (final size in const [Size(1024, 700), Size(1024, 450)]) {
    testWidgets('side bar reaches "Listas" without overflow ($size)', (
      tester,
    ) async {
      await _pumpShell(tester, size);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Listas'));
      await tester.pump();
      expect(tester.getRect(find.text('Listas')).bottom, lessThan(size.height));
    });
  }
}
