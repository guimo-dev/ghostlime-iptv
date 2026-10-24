import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/golden.dart';

void main() {
  const width = 10;
  const height = 10;

  /// A [width]x[height] image filled with one opaque grey.
  Uint8List solid(int grey) {
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      bytes
        ..[i] = grey
        ..[i + 1] = grey
        ..[i + 2] = grey
        ..[i + 3] = 255;
    }
    return bytes;
  }

  test('identical images do not differ', () {
    final diff = compareRgba(solid(100), solid(100), width, height);
    expect(diff.mismatchRatio, 0);
  });

  test('a change within the channel tolerance is ignored', () {
    final changed = solid(100)..[0] = 108;
    final diff = compareRgba(solid(100), changed, width, height);
    expect(diff.mismatchRatio, 0);
  });

  test('1 % of changed pixels gives 0.01 and marks them red', () {
    final changed = solid(100)..[4 * 37] = 200;
    final diff = compareRgba(solid(100), changed, width, height);
    expect(diff.mismatchRatio, 0.01);
    expect(diff.diffRgba.sublist(4 * 37, 4 * 38), [255, 0, 0, 255]);
    expect(diff.diffRgba.sublist(0, 4), isNot([255, 0, 0, 255]));
  });
}
