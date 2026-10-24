import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/home/home_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/backdrop.dart';
import 'package:iptv_player/ui/content_width.dart';

/// Pumps the home of a playlist with a favorite channel and a movie, both
/// named "canal …", in a window of [size].
Future<void> _pumpHome(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  final unsaved = Playlist(
    name: 'Lista',
    type: PlaylistType.m3uUrl,
    source: 'http://h/l.m3u',
  );
  final playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
  db.replaceCatalog(
    playlist.id!,
    const [
      Category(id: 'c', name: 'Cat', kind: MediaKind.live),
      Category(id: 'm', name: 'Pelis', kind: MediaKind.movie),
    ],
    const [
      Channel(
        key: 'k',
        name: 'Canal uno',
        categoryId: 'c',
        kind: MediaKind.live,
        url: 'http://h/1',
      ),
      Channel(
        key: 'p',
        name: 'El canal perdido',
        categoryId: 'm',
        kind: MediaKind.movie,
        url: 'http://h/p.mp4',
      ),
    ],
    DateTime.now(),
  );
  db.setFavorite(playlist.id!, MediaKind.live, 'k', true);
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          // As in the shell: the app background sits between the page's
          // Material and the home.
          body: AppBackground(
            child: HomeScreen(
              db: db,
              playlist: playlist,
              passwords: MemoryPasswordStore(),
              onOpenSection: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Types [query] in the home search field and waits for the results.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('typing searches every kind instead of showing the rails', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(1440, 900));
    expect(find.text('Canales favoritos'), findsOneWidget);

    await _search(tester, 'canal');

    expect(find.text('Canales favoritos'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Canal uno'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'El canal perdido'), findsOneWidget);
  });

  testWidgets('Esc empties the field and brings the rails back', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(1440, 900));
    await _search(tester, 'canal');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Canales favoritos'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('Esc also empties the search from a focused result', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(1440, 900));
    await _search(tester, 'canal');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    expect(field.widget.focusNode.hasFocus, isFalse, reason: 'on a result');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Canales favoritos'), findsOneWidget);
  });

  testWidgets('clearing the text by hand also brings the rails back', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(1440, 900));
    await _search(tester, 'canal');
    await _search(tester, '');
    expect(find.text('Canales favoritos'), findsOneWidget);
  });

  testWidgets('results are roomy and bounded when maximized', (tester) async {
    await _pumpHome(tester, const Size(2560, 1300));
    await _search(tester, 'canal');
    final result = tester.getRect(find.byType(ListTile).first);
    expect(result.width, lessThanOrEqualTo(ContentWidths.reading));
    expect(result.height, greaterThanOrEqualTo(72));
    expect(tester.takeException(), isNull);
  });
}
