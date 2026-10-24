import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/guide_grid.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/backdrop.dart';

const _channel = Channel(
  key: 'k',
  name: 'La 1',
  categoryId: 'c',
  kind: MediaKind.live,
  epgId: 'e',
);

/// A programme from 10:00 to 11:00 UTC on a day long gone, so the real
/// clock would show it finished.
final _programme = Programme(
  channelId: 'e',
  start: DateTime.utc(2020, 3, 2, 10),
  stop: DateTime.utc(2020, 3, 2, 11),
  title: 'Noticias',
);

/// A quarter of the way into [_programme].
DateTime _fixedClock() => DateTime.utc(2020, 3, 2, 10, 15);

/// Pumps [child] in a 1440x900 window with the app theme.
Future<void> _pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('a channel row shows progress at the given clock', (
    tester,
  ) async {
    await _pump(
      tester,
      ChannelRow(
        number: 1,
        channel: _channel,
        name: 'La 1',
        now: _programme,
        next: null,
        selected: false,
        favorite: false,
        onTap: () {},
        onToggleFavorite: () {},
        clock: _fixedClock,
      ),
    );
    final progress = tester.widget<GradientProgress>(
      find.byType(GradientProgress),
    );
    expect(progress.value, closeTo(0.25, 0.001));
  });

  testWidgets('the now panel counts minutes left at the given clock', (
    tester,
  ) async {
    await _pump(
      tester,
      NowPanel(
        channel: _channel,
        channelName: 'La 1',
        now: _programme,
        upcoming: const [],
        controller: null,
        failed: false,
        muted: true,
        favorite: false,
        onFullScreen: () {},
        onToggleSound: () {},
        onToggleFavorite: () {},
        clock: _fixedClock,
      ),
    );
    expect(
      find.textContaining('quedan 45 min', skipOffstage: false),
      findsOneWidget,
    );
    final progress = tester.widget<GradientProgress>(
      find.byType(GradientProgress, skipOffstage: false),
    );
    expect(progress.value, closeTo(0.25, 0.001));
  });

  testWidgets('the guide grid opens its window around the given clock', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final playlistId = db.savePlaylist(
      const Playlist(
        name: 'Lista',
        type: PlaylistType.m3uUrl,
        source: 'http://h/l.m3u',
      ),
    );
    db.replaceEpg(playlistId, [_programme], DateTime.utc(2020, 3, 2));
    await _pump(
      tester,
      GuideGrid(
        db: db,
        playlistId: playlistId,
        channels: const [_channel],
        names: const {},
        selectedKey: null,
        onChannel: (_) {},
        clock: _fixedClock,
      ),
    );
    await tester.pump();
    // The programme of 2020 is only in the window if the grid used the clock.
    expect(find.text('Noticias'), findsOneWidget);
    final start = formatClock(DateTime.utc(2020, 3, 2, 9, 30));
    final end = formatClock(DateTime.utc(2020, 3, 2, 12, 30));
    expect(find.text('$start–$end'), findsOneWidget);
  });
}
