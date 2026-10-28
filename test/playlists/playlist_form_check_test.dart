import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/tv_device.dart';

/// Opens the form from a button (so popping it can be observed), with
/// [checkSource] as its source check, and fills in an Xtream playlist.
/// Returns a getter for what the form popped.
Future<PlaylistFormResult? Function()> _openFilledForm(
  WidgetTester tester,
  PlaylistSourceCheck checkSource,
) async {
  PlaylistFormResult? popped;
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(CatalogDb.inMemory()),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<PlaylistFormResult>(
                MaterialPageRoute(
                  builder: (_) => PlaylistFormScreen(checkSource: checkSource),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  Future<void> fill(String label, String value) =>
      tester.enterText(find.widgetWithText(TextFormField, label), value);
  await fill('Nombre', 'Demo');
  await fill('Servidor', 'http://127.0.0.1:1');
  await fill('Usuario', 'demo');
  await fill('Contraseña', 'mal');
  return () => popped;
}

void main() {
  testWidgets('a rejected source shows its error inline and keeps the form', (
    tester,
  ) async {
    final checked = <(Playlist, String?)>[];
    final popped = await _openFilledForm(tester, (playlist, password) async {
      checked.add((playlist, password));
      return 'El servidor ha rechazado las credenciales de la lista.';
    });

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(checked.single.$1.username, 'demo');
    expect(checked.single.$2, 'mal');
    expect(
      find.text('El servidor ha rechazado las credenciales de la lista.'),
      findsOneWidget,
    );
    expect(find.byType(PlaylistFormScreen), findsOneWidget);
    expect(popped(), isNull);

    final password = find.widgetWithText(TextFormField, 'Contraseña');
    await tester.enterText(password, 'demo');
    expect(tester.widget<TextFormField>(password).controller!.text, 'demo');
  });

  testWidgets('an accepted source pops the playlist', (tester) async {
    final popped = await _openFilledForm(tester, (_, _) async => null);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistFormScreen), findsNothing);
    expect(popped()!.$1.name, 'Demo');
    expect(popped()!.$2, 'mal');
  });

  testWidgets('a check that throws re-enables Guardar and shows an error', (
    tester,
  ) async {
    final popped = await _openFilledForm(
      tester,
      (_, _) async => throw const FormatException('http://u:secret@h'),
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('No se ha podido comprobar la lista.'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(find.text('Guardar'), findsOneWidget);
    expect(popped(), isNull);
  });

  testWidgets('Guardar is disabled while the source is checked', (
    tester,
  ) async {
    final popped = await _openFilledForm(
      tester,
      (_, _) => Future.delayed(const Duration(seconds: 1), () => null),
    );

    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Comprobando…'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(popped(), isNotNull);
  });

  // On a TV typing scrolls each field up (room for the floating keyboard),
  // so the error, at the top of the form, could stay out of view.
  testWidgets('on a TV a rejected source scrolls its error into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    debugTvDevice = true;
    addTearDown(() {
      tester.view.reset();
      debugTvDevice = null;
    });
    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(CatalogDb.inMemory()),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: PlaylistFormScreen(
            checkSource: (_, _) async =>
                'El servidor ha rechazado las credenciales de la lista.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A locked field on a TV only takes text once opened (a tap).
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, value);
    }

    await fill('Nombre', 'Demo');
    await fill('Servidor', 'http://127.0.0.1:1');
    await fill('Usuario', 'demo');
    await fill('Contraseña', 'mal');
    final form = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(form).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final error = find.text(
      'El servidor ha rechazado las credenciales de la lista.',
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final viewport = tester.getRect(form);
    final shown = tester.getRect(error);
    expect(shown.top, greaterThanOrEqualTo(viewport.top));
    expect(shown.bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets('off a TV a rejected source does not scroll the form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 400);
    tester.view.devicePixelRatio = 1;
    debugTvDevice = false;
    addTearDown(() {
      tester.view.reset();
      debugTvDevice = null;
    });
    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(CatalogDb.inMemory()),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: PlaylistFormScreen(
            checkSource: (_, _) async =>
                'El servidor ha rechazado las credenciales de la lista.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, value);
    }

    await fill('Nombre', 'Demo');
    await fill('Servidor', 'http://127.0.0.1:1');
    await fill('Usuario', 'demo');
    await fill('Contraseña', 'mal');
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final before = position.pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(position.pixels, before);
  });
}
