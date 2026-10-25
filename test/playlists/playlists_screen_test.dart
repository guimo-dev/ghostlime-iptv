import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/playlists/playlists_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/content_width.dart';
import 'package:iptv_player/ui/focus_card.dart';

/// Pumps the playlists screen at [size] with [count] M3U playlists that only
/// have live channels.
Future<void> _pump(WidgetTester tester, Size size, {int count = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  for (var i = 1; i <= count; i++) {
    final unsaved = Playlist(
      name: 'Lista $i',
      type: PlaylistType.m3uUrl,
      source: 'http://h/$i.m3u',
    );
    final id = db.savePlaylist(unsaved);
    db.replaceCatalog(
      id,
      const [Category(id: 'c', name: 'Cat', kind: MediaKind.live)],
      const [
        Channel(
          key: 'k',
          name: 'La 1',
          categoryId: 'c',
          kind: MediaKind.live,
          url: 'http://h/1',
        ),
      ],
      DateTime.now(),
    );
  }
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: PlaylistsScreen(db: db, passwords: MemoryPasswordStore()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('counters at zero are not shown', (tester) async {
    await _pump(tester, const Size(1440, 900));
    expect(find.textContaining('1 directo'), findsOneWidget);
    expect(find.textContaining('películas'), findsNothing);
    expect(find.textContaining('series'), findsNothing);
  });

  testWidgets('cards form a centered grid of bounded width when maximized', (
    tester,
  ) async {
    await _pump(tester, const Size(2560, 1300), count: 12);
    final cards = [
      for (var i = 1; i <= 12; i++) tester.getRect(find.text('Lista $i')),
    ];
    final left = cards.map((r) => r.left).reduce(min);
    final right = cards.map((r) => r.right).reduce(max);
    // Wider than the old 360 px cards in a corner, but not the whole window.
    expect(right - left, greaterThan(1000));
    expect(right - left, lessThanOrEqualTo(ContentWidths.grid));
    expect((left + right) / 2, closeTo(1280, 120));
  });

  testWidgets('card actions have visible labels', (tester) async {
    await _pump(tester, const Size(1024, 700));
    expect(find.text('Actualizar'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final count in [1, 2]) {
    testWidgets('$count playlist(s) keep a normal card width when maximized', (
      tester,
    ) async {
      await _pump(tester, const Size(2560, 1300), count: count);
      final card = tester.getRect(find.byType(FocusCard).first);
      expect(card.width, lessThan(ContentWidths.grid / 2));
      expect(card.width, greaterThanOrEqualTo(360));
    });
  }

  testWidgets('phones get "Añadir lista" as a button at the bottom right', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 844));
    final button = find.ancestor(
      of: find.text('Añadir lista'),
      matching: find.byType(FloatingActionButton),
    );
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.top, greaterThan(844 * 2 / 3));
    expect(rect.right, greaterThan(390 - 32));
  });

  testWidgets('the desktop keeps "Añadir lista" in the header', (tester) async {
    await _pump(tester, const Size(1280, 800));
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.getRect(find.text('Añadir lista')).top, lessThan(200));
  });
}
