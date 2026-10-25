import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/xtream/xtream_urls.dart' show LiveFormat;
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';

/// Minimum visible gap, in logical pixels, expected between two form controls.
const _minimumGap = 8.0;

/// Pumps the form at [size] and picks the playlist type labelled [typeLabel].
Future<void> _pumpForm(WidgetTester tester, Size size, String typeLabel) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(CatalogDb.inMemory()),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const PlaylistFormScreen(),
      ),
    ),
  );
  await tester.tap(find.text(typeLabel));
  await tester.pumpAndSettle();
}

void main() {
  const sizes = [Size(1024, 700), Size(1440, 900)];
  const types = ['Xtream', 'M3U (URL)', 'M3U (fichero)'];

  for (final size in sizes) {
    for (final type in types) {
      final name = '${size.width.toInt()}x${size.height.toInt()} $type';

      testWidgets('no field overlaps another ($name)', (tester) async {
        await _pumpForm(tester, size, type);
        // Fields wrap an InputDecorator, so keep only top-level controls.
        final fields = tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .map((w) => tester.getRect(find.byWidget(w)))
            .toList();
        final others = [
          ...tester
              .widgetList(find.byWidgetPredicate((w) => w is SegmentedButton))
              .map((w) => tester.getRect(find.byWidget(w))),
          ...tester
              .widgetList(find.byType(OutlinedButton))
              .map((w) => tester.getRect(find.byWidget(w))),
        ];
        final rects = [...fields, ...others];
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].inflate(_minimumGap / 2).overlaps(rects[j]),
              isFalse,
              reason: '${rects[i]} is closer than $_minimumGap to ${rects[j]}',
            );
          }
        }
      });

      testWidgets('no overflow errors ($name)', (tester) async {
        await _pumpForm(tester, size, type);
        expect(tester.takeException(), isNull);
      });

      testWidgets('120-char name stays inside its field ($name)', (
        tester,
      ) async {
        await _pumpForm(tester, size, type);
        await tester.enterText(find.byType(TextFormField).first, 'N' * 120);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final field = tester.getRect(find.byType(TextFormField).first);
        final text = tester.getRect(find.byType(EditableText).first);
        expect(field.expandToInclude(text), field);
      });
    }

    testWidgets('form is centered and at most 720 px wide '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      await _pumpForm(tester, size, 'Xtream');
      final field = tester.getRect(find.byType(TextFormField).first);
      expect(field.width, lessThanOrEqualTo(720));
      expect(field.center.dx, closeTo(size.width / 2, 1));
    });
  }

  testWidgets('focused floating label sits inside its field', (tester) async {
    await _pumpForm(tester, const Size(1024, 700), 'Xtream');
    final server = find.widgetWithText(TextFormField, 'Servidor');
    await tester.tap(server);
    await tester.pumpAndSettle();
    final field = tester.getRect(
      find.descendant(of: server, matching: find.byType(InputDecorator)),
    );
    final label = tester.getRect(
      find.descendant(of: server, matching: find.text('Servidor')),
    );
    expect(field.expandToInclude(label), field);
  });

  testWidgets('the live format selector has no form field around it', (
    tester,
  ) async {
    await _pumpForm(tester, const Size(1024, 700), 'Xtream');
    final selector = find.byType(SegmentedButton<LiveFormat>);
    expect(selector, findsOneWidget);
    expect(
      find.ancestor(of: selector, matching: find.byType(InputDecorator)),
      findsNothing,
    );
    expect(find.text('Directo en'), findsOneWidget);
    expect(find.text('TS'), findsOneWidget);
    expect(find.text('HLS'), findsOneWidget);
  });
}
