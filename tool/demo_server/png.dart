import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 3x5 pixel glyphs of the digits 0-9, one row per string.
const _digitGlyphs = [
  ['111', '101', '101', '101', '111'],
  ['010', '110', '010', '010', '111'],
  ['111', '001', '111', '100', '111'],
  ['111', '001', '111', '001', '111'],
  ['101', '101', '111', '001', '001'],
  ['111', '100', '111', '001', '111'],
  ['111', '100', '111', '101', '111'],
  ['111', '001', '001', '001', '001'],
  ['111', '101', '111', '101', '111'],
  ['111', '101', '111', '001', '111'],
];

/// Background colors (RGB) of the posters, picked by number.
const _palette = [
  [0x2E, 0x6F, 0x95],
  [0x8E, 0x44, 0xAD],
  [0xC0, 0x39, 0x2B],
  [0x16, 0x7D, 0x5A],
  [0xD3, 0x7A, 0x1F],
  [0x34, 0x49, 0x5E],
];

/// Builds a [width] x [height] PNG with a solid background and [number] drawn
/// in white at the center; the color depends on [number].
Uint8List buildNumberedPng(int number, {int width = 200, int height = 300}) {
  final background = _palette[number % _palette.length];
  final digits = '$number'.split('').map(int.parse).toList();
  const scale = 12;
  const glyphWidth = 3 * scale;
  const gap = scale;
  final textWidth = digits.length * glyphWidth + (digits.length - 1) * gap;
  final left = (width - textWidth) ~/ 2;
  final top = (height - 5 * scale) ~/ 2;

  // Each scanline starts with filter byte 0 (none), then RGB pixels.
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      final isText = _isTextPixel(x - left, y - top, digits, scale, gap);
      if (isText) {
        raw.add(const [255, 255, 255]);
      } else {
        raw.add(background);
      }
    }
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // color type: RGB
  final png = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', zlib.encode(raw.toBytes())))
    ..add(_chunk('IEND', const []));
  return png.toBytes();
}

/// Whether the pixel at ([x], [y]) relative to the text origin is part of a digit.
bool _isTextPixel(int x, int y, List<int> digits, int scale, int gap) {
  if (x < 0 || y < 0 || y >= 5 * scale) return false;
  final cell = 3 * scale + gap;
  final index = x ~/ cell;
  final inCell = x % cell;
  if (index >= digits.length || inCell >= 3 * scale) return false;
  return _digitGlyphs[digits[index]][y ~/ scale][inCell ~/ scale] == '1';
}

/// Encodes one PNG chunk: length, type, data and CRC32 of type + data.
List<int> _chunk(String type, List<int> data) {
  final typeAndData = [...ascii.encode(type), ...data];
  final bytes = ByteData(8 + data.length + 4);
  bytes.setUint32(0, data.length);
  for (var i = 0; i < typeAndData.length; i++) {
    bytes.setUint8(4 + i, typeAndData[i]);
  }
  bytes.setUint32(8 + data.length, _crc32(typeAndData));
  return bytes.buffer.asUint8List();
}

/// CRC-32 (IEEE) of [bytes], as PNG requires.
int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
