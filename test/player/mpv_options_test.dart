import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/mpv_options.dart';

void main() {
  group('hwdecFor', () {
    test('desktop uses auto-safe, or no when switched off', () {
      expect(hwdecFor(hardwareDecoding: true, isMobile: false), 'auto-safe');
      expect(hwdecFor(hardwareDecoding: false, isMobile: false), 'no');
    });

    test("Android and iOS keep media_kit's choice whatever the setting", () {
      // The switch is hidden there, but the value syncs from a desktop.
      expect(hwdecFor(hardwareDecoding: true, isMobile: true), isNull);
      expect(hwdecFor(hardwareDecoding: false, isMobile: true), isNull);
    });
  });
}
