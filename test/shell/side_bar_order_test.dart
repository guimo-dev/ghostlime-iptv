import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/shell/app_shell.dart';
import 'package:iptv_player/ui/app_theme.dart';

void main() {
  testWidgets('the bottom of the side bar is Listas, then Ajustes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 700);
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
    // An error panel instead of the sections, so nothing loads.
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

    final lists = tester.getRect(find.text('Listas'));
    final settings = tester.getRect(find.text('Ajustes'));
    expect(lists.top, lessThan(settings.top));
  });
}
