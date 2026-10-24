import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' show Video;

import 'harness.dart';

/// Rewrites the reference images instead of comparing
/// (`--dart-define=UPDATE_GOLDENS=true`).
const updateGoldens = bool.fromEnvironment('UPDATE_GOLDENS');

/// Also saves the medium-size captures, without the [masks], to `docs/guia/img`
/// (`--dart-define=DOCS_SCREENSHOTS=true`).
const docsScreenshots = bool.fromEnvironment('DOCS_SCREENSHOTS');

/// Where the user guide's screenshots are written.
const docsImageDir = 'docs/guia/img';

/// Share of differing pixels above which a screen fails.
const maxMismatchRatio = 0.002;

/// Where the actual and diff images of failed screens are written.
const goldenFailuresDir = 'build/golden_failures';

/// Result of comparing two RGBA images of the same size.
class GoldenDiff {
  const GoldenDiff(this.mismatchRatio, this.diffRgba);

  /// Share of pixels (0..1) where some channel differs beyond the tolerance.
  final double mismatchRatio;

  /// The reference dimmed, with every differing pixel in opaque red.
  final Uint8List diffRgba;
}

/// Compares two RGBA images of [width]x[height] pixel by pixel. A pixel
/// differs when any channel moves more than [channelTolerance].
GoldenDiff compareRgba(
  Uint8List a,
  Uint8List b,
  int width,
  int height, {
  int channelTolerance = 8,
}) {
  final diff = Uint8List(width * height * 4);
  var mismatched = 0;
  for (var i = 0; i < diff.length; i += 4) {
    var differs = false;
    for (var c = 0; c < 4; c++) {
      if ((a[i + c] - b[i + c]).abs() > channelTolerance) differs = true;
    }
    if (differs) {
      mismatched++;
      diff
        ..[i] = 255
        ..[i + 3] = 255;
    } else {
      diff
        ..[i] = a[i] ~/ 3
        ..[i + 1] = a[i + 1] ~/ 3
        ..[i + 2] = a[i + 2] ~/ 3
        ..[i + 3] = 255;
    }
  }
  return GoldenDiff(mismatched / (width * height), diff);
}

/// Captures the app (the harness's [RepaintBoundary]) as width, height and
/// RGBA bytes. Video surfaces (unless [maskVideo] is false) and every widget
/// matched by [masks] are painted opaque black, since their pixels change from
/// run to run. A video's rectangle covers its controls too: with [maskVideo]
/// false the caller must remove the picture itself.
Future<(int, int, Uint8List)> captureScreen(
  WidgetTester tester, {
  List<Finder> masks = const [],
  bool maskVideo = true,
}) async {
  await tester.pump();
  final boundaryFinder = find.byKey(screenBoundaryKey);
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  final origin = tester.getTopLeft(boundaryFinder);
  final hiddenRects = [
    for (final finder in [if (maskVideo) find.byType(Video), ...masks])
      for (var i = 0; i < finder.evaluate().length; i++)
        tester.getRect(finder.at(i)).shift(-origin),
  ];
  final (width, height, rgba) = (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (image.width, image.height, bytes!.buffer.asUint8List());
    image.dispose();
    return result;
  }))!;
  for (final rect in hiddenRects) {
    _fillBlack(rgba, width, height, rect);
  }
  return (width, height, rgba);
}

/// Captures the app with [captureScreen] and compares it with
/// `integration_test/goldens/<size>/<name>.png`. With [updateGoldens] the
/// reference is rewritten instead. On failure the actual and diff images go
/// to `build/golden_failures/<size>/`. Widgets whose pixels depend on the
/// time (clocks, guide progress, "termina en…") must be passed in [masks].
/// [maskVideo] is passed on to [captureScreen]. Call `settle` first.
Future<void> expectScreen(
  WidgetTester tester,
  String name, {
  List<Finder> masks = const [],
  bool maskVideo = true,
}) async {
  final size = sizeName(tester.view.physicalSize);
  final (width, height, actual) = await captureScreen(
    tester,
    masks: masks,
    maskVideo: maskVideo,
  );

  if (docsScreenshots && size == 'medium') {
    await _writeDocsImage(tester, name, maskVideo);
  }

  final reference = File('integration_test/goldens/$size/$name.png');
  if (updateGoldens) {
    final png = (await tester.runAsync(
      () => encodePng(actual, width, height),
    ))!;
    await reference.parent.create(recursive: true);
    await reference.writeAsBytes(png);
    debugPrint('Reference written: ${reference.absolute.path}');
    return;
  }

  final failures = Directory('$goldenFailuresDir/$size');

  /// Writes the actual image (and [diff], if any) for inspection.
  Future<void> writeFailure(Uint8List? diff) async {
    await failures.create(recursive: true);
    final actualPng = await tester.runAsync(
      () => encodePng(actual, width, height),
    );
    await File('${failures.path}/$name.actual.png').writeAsBytes(actualPng!);
    if (diff == null) return;
    final diffPng = await tester.runAsync(() => encodePng(diff, width, height));
    await File('${failures.path}/$name.diff.png').writeAsBytes(diffPng!);
  }

  if (!reference.existsSync()) {
    await writeFailure(null);
    fail(
      'No reference for $size/$name. Run with '
      '--dart-define=UPDATE_GOLDENS=true to create it.',
    );
  }
  final (refWidth, refHeight, expected) = (await tester.runAsync(
    () async => decodePng(await reference.readAsBytes()),
  ))!;
  if (refWidth != width || refHeight != height) {
    await writeFailure(null);
    fail(
      '$size/$name: reference is ${refWidth}x$refHeight, '
      'capture is ${width}x$height.',
    );
  }
  final diff = compareRgba(expected, actual, width, height);
  if (diff.mismatchRatio > maxMismatchRatio) {
    await writeFailure(diff.diffRgba);
    fail(
      '$size/$name: ${(diff.mismatchRatio * 100).toStringAsFixed(2)} % of '
      'pixels differ (max ${maxMismatchRatio * 100} %). See '
      '${failures.path}/$name.diff.png.',
    );
  }
}

/// Saves the app as `docs/guia/img/<name>.png` for humans: no [masks], so clocks
/// and the like show as they are. Video pictures stay black unless [maskVideo]
/// is false (the test then removed them), so no real content leaks.
Future<void> _writeDocsImage(
  WidgetTester tester,
  String name,
  bool maskVideo,
) async {
  final (width, height, rgba) = await captureScreen(
    tester,
    maskVideo: maskVideo,
  );
  final png = (await tester.runAsync(() => encodePng(rgba, width, height)))!;
  final file = File('$docsImageDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png);
}

/// Paints [rect] (clipped to the image) opaque black in an RGBA buffer.
void _fillBlack(Uint8List rgba, int width, int height, ui.Rect rect) {
  final left = rect.left.floor().clamp(0, width);
  final right = rect.right.ceil().clamp(0, width);
  final top = rect.top.floor().clamp(0, height);
  final bottom = rect.bottom.ceil().clamp(0, height);
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final i = (y * width + x) * 4;
      rgba
        ..[i] = 0
        ..[i + 1] = 0
        ..[i + 2] = 0
        ..[i + 3] = 255;
    }
  }
}

/// Decodes a PNG into width, height and RGBA bytes with the engine's codec.
Future<(int, int, Uint8List)> decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = (image.width, image.height, bytes!.buffer.asUint8List());
  image.dispose();
  codec.dispose();
  return result;
}

/// Encodes RGBA bytes of [width]x[height] as PNG with the engine's codec.
Future<Uint8List> encodePng(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return png!.buffer.asUint8List();
}
