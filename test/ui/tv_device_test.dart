import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/form_factor.dart';
import 'package:iptv_player/ui/tv_device.dart';

const _deviceChannel = MethodChannel('ghostlime/device');

/// Answers the device channel's `isTv` with [answer], or fails when
/// [answer] is `null`.
void _mockDeviceChannel(bool? answer) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_deviceChannel, (call) async {
        expect(call.method, 'isTv');
        if (answer == null) {
          throw PlatformException(code: 'boom');
        }
        return answer;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugTvDevice = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_deviceChannel, null);
  });

  group('form factor on a TV', () {
    test('a TV always gets the desktop layout and no touch', () {
      debugTvDevice = true;
      expect(usesDesktopLayout(const Size(960, 540)), isTrue);
      expect(usesDesktopLayout(const Size(390, 844)), isTrue);
      expect(isTouchPlatform, isFalse);
    });

    test('elsewhere the rules of today hold', () {
      debugTvDevice = false;
      expect(usesDesktopLayout(const Size(960, 540)), isFalse);
      expect(usesDesktopLayout(const Size(1024, 700)), isTrue);
      // Widget tests run as Android.
      expect(isTouchPlatform, isTrue);
    });
  });

  group('detectTvDevice', () {
    test('the channel saying TV makes isTvDevice true', () async {
      _mockDeviceChannel(true);
      await detectTvDevice();
      expect(isTvDevice, isTrue);
    });

    test('the channel saying no TV keeps isTvDevice false', () async {
      _mockDeviceChannel(false);
      await detectTvDevice();
      expect(isTvDevice, isFalse);
    });

    test('a channel error leaves isTvDevice false', () async {
      _mockDeviceChannel(true);
      await detectTvDevice();
      _mockDeviceChannel(null);
      await detectTvDevice();
      expect(isTvDevice, isFalse);
    });

    test('a missing channel (desktop) leaves isTvDevice false', () async {
      await detectTvDevice();
      expect(isTvDevice, isFalse);
    });
  });
}
