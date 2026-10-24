import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/mpv_options.dart';

void main() {
  group('hwdecFor', () {
    test('desktop uses auto-safe, or no when switched off', () {
      expect(hwdecFor(hardwareDecoding: true, isAndroid: false), 'auto-safe');
      expect(hwdecFor(hardwareDecoding: false, isAndroid: false), 'no');
    });

    test("Android keeps media_kit's choice unless switched off", () {
      expect(hwdecFor(hardwareDecoding: true, isAndroid: true), isNull);
      expect(hwdecFor(hardwareDecoding: false, isAndroid: true), 'no');
    });
  });
}
