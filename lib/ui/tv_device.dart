import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Builds with `--dart-define=GHOSTLIME_FORCE_TV=true` behave as a TV on any
/// device (to try the TV interface on a desktop or phone).
const _forceTv = bool.fromEnvironment('GHOSTLIME_FORCE_TV');

/// Channel to the Android activity, which answers `isTv`.
const _deviceChannel = MethodChannel('ghostlime/device');

/// What [detectTvDevice] found out.
bool _detectedTv = false;

/// Test override of [isTvDevice]; `null` uses the detected value.
bool? _debugTvDevice;

/// Whether the app runs on a TV (Android TV, Google TV, Fire TV), driven
/// with a remote: forced by `GHOSTLIME_FORCE_TV` or found by
/// [detectTvDevice].
bool get isTvDevice => _debugTvDevice ?? (_forceTv || _detectedTv);

/// Makes [isTvDevice] return [value] in tests; `null` restores detection.
@visibleForTesting
set debugTvDevice(bool? value) => _debugTvDevice = value;

/// Asks Android whether this device is a TV; call it in `main` before
/// `runApp`. Where the channel is missing (desktop) or fails, the device
/// is not a TV.
Future<void> detectTvDevice() async {
  try {
    _detectedTv = await _deviceChannel.invokeMethod<bool>('isTv') ?? false;
  } on Exception {
    _detectedTv = false;
  }
}
