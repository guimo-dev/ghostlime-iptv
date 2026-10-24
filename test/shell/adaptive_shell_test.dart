import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/shell/app_shell.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/form_factor.dart';

/// Pumps a "Listas" page and pushes the shell over it (showing its error
/// panel, so no section loads) on a screen of [size].
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AppShell(
                    db: db,
                    playlist: playlist,
                    passwords: MemoryPasswordStore(),
                  ),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  test('form factor goes by the shortest side', () {
    expect(formFactorOf(const Size(360, 640)), FormFactor.phone);
    expect(formFactorOf(const Size(640, 360)), FormFactor.phone);
    expect(formFactorOf(const Size(800, 1280)), FormFactor.tablet);
    expect(usesDesktopLayout(const Size(1280, 800)), isTrue);
    expect(usesDesktopLayout(const Size(800, 1280)), isFalse);
    expect(usesDesktopLayout(const Size(1024, 450)), isFalse);
  });

  for (final size in const [Size(360, 640), Size(640, 360), Size(800, 1280)]) {
    testWidgets('bottom bar with "Más" sheet at $size', (tester) async {
      await _pumpShell(tester, size);
      expect(find.byType(NavigationBar), findsOneWidget);
      for (final label in ['Inicio', 'Directo', 'Películas', 'Series', 'Más']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Listas'), findsNothing);
      await tester.tap(find.text('Más'));
      await tester.pumpAndSettle();
      expect(find.text('Listas'), findsOneWidget);
      expect(find.text('Ajustes'), findsOneWidget);
    });
  }

  testWidgets('"Listas" in the sheet returns to the playlists page', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(360, 640));
    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listas'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('wide tablet keeps the side bar', (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Listas'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
  });

  testWidgets('Back goes to Inicio from a section, then to Listas', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(360, 640));
    for (final section in ['Directo', 'Películas', 'Series']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(section),
        ),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(await navigator.maybePop(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsNothing, reason: 'still in the shell');
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    }
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
  });
}
