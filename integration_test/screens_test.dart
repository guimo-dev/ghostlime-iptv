import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/live/live_phone_view.dart'
    show PhoneChannelRow, PhoneSchedule;
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/settings/app_settings.dart' show AccentColor;
import 'package:iptv_player/settings/parental_session.dart';
import 'package:iptv_player/browse/catalog_images.dart' show ChannelLogo;
import 'package:iptv_player/ui/backdrop.dart' show GradientProgress;
import 'package:iptv_player/ui/focus_card.dart';
import 'package:iptv_player/ui/form_factor.dart' show usesDesktopLayout;
import 'package:iptv_player/ui/tv_device.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show MaterialDesktopSeekBar, Video;

import '../tool/demo_server/demo_data.dart';
import 'support/golden.dart';
import 'support/harness.dart';

/// Captures one screen: reaches it from a fresh [AppHarness] and calls
/// `expectScreen` with [name].
typedef _Capture = Future<void> Function(
  WidgetTester tester,
  AppHarness harness,
  String name,
);

/// Name of the playlist every test adds.
const _playlistName = 'Demo';

/// Whether the test window gets the phone layout (bottom bar, Directo for
/// zapping): the `phone` and `tablet` sizes.
bool _phoneLayout(WidgetTester tester) =>
    !usesDesktopLayout(tester.view.physicalSize / tester.view.devicePixelRatio);

/// The channel rows of Directo: [PhoneChannelRow] in the phone layout,
/// [ChannelRow] otherwise.
Finder _channelRows(WidgetTester tester) =>
    find.byType(_phoneLayout(tester) ? PhoneChannelRow : ChannelRow);

/// Scrolls [scrollable] in steps of [delta] until [finder] is built, then
/// brings it into view, like `WidgetTester.scrollUntilVisible`. On Android
/// it jumps the scroll position instead of dragging: on the emulator the
/// test's drags did not move the lists.
Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder finder,
  double delta, {
  required Finder scrollable,
}) async {
  if (!Platform.isAndroid) {
    await tester.scrollUntilVisible(finder, delta, scrollable: scrollable);
    return;
  }
  final position = tester.state<ScrollableState>(scrollable).position;
  while (finder.evaluate().isEmpty &&
      position.pixels < position.maxScrollExtent) {
    position.jumpTo(
      math.min(position.pixels + delta, position.maxScrollExtent),
    );
    await tester.pump();
  }
  await tester.ensureVisible(finder);
}

/// Pumps (letting real time pass) until [done] is true; fails after [limit].
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 25),
}) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < limit) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue, reason: 'condition not met within $limit');
}

/// Lets [duration] of real time pass while pumping, e.g. for video to play.
Future<void> _pumpRealTime(WidgetTester tester, Duration duration) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Types [text] into the field [finder]. On a TV a field stays read-only
/// until it is opened (OK on the remote or a tap), so it is tapped first.
Future<void> _typeInto(WidgetTester tester, Finder finder, String text) async {
  if (isTvDevice) {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
  await tester.enterText(finder, text);
}

/// Opens the "Añadir lista" form from the playlists screen.
Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.text('Añadir lista'));
  await tester.pumpAndSettle();
}

/// Fills the Xtream form with the demo server and [password].
Future<void> _fillXtreamForm(
  WidgetTester tester,
  AppHarness harness, {
  String password = demoPassword,
}) async {
  Future<void> fill(String label, String value) =>
      _typeInto(tester, find.widgetWithText(TextFormField, label), value);
  await fill('Nombre', _playlistName);
  await fill('Servidor', harness.server.baseUrl.toString());
  await fill('Usuario', demoUser);
  await fill('Contraseña', password);
}

/// On a TV, scrolls the form holding [error] back to its top: typing scrolled
/// the last field up (room for the floating keyboard), past the error.
Future<void> _formToTopOnTv(WidgetTester tester, Finder error) async {
  if (!isTvDevice) return;
  final form = find.ancestor(of: error, matching: find.byType(Scrollable));
  tester.state<ScrollableState>(form.first).position.jumpTo(0);
  await tester.pumpAndSettle();
}

/// Mask for the demo server address, whose port changes on every run.
Finder _serverField() => find.widgetWithText(TextFormField, 'Servidor');

/// Adds the demo Xtream playlist through the form and waits until its catalog
/// and guide are downloaded and the playlists screen is idle again.
Future<void> _addPlaylist(WidgetTester tester, AppHarness harness) async {
  await _openForm(tester);
  await _fillXtreamForm(tester, harness);
  await tester.tap(find.text('Guardar'));
  await _pumpUntil(tester, () => harness.db.playlists().isNotEmpty);
  final id = harness.db.playlists().single.id!;
  await _pumpUntil(
    tester,
    () =>
        harness.db.playlists().single.refreshedAt != null &&
        harness.db.epgRefreshedAt(id) != null,
  );
  await _pumpUntil(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

/// Id of the playlist added by [_addPlaylist].
int _playlistId(AppHarness harness) => harness.db.playlists().single.id!;

/// Replaces the guide with fixed titles: every demo channel has a programme
/// from an hour ago to an hour ahead and the next one for two hours more. With
/// [forGuideGrid], it also lays programmes on the window the guide grid shows
/// after moving forward twice, so their cells never depend on the time of day.
void _seedGuide(AppHarness harness, {bool forGuideGrid = false}) {
  final now = DateTime.now();
  final onAirStart = now.toUtc().subtract(const Duration(hours: 1));
  final rounded = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute < 30 ? 0 : 30,
  );
  final guideStart = rounded
      .subtract(const Duration(minutes: 30))
      .add(const Duration(hours: 2))
      .toUtc();
  final programmes = <Programme>[];
  for (final channel in demoChannels) {
    if (forGuideGrid) {
      for (var slot = -1; slot < 4; slot++) {
        final start = guideStart.add(Duration(minutes: 90 * slot));
        programmes.add(
          Programme(
            channelId: channel.epgId,
            start: start,
            stop: start.add(const Duration(minutes: 90)),
            title: 'Programa ${(slot + channel.id) % 5 + 1}',
            description: 'Descripción de ejemplo.',
          ),
        );
      }
    } else {
      programmes
        ..add(
          Programme(
            channelId: channel.epgId,
            start: onAirStart,
            stop: onAirStart.add(const Duration(hours: 2)),
            title: 'En emisión ${channel.id}',
            description: 'Descripción de ejemplo del programa en emisión.',
          ),
        )
        ..add(
          Programme(
            channelId: channel.epgId,
            start: onAirStart.add(const Duration(hours: 2)),
            stop: onAirStart.add(const Duration(hours: 4)),
            title: 'Después ${channel.id}',
          ),
        );
    }
  }
  harness.db.replaceEpg(_playlistId(harness), programmes, DateTime.now());
}

/// Channels (or movies, or series) of [kind] in the first [categories] of the
/// catalog, in catalog order.
List<Channel> _items(AppHarness harness, MediaKind kind, {int categories = 1}) {
  final id = _playlistId(harness);
  return [
    for (final category in harness.db.categories(id, kind).take(categories))
      ...harness.db.channels(id, category.id),
  ];
}

/// Marks the first [count] items of [kind] as favorites.
void _seedFavorites(AppHarness harness, MediaKind kind, int count) {
  final id = _playlistId(harness);
  for (final item in _items(harness, kind).take(count)) {
    harness.db.setFavorite(id, kind, item.key, true);
  }
}

/// Marks the first [count] items of [kind] as watched, at fixed times.
void _seedRecents(AppHarness harness, MediaKind kind, int count) {
  final id = _playlistId(harness);
  final items = _items(harness, kind, categories: 2).skip(1).take(count);
  for (final (index, item) in items.indexed) {
    harness.db.addRecent(
      id,
      kind,
      item.key,
      at: DateTime(2026, 1, 1, 12, index),
    );
  }
}

/// Leaves the first [count] movies half watched, at fixed times.
void _seedProgress(AppHarness harness, int count) {
  final id = _playlistId(harness);
  final movies = _items(harness, MediaKind.movie, categories: 2).take(count);
  for (final (index, movie) in movies.indexed) {
    harness.db.saveProgress(
      id,
      PlayTarget.fromChannel(movie),
      Duration(minutes: 20 + index * 15),
      const Duration(minutes: 100),
      at: DateTime(2026, 1, 1, 12, index),
    );
  }
}

/// Seeds what the playlist home shows: favorites of each kind, recent
/// channels and unfinished movies.
void _seedHome(AppHarness harness) {
  _seedGuide(harness);
  _seedFavorites(harness, MediaKind.live, 3);
  _seedFavorites(harness, MediaKind.movie, 3);
  _seedFavorites(harness, MediaKind.series, 3);
  _seedRecents(harness, MediaKind.live, 3);
  _seedProgress(harness, 3);
}

/// Opens the added playlist from the playlists screen.
Future<void> _openPlaylist(WidgetTester tester) async {
  await tester.tap(find.text(_playlistName));
  await settle(tester, timeout: const Duration(seconds: 2));
}

/// Adds the playlist, runs [seed] on the harness, opens the playlist and goes
/// to the side-bar section named [section] when given.
Future<void> _enter(
  WidgetTester tester,
  AppHarness harness, {
  void Function(AppHarness harness)? seed,
  String? section,
}) async {
  await settle(tester);
  await _addPlaylist(tester, harness);
  seed?.call(harness);
  await _openPlaylist(tester);
  if (section != null) await _goTo(tester, section);
}

/// The poster card of the browse grid item titled [title] (the title itself
/// is outside the tappable card).
Finder _posterOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Column)).first,
  matching: find.byType(FocusCard),
);

/// Taps the side-bar button [section], or its bottom-bar destination in the
/// phone layout (Inicio has a "Directo" button of its own).
Future<void> _goTo(WidgetTester tester, String section) async {
  await tester.tap(
    _phoneLayout(tester)
        ? find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(section),
          )
        : find.text(section).first,
  );
  await settle(tester, timeout: const Duration(seconds: 2));
}

/// Opens the settings of the open playlist: the side-bar "Ajustes", or
/// "Más" > "Ajustes" in the phone layout.
Future<void> _openPlaylistSettings(WidgetTester tester) async {
  if (_phoneLayout(tester)) {
    await tester.tap(find.text('Más'));
    await settle(tester, timeout: const Duration(seconds: 2));
  }
  await tester.tap(find.text('Ajustes'));
  await settle(tester);
}

/// Taps the category chip [label]; in the phone layout it is scrolled into
/// view first, since the chips run past the screen's edge (and are built
/// lazily).
Future<void> _tapChip(WidgetTester tester, String label) async {
  if (_phoneLayout(tester)) {
    await _scrollUntilVisible(
      tester,
      find.text(label),
      100,
      scrollable: find
          .ancestor(
            of: find.text('Continuar viendo'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // Lay the scrolled chips out before tapping, or the tap lands where the
    // chip was before the scroll.
    await tester.pump();
  }
  await tester.tap(find.text(label));
  await settle(tester);
}

/// Taps Directo's "Orden": a button with its label, or only its icon in the
/// phone layout.
Future<void> _tapLiveSort(WidgetTester tester) async {
  await tester.tap(
    _phoneLayout(tester) ? find.byTooltip('Orden') : find.text('Orden'),
  );
  await tester.pumpAndSettle();
}

/// Masks for everything in live TV that follows the clock or the preview:
/// start times (rows and the day's schedule), time left and progress; in the
/// phone layout also the schedule's progress and the preview.
List<Finder> _liveMasks() => [
  find.textContaining(RegExp(r'^\d\d:\d\d')),
  find.textContaining('quedan'),
  find.descendant(
    of: find.byType(NowPanel),
    matching: find.byType(GradientProgress),
  ),
  _programmeProgress(),
  find.descendant(
    of: find.byType(NowPanel),
    matching: find.byType(AspectRatio),
  ),
  find.descendant(
    of: find.byType(PhoneSchedule),
    matching: find.byType(GradientProgress),
  ),
  find.byType(LivePreviewBox),
];

/// Masks for the clocks of the guide grid: the time labels and its header
/// row, whose controls move sideways with the width of the "HH:mm–HH:mm"
/// button. On a narrow grid (a phone) that header is a `Wrap`.
List<Finder> _guideMasks() {
  final wrap = find.ancestor(
    of: find.byType(FilterChip),
    matching: find.byType(Wrap),
  );
  return [
    find.textContaining(RegExp(r'^\d\d:\d\d')),
    wrap.evaluate().isNotEmpty
        ? wrap.first
        : find
              .ancestor(of: find.byType(FilterChip), matching: find.byType(Row))
              .first,
  ];
}

/// Mask for the content of the playlist cards: the subtitle (counts and "hace
/// N min") changes width, so its own rectangle would leave part of it visible.
List<Finder> _playlistsMasks() => [
  find
      .ancestor(
        of: find.textContaining(RegExp(r'directo|Sin actualizar|Actualizando')),
        matching: find.byType(Column),
      )
      .first,
];

/// Mask for the progress bars of programmes on air in channel rows and cards:
/// their fill follows the clock.
Finder _programmeProgress() => find.descendant(
  of: find.ancestor(
    of: find.byType(ChannelLogo),
    matching: find.byType(FocusCard),
  ),
  matching: find.byType(GradientProgress),
);

/// Plays the second live channel full screen and waits for the clip to play.
Future<void> _playLive(WidgetTester tester) async {
  final row = _channelRows(tester).at(1);
  await tester.tap(row);
  await settle(tester, timeout: const Duration(seconds: 2));
  await tester.tap(row);
  await _pumpUntil(
    tester,
    () => find.byType(PlayerScreen).evaluate().isNotEmpty,
  );
  await _freezePlayback(tester);
}

/// Waits until the clip is playing and pauses it, so nothing moves while the
/// screen is captured. The position itself still differs from run to run: the
/// callers mask the position text and the seek bar.
Future<void> _freezePlayback(WidgetTester tester) async {
  final video = find.descendant(
    of: find.byType(PlayerScreen),
    matching: find.byType(Video),
  );
  final player = tester.widget<Video>(video).controller.player;
  await _pumpUntil(
    tester,
    () => player.state.position > Duration.zero,
    limit: const Duration(seconds: 20),
  );
  await tester.runAsync(player.pause);
  await _pumpUntil(tester, () => !player.state.playing);
  await _pumpRealTime(tester, const Duration(seconds: 1));
}

/// Removes the picture of every video so its controls and overlays show over
/// black: the frames change from run to run, and masking the whole `Video`
/// would hide the overlays too. Fails if any texture is still on screen, since
/// a real frame in a reference would make it differ on every run.
Future<void> _hideVideoPictures(WidgetTester tester) async {
  for (final video in tester.widgetList<Video>(find.byType(Video))) {
    video.controller.notifier.value!.id.value = null;
  }
  await tester.pump();
  expect(
    find.byType(Texture),
    findsNothing,
    reason: 'video picture not hidden',
  );
}

/// Waits (in real time) until the current half hour has just started, so the
/// guide window the seed is laid on is still the one the screen computes a few
/// seconds later.
Future<void> _waitForHalfHourStart(WidgetTester tester) async {
  bool nearEnd() {
    final now = DateTime.now();
    return (now.minute % 30) * 60 + now.second > 30 * 60 - 20;
  }

  while (nearEnd()) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
  }
}

/// Whether [_registerDemoLicenses] already ran in this process.
var _demoLicensesRegistered = false;

/// The test binding loads no licenses, so the licenses page would be empty:
/// registers two fixed packages (once per process, so repeated runs show the
/// same list).
void _registerDemoLicenses() {
  if (_demoLicensesRegistered) return;
  _demoLicensesRegistered = true;
  LicenseRegistry.addLicense(
    () => Stream.fromIterable([
      const LicenseEntryWithLineBreaks(['demo_player'], 'Licencia de ejemplo.'),
      const LicenseEntryWithLineBreaks(['demo_ui'], 'Licencia de ejemplo.'),
    ]),
  );
}

/// Scrolls the settings page until [finder] is visible.
Future<void> _scrollSettingsTo(WidgetTester tester, Finder finder) async {
  await _scrollUntilVisible(
    tester,
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Taps the "Control parental con PIN" switch and types a PIN into the dialog.
Future<void> _startParentalLock(WidgetTester tester) async {
  await _openPlaylistSettings(tester);
  final title = find.text('Control parental con PIN');
  await _scrollSettingsTo(tester, title);
  final row = find.ancestor(of: title, matching: find.byType(Row)).first;
  await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
  await tester.pumpAndSettle();
}

/// Screens that start signed in: parental control needs an account.
const _signedInScreens = {'ajustes-control-parental', 'pin'};

/// Screens that start as a new installation, with the welcome.
const _firstRunScreens = {'bienvenida', 'aviso-legal'};

/// The account's "Última sincronización: dd/mm hh:mm" line, which shows the
/// time of the run.
Finder _lastSyncMask() => find.textContaining('Última sincronización');

/// Captures the first-run screen as [name] without focus or hover
/// highlights: a button may keep the focus and a mouse left by an earlier
/// test may hover it, so the pointer is parked away, the focus dropped and
/// the highlights left to fade.
Future<void> _expectFirstRunScreen(WidgetTester tester, String name) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  try {
    await mouse.addPointer(location: const Offset(-10, -10));
    FocusManager.instance.primaryFocus?.unfocus();
    await _pumpRealTime(tester, const Duration(seconds: 1));
    await expectScreen(tester, name);
  } finally {
    await mouse.removePointer();
  }
}

/// Every screen, by the name of its reference image.
final Map<String, _Capture> _screens = {
  'bienvenida': (tester, harness, name) async {
    await settle(tester);
    // The legal notice opens first: accept it to show the welcome options.
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    await _expectFirstRunScreen(tester, name);
  },
  // The legal notice as it opens over the welcome: a dialog in the desktop
  // layout, a sheet from the bottom in the phone layout.
  'aviso-legal': (tester, harness, name) async {
    await settle(tester);
    expect(find.text('Aceptar'), findsOneWidget);
    await _expectFirstRunScreen(tester, name);
  },
  'inicio-vacio': (tester, harness, name) async {
    await _enter(tester, harness);
    await expectScreen(tester, name);
  },
  'listas': (tester, harness, name) async {
    await settle(tester);
    await _addPlaylist(tester, harness);
    await settle(tester);
    await expectScreen(tester, name, masks: _playlistsMasks());
  },
  'form-xtream': (tester, harness, name) async {
    await settle(tester);
    await _openForm(tester);
    await expectScreen(tester, name);
  },
  'form-m3u-url': (tester, harness, name) async {
    await settle(tester);
    await _openForm(tester);
    await tester.tap(find.text('M3U (URL)'));
    await tester.pumpAndSettle();
    await expectScreen(tester, name);
  },
  'form-m3u-archivo': (tester, harness, name) async {
    await settle(tester);
    await _openForm(tester);
    await tester.tap(find.text('M3U (fichero)'));
    await tester.pumpAndSettle();
    await expectScreen(tester, name);
  },
  'form-error-credenciales': (tester, harness, name) async {
    await settle(tester);
    await _openForm(tester);
    await _fillXtreamForm(tester, harness, password: 'mal');
    await tester.tap(find.text('Guardar'));
    await _pumpUntil(
      tester,
      () => find
          .textContaining('rechazado las credenciales')
          .evaluate()
          .isNotEmpty,
    );
    await _formToTopOnTv(tester, find.textContaining('rechazado'));
    await tester.pumpAndSettle();
    await expectScreen(tester, name, masks: [_serverField()]);
  },
  'form-error-servidor': (tester, harness, name) async {
    harness.server.down = true;
    await settle(tester);
    await _openForm(tester);
    await _fillXtreamForm(tester, harness);
    await tester.tap(find.text('Guardar'));
    await _pumpUntil(
      tester,
      () => find.textContaining('HTTP 503').evaluate().isNotEmpty,
    );
    await _formToTopOnTv(tester, find.textContaining('HTTP 503'));
    await tester.pumpAndSettle();
    await expectScreen(tester, name, masks: [_serverField()]);
  },
  'inicio': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedHome);
    await expectScreen(tester, name, masks: [_programmeProgress()]);
  },
  'inicio-acento': (tester, harness, name) async {
    harness.settings.update(
      harness.settings.value.copyWith(accentColor: AccentColor.violet),
    );
    await _enter(tester, harness, seed: _seedHome);
    await expectScreen(tester, name, masks: [_programmeProgress()]);
  },
  'directo': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await tester.tap(_channelRows(tester).at(1));
    await settle(tester, timeout: const Duration(seconds: 2));
    await expectScreen(tester, name, masks: _liveMasks());
  },
  'directo-orden': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _tapLiveSort(tester);
    await expectScreen(tester, name, masks: _liveMasks());
  },
  'directo-reordenar': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _tapLiveSort(tester);
    await tester.tap(find.text('Ordenar a mano…'));
    await settle(tester, timeout: const Duration(seconds: 2));
    await expectScreen(tester, name);
  },
  'directo-guia': (tester, harness, name) async {
    await _waitForHalfHourStart(tester);
    await _enter(
      tester,
      harness,
      seed: (h) => _seedGuide(h, forGuideGrid: true),
      section: 'Directo',
    );
    await tester.tap(
      find.byTooltip(
        _phoneLayout(tester) ? 'Guía' : 'Ver la guía de los canales',
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Después'));
    await tester.pump();
    await tester.tap(find.byTooltip('Después'));
    await settle(tester);
    await expectScreen(tester, name, masks: _guideMasks());
  },
  'peliculas': (tester, harness, name) async {
    await _enter(tester, harness, section: 'Películas');
    await expectScreen(tester, name);
  },
  'ficha-pelicula': (tester, harness, name) async {
    await _enter(tester, harness, section: 'Películas');
    await tester.tap(_posterOf('La isla del faro perdido'));
    await settle(tester, timeout: const Duration(seconds: 2));
    await expectScreen(tester, name);
  },
  'series': (tester, harness, name) async {
    await _enter(tester, harness, section: 'Series');
    await expectScreen(tester, name);
  },
  'ficha-serie': (tester, harness, name) async {
    await _enter(tester, harness, section: 'Series');
    await tester.tap(_posterOf('Valle de las Sombras Demo'));
    await settle(tester, timeout: const Duration(seconds: 2));
    await expectScreen(tester, name);
  },
  'inicio-busqueda': (tester, harness, name) async {
    await _enter(tester, harness);
    await _typeInto(tester, find.byType(TextField).first, 'cine');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await expectScreen(tester, name);
  },
  'favoritos': (tester, harness, name) async {
    await _enter(
      tester,
      harness,
      seed: (h) => _seedFavorites(h, MediaKind.movie, 4),
      section: 'Películas',
    );
    await _tapChip(tester, 'Favoritos');
    await expectScreen(tester, name);
  },
  'recientes': (tester, harness, name) async {
    await _enter(
      tester,
      harness,
      seed: (h) => _seedRecents(h, MediaKind.movie, 4),
      section: 'Películas',
    );
    await _tapChip(tester, 'Recientes');
    await expectScreen(tester, name);
  },
  'reproductor-controles': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _playLive(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(PlayerScreen)));
      await _pumpRealTime(tester, const Duration(seconds: 1));
      await _hideVideoPictures(tester);
      await expectScreen(
        tester,
        name,
        maskVideo: false,
        masks: [
          find.textContaining(RegExp(r'^\d\d:\d\d / ')),
          find.byType(MaterialDesktopSeekBar),
        ],
      );
    } finally {
      await mouse.removePointer();
    }
  },
  'reproductor-info': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _playLive(tester);
    await tester.tap(find.byTooltip('Info del stream (I)'));
    await _pumpUntil(
      tester,
      () => find.text('Resolución: 1280×720').evaluate().isNotEmpty,
    );
    await _hideVideoPictures(tester);
    await expectScreen(tester, name, maskVideo: false);
  },
  'ajustes': (tester, harness, name) async {
    await _enter(tester, harness);
    await _openPlaylistSettings(tester);
    await _scrollSettingsTo(tester, find.text('Carruseles de Inicio'));
    await expectScreen(tester, name);
  },
  'ajustes-acento': (tester, harness, name) async {
    await _enter(tester, harness);
    await _openPlaylistSettings(tester);
    final title = find.text('Color de acento');
    await _scrollSettingsTo(tester, title);
    // Title a fifth down the list, so the row of swatches and
    // the section above show too.
    await Scrollable.ensureVisible(tester.element(title), alignment: 0.2);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accent-swatch-violet')));
    await settle(tester);
    await expectScreen(tester, name);
  },
  'ajustes-control-parental': (tester, harness, name) async {
    await _enter(tester, harness);
    await _startParentalLock(tester);
    await _typeInto(tester, find.widgetWithText(TextField, 'PIN'), '1234');
    await _typeInto(
      tester,
      find.widgetWithText(TextField, 'Repite el PIN'),
      '1234',
    );
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    await _scrollSettingsTo(tester, find.text('Bloqueo'));
    await expectScreen(tester, name, masks: [_lastSyncMask()]);
  },
  'pin': (tester, harness, name) async {
    await _enter(tester, harness);
    await _startParentalLock(tester);
    await _typeInto(tester, find.widgetWithText(TextField, 'PIN'), '1234');
    await _typeInto(
      tester,
      find.widgetWithText(TextField, 'Repite el PIN'),
      '123',
    );
    await tester.pumpAndSettle();
    await expectScreen(tester, name, masks: [_lastSyncMask()]);
  },
  'ajustes-cuenta-sin-supabase': (tester, harness, name) async {
    await settle(tester);
    await tester.tap(find.byTooltip('Ajustes'));
    await settle(tester);
    await expectScreen(tester, name);
  },
  'licencias': (tester, harness, name) async {
    _registerDemoLicenses();
    await settle(tester);
    await tester.tap(find.byTooltip('Ajustes'));
    await settle(tester);
    await _scrollSettingsTo(tester, find.text('Licencias'));
    // The first "Ver" is the licenses' one (the legal texts follow it); in
    // the phone layout it sits below the title, not in its row.
    await tester.tap(find.text('Ver').first);
    await _pumpUntil(
      tester,
      () => find.text('demo_player').evaluate().isNotEmpty,
    );
    await settle(tester);
    await expectScreen(tester, name);
  },
};

/// Presses [key] on the remote and lets the overlay it opens appear. The
/// key comes as from Android, whatever the host: Windows has no physical
/// key for Select (OK).
Future<void> _pressRemote(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key, platform: 'android');
  await _pumpRealTime(tester, const Duration(milliseconds: 500));
}

/// Plays the first movie of Películas full screen from its detail page and
/// waits for the clip to play.
Future<void> _playMovie(WidgetTester tester, AppHarness harness) async {
  await _enter(tester, harness, section: 'Películas');
  await tester.tap(_posterOf('La isla del faro perdido'));
  await settle(tester, timeout: const Duration(seconds: 2));
  await tester.tap(find.text('Reproducir'));
  await _pumpUntil(
    tester,
    () => find.byType(PlayerScreen).evaluate().isNotEmpty,
  );
  await _freezePlayback(tester);
}

/// Masks for the info bar of the TV live player: the programme's times, its
/// progress and the time of the next one.
List<Finder> _tvInfoMasks() => [
  find.textContaining(RegExp(r'^\d\d:\d\d')),
  find.textContaining('A continuación'),
  find.byKey(const ValueKey('tv-info-progress')),
];

/// Masks for the controls bar of the TV movie player: the position, the
/// length and the progress between them.
List<Finder> _tvVodMasks() => [
  find.descendant(
    of: find.byKey(const ValueKey('tv-vod-controls')),
    matching: find.textContaining(RegExp(r'^\d+:\d\d')),
  ),
  find.byKey(const ValueKey('tv-vod-progress')),
];

/// Screens only a TV has: the overlays of the full-screen player, which
/// the remote opens.
final Map<String, _Capture> _tvScreens = {
  // OK on a channel playing: number, name, programme on air and the next.
  'tv-directo-info': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _playLive(tester);
    await _pressRemote(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-info')), findsOneWidget);
    await _hideVideoPictures(tester);
    await expectScreen(tester, name, maskVideo: false, masks: _tvInfoMasks());
  },
  // OK again: the channels of the group, the one playing focused.
  'tv-directo-lista': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _playLive(tester);
    await _pressRemote(tester, LogicalKeyboardKey.select);
    await _pressRemote(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-channel-list')), findsOneWidget);
    await _hideVideoPictures(tester);
    await expectScreen(tester, name, maskVideo: false);
  },
  // Left: the groups beside the channels.
  'tv-directo-grupos': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _playLive(tester);
    await _pressRemote(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(const ValueKey('tv-group-list')), findsOneWidget);
    await _hideVideoPictures(tester);
    await expectScreen(tester, name, maskVideo: false);
  },
  // Right: the audio and subtitle tracks.
  'tv-directo-opciones': (tester, harness, name) async {
    await _enter(tester, harness, seed: _seedGuide, section: 'Directo');
    await _playLive(tester);
    await _pressRemote(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(const ValueKey('tv-options')), findsOneWidget);
    await _hideVideoPictures(tester);
    await expectScreen(tester, name, maskVideo: false);
  },
  // Up on a movie (paused): title, play or pause and the progress.
  'tv-pelicula-controles': (tester, harness, name) async {
    await _playMovie(tester, harness);
    await _pressRemote(tester, LogicalKeyboardKey.arrowUp);
    expect(find.byKey(const ValueKey('tv-vod-controls')), findsOneWidget);
    await _hideVideoPictures(tester);
    await expectScreen(tester, name, maskVideo: false, masks: _tvVodMasks());
  },
  // Menu on a movie: its tracks.
  'tv-pelicula-opciones': (tester, harness, name) async {
    await _playMovie(tester, harness);
    await _pressRemote(tester, LogicalKeyboardKey.contextMenu);
    expect(find.byKey(const ValueKey('tv-options')), findsOneWidget);
    await _hideVideoPictures(tester);
    await expectScreen(tester, name, maskVideo: false);
  },
};

/// Screens left out on a TV, with the reason.
const _skippedOnTv = {
  'reproductor-controles': _noDesktopPlayerControls,
  'reproductor-info': _noDesktopPlayerControls,
};

/// On a TV the full-screen player has neither the desktop controls nor the
/// bar with "Info del stream": the remote opens its own overlays, which the
/// `tv-directo-*` and `tv-pelicula-*` captures show.
const _noDesktopPlayerControls = 'the TV player has its own overlays';

/// Screens left out on Android, with the reason.
final _skippedOnAndroid = {
  'reproductor-controles': _noClipOnDevice,
  'reproductor-info': _noClipOnDevice,
  for (final name in _tvScreens.keys) name: _noClipOnDevice,
};

/// The harness's own demo server reads its clip from the repository
/// (`tool/demo_server/assets`), which is not on the device, so nothing plays
/// (`android_smoke_test.dart` plays from the PC's server instead).
const _noClipOnDevice = 'the demo clip is not on the device';

/// One visual test per screen and size; each starts the app on throwaway data.
/// Every screen runs at every size: `phone` and `tablet` get the phone layout
/// (bottom bar, Directo for zapping), and on Windows the player keeps its
/// desktop controls. At `tv` the app runs as on a TV (scale, focus, remote
/// overlays in the player), with the [_tvScreens] added and the
/// [_skippedOnTv] left out.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [smallSize, mediumSize, phoneSize, tabletSize, tvSize]) {
    final tv = size == tvSize;
    final screens = tv ? {..._screens, ..._tvScreens} : _screens;
    for (final MapEntry(key: name, value: capture) in screens.entries) {
      final skipped =
          (Platform.isAndroid && _skippedOnAndroid.containsKey(name)) ||
          (tv && _skippedOnTv.containsKey(name));
      testWidgets('$name at ${sizeName(size)}', skip: skipped, (tester) async {
        if (tv) {
          debugTvDevice = true;
          addTearDown(() => debugTvDevice = null);
        }
        ParentalSession.unlocked.value = false;
        final harness = await AppHarness.start(
          tester,
          size: size,
          signedIn: _signedInScreens.contains(name),
          firstRun: _firstRunScreens.contains(name),
        );
        addTearDown(harness.close);
        await capture(tester, harness, name);
      });
    }
  }
}
