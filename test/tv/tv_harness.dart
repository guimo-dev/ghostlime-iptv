import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/pin_scope.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/tv/remote_keys.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/tv_device.dart';
import 'package:iptv_player/ui/tv_scale.dart';

import '../../tool/demo_server/demo_data.dart';

/// Makes the test a TV: a 1080p screen at density 2 (960x540 logical, the
/// app sees its 1280x720 canvas) and [isTvDevice] on, both undone at the end.
void useTvView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  debugTvDevice = true;
  addTearDown(() {
    tester.view.reset();
    debugTvDevice = null;
  });
}

/// The demo catalog in a fresh in-memory database, as an M3U playlist (no
/// network), with a favourite, a recent channel and a movie half watched.
class TvDemo {
  TvDemo() {
    final id = db.savePlaylist(
      const Playlist(
        name: 'Lista demo',
        type: PlaylistType.m3uUrl,
        source: 'http://demo.invalid/get.php',
      ),
    );
    playlist = db.playlists().firstWhere((p) => p.id == id);
    db.replaceCatalog(
      id,
      [
        for (final MapEntry(:key, :value) in liveCategoryNames.entries)
          Category(id: key, name: value, kind: MediaKind.live),
        for (final MapEntry(:key, :value) in movieCategoryNames.entries)
          Category(id: key, name: value, kind: MediaKind.movie),
        for (final MapEntry(:key, :value) in seriesCategoryNames.entries)
          Category(id: key, name: value, kind: MediaKind.series),
      ],
      [...liveChannels, ...movies, ...episodes],
      DateTime.now(),
    );
    final now = DateTime.now();
    db.replaceEpg(id, [
      for (final p in demoProgrammes(now))
        Programme(
          channelId: p.channelId,
          start: p.start,
          stop: p.stop,
          title: p.title,
        ),
    ], now);
    db.setFavorite(id, MediaKind.live, liveChannels.first.key, true);
    db.setFavorite(id, MediaKind.movie, movies.first.key, true);
    db.addRecent(id, MediaKind.live, liveChannels[1].key);
    db.saveProgress(
      id,
      PlayTarget.fromChannel(movies.first),
      const Duration(minutes: 40),
      const Duration(minutes: 100),
    );
  }

  final db = CatalogDb.inMemory();
  late final Playlist playlist;

  final liveChannels = [
    for (final c in demoChannels)
      Channel(
        key: 'live-${c.id}',
        name: c.name,
        categoryId: c.categoryId,
        kind: MediaKind.live,
        epgId: c.epgId,
        url: 'http://demo.invalid/live/${c.id}.ts',
      ),
  ];

  final movies = [
    for (final m in demoMovies)
      Channel(
        key: 'movie-${m.id}',
        name: m.title,
        categoryId: m.categoryId,
        kind: MediaKind.movie,
        url: 'http://demo.invalid/movie/${m.id}.mp4',
      ),
  ];

  final episodes = [
    for (final s in demoSeries)
      for (final e in s.episodes)
        Channel(
          key: 'episode-${e.id}',
          name: '${s.title} S0${e.season}E0${e.number}',
          categoryId: s.categoryId,
          kind: MediaKind.series,
          url: 'http://demo.invalid/series/${e.id}.mp4',
        ),
  ];

  /// Episodes of the first demo show, as the series page gets them.
  List<Channel> get firstShow =>
      episodes.where((e) => e.name.startsWith(demoSeries.first.title)).toList();

  /// The first demo show as the series page gets it.
  Channel get firstSeries => Channel(
    key: 'show',
    name: demoSeries.first.title,
    categoryId: demoSeries.first.categoryId,
    kind: MediaKind.series,
  );
}

/// Pumps [home] as the app does on a TV (scaled canvas, remote shortcuts),
/// with settings on [db] and PINs in memory.
Future<void> pumpTvApp(
  WidgetTester tester,
  CatalogDb db,
  Widget home, {
  Map<Type, Action<Intent>> actions = const {},
}) async {
  await tester.pumpWidget(
    Actions(
      actions: actions,
      child: SettingsScope(
        controller: SettingsController(db),
        child: PinScope(
          store: MemoryPinStore(),
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: (context, child) =>
                TvScale(child: RemoteTextFieldKeys(child: child!)),
            shortcuts: appShortcuts(),
            home: home,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The widget with the primary focus, failing when there is none or it is
/// only a scope or an invisible key catcher.
FocusNode focusedNode() {
  final node = FocusManager.instance.primaryFocus;
  expect(node, isNotNull, reason: 'nothing has the focus');
  expect(node, isNot(isA<FocusScopeNode>()), reason: 'only a scope: $node');
  expect(node!.skipTraversal, isFalse, reason: 'not a useful widget: $node');
  expect(node.context, isNotNull);
  return node;
}

/// The view rectangle, in logical pixels.
Rect viewRect(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

/// Checks that something useful has the focus and that the arrows take it
/// to another visible widget: down first, then right, then (for dialogs
/// whose focused button is the last one) left and up.
Future<void> expectFocusAndArrows(WidgetTester tester) async {
  final first = focusedNode();
  expect(
    viewRect(tester).overlaps(first.rect),
    isTrue,
    reason: 'the focused widget is off screen: $first',
  );
  for (final key in [
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowUp,
  ]) {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final now = FocusManager.instance.primaryFocus;
    if (now != null && now != first) {
      final moved = focusedNode();
      expect(
        viewRect(tester).overlaps(moved.rect),
        isTrue,
        reason: 'the arrow moved the focus off screen: $moved',
      );
      return;
    }
  }
  fail('no arrow moves the focus away from $first');
}
