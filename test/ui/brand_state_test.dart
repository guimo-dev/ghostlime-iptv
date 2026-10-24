import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/brand_state.dart';
import 'package:iptv_player/ui/ghostlime_logo.dart';

/// Pumps [child] under the app theme, optionally with animations disabled.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: app!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('BrandMessage shows the ghost, title, message and child', (
    tester,
  ) async {
    await _pump(
      tester,
      const BrandMessage(
        title: 'Nada encontrado',
        message: 'Prueba otra cosa',
        child: Text('Reintentar'),
      ),
    );
    final logo = tester.widget<GhostlimeLogo>(find.byType(GhostlimeLogo));
    expect(logo.tile, isFalse);
    expect(find.text('Nada encontrado'), findsOneWidget);
    expect(find.text('Prueba otra cosa'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('BrandMessage dims the ghost for errors', (tester) async {
    await _pump(tester, const BrandMessage(title: 'Error', dimmed: true));
    final opacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byType(GhostlimeLogo),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(0.5));
  });

  testWidgets('BrandLoader shows the ghost and animates', (tester) async {
    await _pump(tester, const BrandLoader());
    expect(find.byType(GhostlimeLogo), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('BrandLoader is static when animations are disabled', (
    tester,
  ) async {
    await _pump(tester, const BrandLoader(), disableAnimations: true);
    expect(find.byType(GhostlimeLogo), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('GhostlimeLogo is decorative unless given a semantic label', (
    tester,
  ) async {
    await _pump(tester, const GhostlimeLogo());
    expect(find.bySemanticsLabel('Ghostlime'), findsNothing);
    await _pump(tester, const GhostlimeLogo(semanticLabel: 'Ghostlime'));
    expect(find.bySemanticsLabel('Ghostlime'), findsOneWidget);
  });
}
