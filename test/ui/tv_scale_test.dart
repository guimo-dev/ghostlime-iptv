import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/tv_device.dart';
import 'package:iptv_player/ui/tv_scale.dart';

/// Puts the test view at a 1080p TV of density 2 (960x540 logical).
void _useTvView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(bottom: 120);
  tester.view.viewPadding = const FakeViewPadding(bottom: 120);
  addTearDown(tester.view.reset);
}

/// A [MaterialApp] whose builder wraps everything in [TvScale], with
/// [home] as its only screen.
Widget _app(Widget home) => MaterialApp(
  builder: (context, child) => TvScale(child: child!),
  home: Scaffold(body: home),
);

void main() {
  tearDown(() => debugTvDevice = null);

  testWidgets('on a TV the app sees a 1280x720 canvas', (tester) async {
    debugTvDevice = true;
    _useTvView(tester);
    late MediaQueryData inside;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            inside = MediaQuery.of(context);
            return const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(key: Key('box'), width: 100, height: 100),
            );
          },
        ),
      ),
    );

    expect(inside.size, const Size(1280, 720));
    // 120 physical px of padding are 60 logical px outside and 80 inside
    // (the Scaffold consumes `padding`; `viewPadding` keeps it). The other
    // sides get the overscan margin.
    expect(inside.viewPadding.bottom, closeTo(80, 0.001));
    expect(inside.viewPadding.left, tvSafeMargin.left);
    expect(inside.viewPadding.top, tvSafeMargin.top);
    expect(inside.viewPadding.right, tvSafeMargin.right);
    expect(inside.devicePixelRatio, closeTo(1.5, 0.001));
    final rect = tester.getRect(find.byKey(const Key('box')));
    expect(rect.width * tester.view.devicePixelRatio, closeTo(150, 0.001));
    expect(rect.height * tester.view.devicePixelRatio, closeTo(150, 0.001));
  });

  testWidgets('taps and focus reach the scaled widget', (tester) async {
    debugTvDevice = true;
    _useTvView(tester);
    var pressed = 0;
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.only(left: 1000, top: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton(
                onPressed: () => pressed++,
                child: const Text('Pulsar'),
              ),
              SizedBox(width: 200, child: TextField(focusNode: fieldFocus)),
            ],
          ),
        ),
      ),
    );

    // Unscaled, x 1000 would be off the 960-wide screen.
    await tester.tap(find.text('Pulsar'));
    expect(pressed, 1);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(fieldFocus.hasFocus, isTrue);
  });

  testWidgets('elsewhere the child is returned as is', (tester) async {
    debugTvDevice = false;
    _useTvView(tester);
    const child = SizedBox(key: Key('child'));
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          final widget = const TvScale(child: child).build(context);
          expect(widget, same(child));
          return widget;
        },
      ),
    );
    expect(find.byKey(const Key('child')), findsOneWidget);
  });
}
