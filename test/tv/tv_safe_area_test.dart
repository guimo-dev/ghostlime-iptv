import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/tv/exit_dialog.dart';
import 'package:iptv_player/ui/focus_card.dart';
import 'package:iptv_player/vod/movie_detail_screen.dart';
import 'package:iptv_player/vod/series_detail_screen.dart';
import 'package:iptv_player/ui/tv_scale.dart';

import 'tv_harness.dart';

/// The part of the test view inside the TV safe margin (64 x 36 canvas
/// units around the 1280x720 canvas).
Rect _safeRect(WidgetTester tester) {
  final view = viewRect(tester);
  final scale = view.width / tvCanvasSize.width;
  return Rect.fromLTRB(
    tvSafeMargin.left * scale,
    tvSafeMargin.top * scale,
    view.width - tvSafeMargin.right * scale,
    view.height - tvSafeMargin.bottom * scale,
  );
}

/// Checks that every widget [finder] finds lies inside the safe margin.
void _expectInside(WidgetTester tester, Finder finder) {
  final safe = _safeRect(tester);
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    expect(
      safe.inflate(0.01).contains(rect.topLeft) &&
          safe.inflate(0.01).contains(rect.bottomRight),
      isTrue,
      reason: '$rect is outside $safe',
    );
  }
}

void main() {
  test('the safe margin is 64 x 36 canvas units', () {
    expect(
      tvSafeMargin,
      const EdgeInsets.symmetric(horizontal: 64, vertical: 36),
    );
  });

  testWidgets('the shell side bar stays inside the safe margin', (
    tester,
  ) async {
    useTvView(tester);
    final demo = TvDemo();
    addTearDown(demo.db.close);
    demo.db.saveWelcomeDone();
    demo.db.saveAcceptedTermsVersion(termsVersion);
    await tester.pumpWidget(
      IptvApp(
        db: demo.db,
        passwords: MemoryPasswordStore(),
        settings: SettingsController(demo.db),
        pins: MemoryPinStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    for (final label in ['Inicio', 'Directo', 'Series', 'Listas', 'Ajustes']) {
      _expectInside(tester, find.text(label).first);
    }
  });

  testWidgets('the playlist form Guardar stays inside the safe margin', (
    tester,
  ) async {
    useTvView(tester);
    final demo = TvDemo();
    addTearDown(demo.db.close);
    await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
    await tester.pumpAndSettle();

    _expectInside(tester, find.widgetWithText(FilledButton, 'Guardar'));
  });

  testWidgets('the movie page buttons stay inside the safe margin', (
    tester,
  ) async {
    useTvView(tester);
    final demo = TvDemo();
    addTearDown(demo.db.close);
    await pumpTvApp(
      tester,
      demo.db,
      MovieDetailScreen(
        db: demo.db,
        playlist: demo.playlist,
        passwords: MemoryPasswordStore(),
        movie: demo.movies.first,
      ),
    );
    await tester.pumpAndSettle();

    _expectInside(tester, find.byType(FilledButton));
    _expectInside(tester, find.byType(OutlinedButton));
  });

  testWidgets('the series seasons and episodes stay inside the safe margin', (
    tester,
  ) async {
    useTvView(tester);
    final demo = TvDemo();
    addTearDown(demo.db.close);
    await pumpTvApp(
      tester,
      demo.db,
      SeriesDetailScreen(
        db: demo.db,
        playlist: demo.playlist,
        passwords: MemoryPasswordStore(),
        series: demo.firstSeries,
        m3uEpisodes: demo.firstShow,
      ),
    );
    await tester.pumpAndSettle();

    _expectInside(tester, find.byType(FilledButton));
    _expectInside(tester, find.textContaining('Temporada'));
    // Only the rows on screen: the list scrolls.
    final safe = _safeRect(tester);
    final rows = find
        .byType(FocusCard)
        .evaluate()
        .where(
          (e) =>
              tester.getRect(find.byElementPredicate((x) => x == e)).top <
              safe.bottom,
        );
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final rect = tester.getRect(find.byElementPredicate((x) => x == row));
      expect(
        rect.left,
        greaterThanOrEqualTo(safe.left - 0.01),
        reason: '$rect',
      );
      expect(rect.right, lessThanOrEqualTo(safe.right + 0.01), reason: '$rect');
    }
  });

  testWidgets('dialog buttons stay inside the safe margin', (tester) async {
    useTvView(tester);
    final demo = TvDemo();
    addTearDown(demo.db.close);
    await pumpTvApp(
      tester,
      demo.db,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => confirmExit(context),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    _expectInside(tester, find.widgetWithText(TextButton, 'Cancelar'));
    _expectInside(tester, find.widgetWithText(FilledButton, 'Salir'));
  });
}
