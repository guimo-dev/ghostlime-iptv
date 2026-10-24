import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_sync.dart';
import 'package:iptv_player/home/home_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/shell/app_shell.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/brand_state.dart';

void main() {
  late Directory dir;
  late CatalogDb db;
  late Playlist playlist;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ghostlime_shell_');
    db = CatalogDb.inMemory();
    final unsaved = Playlist(
      name: 'Fichero',
      type: PlaylistType.m3uFile,
      source: '${dir.path}/lista.m3u',
    );
    playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
    db.saveSyncError(playlist.id!, 'No se puede leer el fichero de la lista.');
  });

  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  /// Taps "Reintentar" with real async, so the file read completes, then
  /// pumps the result.
  Future<void> retry(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Reintentar'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  testWidgets('a playlist whose refresh failed shows the error, not Home', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.text('No se ha podido cargar la lista'), findsOneWidget);
    expect(
      find.text('No se puede leer el fichero de la lista.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(BrandMessage), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('retrying after fixing the source opens Home', (tester) async {
    await pumpShell(tester);
    File(playlist.source!).writeAsStringSync(
      '#EXTM3U\n#EXTINF:-1 group-title="G",Canal\nhttp://h/1\n',
    );

    await retry(tester);

    expect(find.text('No se ha podido cargar la lista'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(db.syncError(playlist.id!), isNull);
  });

  testWidgets('a background refresh that succeeds replaces the error', (
    tester,
  ) async {
    await pumpShell(tester);
    File(playlist.source!).writeAsStringSync(
      '#EXTM3U\n#EXTINF:-1 group-title="G",Canal\nhttp://h/1\n',
    );

    // As the playlists screen does behind the shell.
    await tester.runAsync(() => syncPlaylist(db, playlist));
    await tester.pump();

    expect(find.text('No se ha podido cargar la lista'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a failed retry keeps the error on screen', (tester) async {
    await pumpShell(tester);

    await retry(tester);

    expect(
      find.text('No se puede leer el fichero de la lista.'),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsNothing);
  });
}
