import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/guide_grid.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/ui/app_theme.dart';

const _withGuide = Channel(
  key: 'a',
  name: 'Uno',
  categoryId: 'c',
  kind: MediaKind.live,
  epgId: 'e1',
);
const _withoutGuide = Channel(
  key: 'b',
  name: 'Dos',
  categoryId: 'c',
  kind: MediaKind.live,
);

void main() {
  late CatalogDb db;
  late int playlistId;
  late List<Channel> tapped;

  setUp(() {
    db = CatalogDb.inMemory();
    const unsaved = Playlist(
      name: 'Lista',
      type: PlaylistType.m3uUrl,
      source: 'http://h/l.m3u',
    );
    playlistId = db.savePlaylist(unsaved);
    final now = DateTime.now().toUtc();
    db.replaceEpg(playlistId, [
      Programme(
        channelId: 'e1',
        start: now.subtract(const Duration(minutes: 20)),
        stop: now.add(const Duration(minutes: 10)),
        title: 'Noticias',
      ),
    ], DateTime.now());
    tapped = [];
  });
  tearDown(() => db.close());

  Future<void> pumpGrid(
    WidgetTester tester, {
    int revision = 0,
    Size size = const Size(1200, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: GuideGrid(
            db: db,
            playlistId: playlistId,
            channels: const [_withGuide, _withoutGuide],
            names: const {'a': 'Uno · 1'},
            selectedKey: null,
            onChannel: tapped.add,
            revision: revision,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('narrow grid keeps channel names on one line', (tester) async {
    await pumpGrid(tester, size: const Size(390, 844));
    final name = tester.widget<Text>(find.text('Uno · 1'));
    expect(name.maxLines, 1);
    expect(name.softWrap, isFalse);
    expect(name.overflow, TextOverflow.ellipsis);
  });

  testWidgets('wide grid lets channel names take two lines', (tester) async {
    await pumpGrid(tester);
    expect(tester.widget<Text>(find.text('Uno · 1')).maxLines, 2);
  });

  testWidgets('shows the given channels with their display names', (
    tester,
  ) async {
    await pumpGrid(tester);
    expect(find.text('Uno · 1'), findsOneWidget);
    expect(find.text('Dos'), findsOneWidget);
    expect(find.text('Noticias'), findsOneWidget);
    expect(find.text('Sin guía'), findsOneWidget);
  });

  testWidgets('tapping a programme or a channel picks that channel', (
    tester,
  ) async {
    await pumpGrid(tester);
    await tester.tap(find.text('Noticias'));
    await tester.tap(find.text('Dos'));
    expect(tapped.map((c) => c.key), ['a', 'b']);
  });

  testWidgets('"Solo con guía" hides channels without programmes', (
    tester,
  ) async {
    await pumpGrid(tester);
    await tester.tap(find.text('Solo con guía'));
    await tester.pump();
    expect(find.text('Dos'), findsNothing);
    expect(find.text('Uno · 1'), findsOneWidget);
  });

  testWidgets('the arrows move the time window', (tester) async {
    await pumpGrid(tester);
    final before = find.textContaining('–').evaluate().single.widget as Text;
    await tester.tap(find.byTooltip('Después'));
    await tester.tap(find.byTooltip('Después'));
    await tester.pump();
    final after = find.textContaining('–').evaluate().single.widget as Text;
    expect(after.data, isNot(before.data));
    expect(find.text('Noticias'), findsNothing, reason: 'out of the window');
  });

  testWidgets('a new revision reads the guide again', (tester) async {
    await pumpGrid(tester);
    final now = DateTime.now().toUtc();
    db.replaceEpg(playlistId, [
      Programme(
        channelId: 'e1',
        start: now.subtract(const Duration(minutes: 20)),
        stop: now.add(const Duration(minutes: 10)),
        title: 'Deportes',
      ),
    ], DateTime.now());
    await pumpGrid(tester);
    expect(find.text('Noticias'), findsOneWidget, reason: 'same revision');
    await pumpGrid(tester, revision: 1);
    expect(find.text('Deportes'), findsOneWidget);
  });
}
