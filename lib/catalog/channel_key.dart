import 'dart:convert';

import '../m3u/m3u_parser.dart';

/// 64-bit FNV-1a hash of [text]'s UTF-8 bytes, as 16 lowercase hex digits.
String fnv1a64Hex(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  return BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// Stable keys for M3U entries, in the same order as [entries].
///
/// `t:<tvg-id>` when the tvg-id is unique in the list, otherwise
/// `h:<fnv1a64(name + "\n" + url)>`.
List<String> m3uChannelKeys(List<M3uEntry> entries) {
  final tvgIdCounts = <String, int>{};
  for (final entry in entries) {
    final id = entry.tvgId;
    if (id != null) tvgIdCounts[id] = (tvgIdCounts[id] ?? 0) + 1;
  }
  return [
    for (final entry in entries)
      if (entry.tvgId != null && tvgIdCounts[entry.tvgId] == 1)
        't:${entry.tvgId}'
      else
        'h:${fnv1a64Hex('${entry.name}\n${entry.url}')}',
  ];
}
