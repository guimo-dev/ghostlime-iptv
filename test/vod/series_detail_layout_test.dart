import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/content_width.dart';
import 'package:iptv_player/ui/focus_card.dart';
import 'package:iptv_player/vod/series_detail_screen.dart';

/// Pumps a series page with three M3U episodes at [size].
Future<void> _pump(WidgetTester tester, Size size) async {
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
  Channel episode(int number) => Channel(
    key: 'e$number',
    name: 'Show S01E0$number',
    categoryId: 'c',
    kind: MediaKind.series,
    url: 'http://h/$number',
  );
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: SeriesDetailScreen(
          db: db,
          playlist: playlist,
          passwords: MemoryPasswordStore(),
          series: const Channel(
            key: 's',
            name: 'Show',
            categoryId: 'c',
            kind: MediaKind.series,
          ),
          m3uEpisodes: [episode(1), episode(2), episode(3)],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('episode rows are bounded in width and touch each other', (
    tester,
  ) async {
    await _pump(tester, const Size(2560, 1300));
    final rows = [
      for (var i = 0; i < 3; i++) tester.getRect(find.byType(FocusCard).at(i)),
    ];
    for (final row in rows) {
      expect(row.width, lessThanOrEqualTo(ContentWidths.reading));
    }
    // No strip of the blurred backdrop between rows.
    expect(rows[1].top - rows[0].bottom, lessThanOrEqualTo(1));
    expect(rows[2].top - rows[1].bottom, lessThanOrEqualTo(1));
  });

  for (final size in const [Size(1024, 700), Size(2560, 1300)]) {
    testWidgets('season chips start where the episode rows do at $size', (
      tester,
    ) async {
      await _pump(tester, size);
      final chip = tester.getRect(find.byType(ChoiceChip).first);
      final row = tester.getRect(find.byType(FocusCard).first);
      expect(chip.left, closeTo(row.left, 0.5));
    });
  }
}
