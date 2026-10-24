import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/ghostlime_logo.dart';

/// Renders a 100 px [GhostlimeLogo] and returns a pixel reader.
Future<Color Function(int x, int y)> _render(
  WidgetTester tester, {
  required bool tile,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: GhostlimeLogo(size: 100, tile: tile),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final (image, bytes) = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    return (image, await image.toByteData());
  }))!;
  return (x, y) {
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(
      bytes!.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
  };
}

void main() {
  testWidgets('ghost body is lime and the play face is dark', (tester) async {
    final pixel = await _render(tester, tile: true);
    // Body left of the play, inside the ghost (SVG ~ (38, 60)).
    expect(pixel(32, 48), AppColors.accent);
    // Centre of the play triangle (SVG ~ (60, 60) shifted up by 3).
    expect(pixel(50, 47), AppColors.onAccent);
  });

  testWidgets('tile paints a dark square, no tile stays transparent', (
    tester,
  ) async {
    final withTile = await _render(tester, tile: true);
    expect(withTile(50, 95), AppColors.onAccent);
    final without = await _render(tester, tile: false);
    expect(without(50, 95).a, 0);
    expect(without(32, 48), AppColors.accent);
  });
}
