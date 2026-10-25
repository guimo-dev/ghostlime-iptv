import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/marquee_text.dart';

const _long = 'Canal con un nombre largo';
const _style = TextStyle(fontSize: 10);

/// Pumps [text] in a 100 px wide box (the test font is 10 px per letter)
/// with the marquee switched on for this test.
Future<void> _pump(
  WidgetTester tester,
  String text, {
  bool disableAnimations = false,
  bool tickers = true,
}) async {
  MarqueeText.enabled = true;
  addTearDown(() => MarqueeText.enabled = false);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: tickers,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              child: MarqueeText(text, style: _style),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Left edge of the text relative to its 100 px box at the origin.
double _textLeft(WidgetTester tester) => tester.getTopLeft(find.text(_long)).dx;

void main() {
  testWidgets('a name that fits is plain text and never animates', (
    tester,
  ) async {
    await _pump(tester, 'Uno');
    expect(tester.widget<Text>(find.text('Uno')).maxLines, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a long name rests with an ellipsis, then scrolls to its end '
      'and jumps back', (tester) async {
    await _pump(tester, _long);
    final atRest = tester.widget<Text>(find.text(_long));
    expect(atRest.overflow, TextOverflow.ellipsis);
    expect(_textLeft(tester), 0);

    await tester.pump(MarqueeText.restPause);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_textLeft(tester), lessThan(0));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // Scrolls 150 px (250 of text in 100) and waits at the end.
    await tester.pump(const Duration(seconds: 5));
    expect(_textLeft(tester), -150);

    await tester.pump(MarqueeText.endPause);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_textLeft(tester), 0);
    expect(
      tester.widget<Text>(find.text(_long)).overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets('with animations disabled a long name keeps the ellipsis', (
    tester,
  ) async {
    await _pump(tester, _long, disableAnimations: true);
    await tester.pump(const Duration(seconds: 10));
    expect(_textLeft(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a muted ticker (offscreen route or tab) does not animate', (
    tester,
  ) async {
    await _pump(tester, _long, tickers: false);
    await tester.pump(const Duration(seconds: 10));
    expect(_textLeft(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('switched off (as in tests and captures) it stays still', (
    tester,
  ) async {
    expect(MarqueeText.enabled, isFalse);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 100, child: MarqueeText(_long, style: _style)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(_textLeft(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
