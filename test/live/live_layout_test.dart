import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/backdrop.dart';

const _channel = Channel(
  key: 'k',
  name: 'La 1',
  categoryId: 'c',
  kind: MediaKind.live,
);

final _longTitle = 'x' * 200;

Programme _programme(String title, {required int startMinutes}) {
  final now = DateTime.now().toUtc();
  return Programme(
    channelId: 'e',
    start: now.add(Duration(minutes: startMinutes)),
    stop: now.add(Duration(minutes: startMinutes + 60)),
    title: title,
    description: 'Descripción del programa',
  );
}

/// Pumps [child] in a window of [size] with the app theme.
Future<void> _pump(WidgetTester tester, Size size, Widget child) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    ),
  );
}

/// The progress track must be as wide as the title column above it, with a
/// visible gap before the "next" column (the column has no border of its own).
void _expectTrackSpansTitleColumn(WidgetTester tester) {
  final title = tester.getRect(find.text(_longTitle));
  final track = tester.getRect(find.byType(GradientProgress));
  final next = tester.getRect(find.textContaining('Siguiente programa'));
  expect(track.width, closeTo(title.width, 0.5));
  expect(track.left, closeTo(title.left, 0.5));
  expect(next.left - track.right, greaterThanOrEqualTo(16));
}

void main() {
  testWidgets('channels sharing a name are told apart in the list', (
    tester,
  ) async {
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
      const [Category(id: 'c', name: 'Cat', kind: MediaKind.live)],
      const [
        Channel(
          key: 'a',
          name: 'La 1',
          categoryId: 'c',
          kind: MediaKind.live,
          url: 'http://h/a',
        ),
        Channel(
          key: 'b',
          name: 'La 1',
          categoryId: 'c',
          kind: MediaKind.live,
          url: 'http://h/b',
        ),
      ],
      DateTime.now(),
    );
    await _pump(
      tester,
      const Size(1440, 900),
      SettingsScope(
        controller: SettingsController(db),
        child: LiveTvScreen(
          db: db,
          playlist: playlist,
          passwords: MemoryPasswordStore(),
        ),
      ),
    );
    await tester.tap(find.text('Cat'));
    await tester.pump();
    expect(find.text('La 1'), findsOneWidget);
    expect(find.text('La 1 · 2'), findsOneWidget);
  });

  for (final width in [1024.0, 2560.0]) {
    testWidgets('live list rows do not overflow (${width}px)', (tester) async {
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
        const [Category(id: 'c', name: 'Cat', kind: MediaKind.live)],
        const [
          Channel(
            key: 'k',
            name: 'La 1',
            categoryId: 'c',
            kind: MediaKind.live,
            epgId: 'e',
            url: 'http://h/1',
          ),
        ],
        DateTime.now(),
      );
      db.replaceEpg(playlist.id!, [
        _programme(_longTitle, startMinutes: -10),
        _programme('Siguiente programa', startMinutes: 50),
      ], DateTime.now());
      await _pump(
        tester,
        Size(width, 700),
        SettingsScope(
          controller: SettingsController(db),
          child: LiveTvScreen(
            db: db,
            playlist: playlist,
            passwords: MemoryPasswordStore(),
          ),
        ),
      );
      await tester.tap(find.text('Cat'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      _expectTrackSpansTitleColumn(tester);
    });
  }

  for (final width in [1024.0, 2560.0]) {
    testWidgets('long current title stays inside its column (${width}px)', (
      tester,
    ) async {
      await _pump(
        tester,
        Size(width, 700),
        ChannelRow(
          number: 1,
          channel: _channel,
          name: 'La 1',
          now: _programme(_longTitle, startMinutes: -10),
          next: _programme('Siguiente programa', startMinutes: 50),
          selected: false,
          favorite: false,
          onTap: () {},
          onToggleFavorite: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      _expectTrackSpansTitleColumn(tester);
    });
  }

  /// Pumps a [NowPanel] [width] logical pixels wide and returns nothing.
  Future<void> pumpPanel(
    WidgetTester tester,
    double width, {
    Programme? now,
    List<Programme> upcoming = const [],
  }) => _pump(
    tester,
    Size(width, 900),
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: NowPanel(
          channel: _channel,
          channelName: 'La 1',
          now: now,
          upcoming: upcoming,
          controller: null,
          failed: false,
          muted: true,
          favorite: false,
          onFullScreen: () {},
          onToggleSound: () {},
          onToggleFavorite: () {},
        ),
      ),
    ),
  );

  // The live area of a 1024x700 window: minus the shell and groups side bars.
  const smallPanelWidth = 1024.0 - 92 - 250;

  testWidgets('now panel text and button fit a small window', (tester) async {
    await pumpPanel(tester, smallPanelWidth);
    expect(tester.takeException(), isNull);
    // The test font is wider than the real one, so check the room the title
    // gets instead of whether it ellipsizes.
    final title = tester.getRect(find.text('Sin información'));
    expect(title.width, greaterThanOrEqualTo(300));
    expect(tester.getRect(find.byType(FilledButton)).height, lessThan(60));
  });

  testWidgets('a long day schedule scrolls inside a small panel', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      smallPanelWidth,
      now: _programme('Ahora', startMinutes: -10),
      upcoming: [
        for (var i = 1; i <= 12; i++)
          _programme('Luego $i', startMinutes: 50 + 60 * (i - 1)),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(GradientProgress, skipOffstage: false), findsOneWidget);
    // The test font is tall: the list may start below the fold, but every
    // programme can be scrolled into view.
    final list = find.descendant(
      of: find.byType(NowPanel),
      matching: find.byType(Scrollable),
    );
    expect(find.text('A continuación', skipOffstage: false), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Luego 12'),
      40,
      scrollable: list,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview grows with the panel', (tester) async {
    await pumpPanel(tester, smallPanelWidth);
    final small = tester.getRect(find.byType(AspectRatio)).width;
    await pumpPanel(tester, 2200);
    final large = tester.getRect(find.byType(AspectRatio)).width;
    expect(small, greaterThanOrEqualTo(240));
    expect(large, greaterThan(small * 1.5));
    expect(tester.takeException(), isNull);
  });
}
