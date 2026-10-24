/// One playable entry of an M3U playlist.
class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    this.tvgId,
    this.tvgLogo,
    this.groupTitle,
  });

  final String name;
  final String url;
  final String? tvgId;
  final String? tvgLogo;
  final String? groupTitle;
}

final _attributePattern = RegExp(r'([\w-]+)="([^"]*)"');

/// Parses M3U/M3U8 text into entries, tolerating BOM, CRLF, blank lines,
/// extra directives between `#EXTINF` and the URL, and `#EXTINF` lines
/// without a URL (which are dropped).
List<M3uEntry> parseM3u(String content) {
  final entries = <M3uEntry>[];
  String? pendingInfo;
  for (final rawLine in content.split('\n')) {
    final line = rawLine.replaceAll('﻿', '').trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      pendingInfo = line;
    } else if (_isStreamUrl(line)) {
      entries.add(_buildEntry(pendingInfo, line));
      pendingInfo = null;
    }
  }
  return entries;
}

/// The guide URL declared in the header (`url-tvg` or `x-tvg-url` on any
/// `#EXTM3U` line before the first entry), or `null`. Some lists, such as
/// TDTChannels, put it on a second `#EXTM3U` line. When several are given
/// separated by commas, the first is returned.
String? parseM3uTvgUrl(String content) {
  for (final rawLine in content.split('\n')) {
    final line = rawLine.replaceAll('﻿', '').trim();
    if (line.startsWith('#EXTINF') || _isStreamUrl(line)) return null;
    if (!line.startsWith('#EXTM3U')) continue;
    final attributes = {
      for (final match in _attributePattern.allMatches(line))
        match.group(1)!.toLowerCase(): match.group(2)!,
    };
    final value = attributes['url-tvg'] ?? attributes['x-tvg-url'];
    final first = value?.split(',').first.trim();
    if (first != null && first.isNotEmpty) return first;
  }
  return null;
}

/// Whether [line] is a bare absolute URL (rejects HTML that merely contains one).
bool _isStreamUrl(String line) {
  if (line.contains(RegExp(r'[\s<>"]'))) return false;
  return Uri.tryParse(line)?.hasAuthority ?? false;
}

/// Builds an entry from an optional `#EXTINF` line and its URL.
M3uEntry _buildEntry(String? info, String url) {
  if (info == null) return M3uEntry(name: url, url: url);
  final commaIndex = _firstCommaOutsideQuotes(info);
  final header = commaIndex == -1 ? info : info.substring(0, commaIndex);
  final name = commaIndex == -1 ? '' : info.substring(commaIndex + 1).trim();
  final attributes = {
    for (final match in _attributePattern.allMatches(header))
      match.group(1)!.toLowerCase(): match.group(2)!.trim(),
  };
  String? attribute(String key) {
    final value = attributes[key];
    return value == null || value.isEmpty ? null : value;
  }

  return M3uEntry(
    name: name.isEmpty ? url : name,
    url: url,
    tvgId: attribute('tvg-id'),
    tvgLogo: attribute('tvg-logo'),
    groupTitle: attribute('group-title'),
  );
}

/// Index of the first comma not inside double quotes, or -1.
int _firstCommaOutsideQuotes(String text) {
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '"') inQuotes = !inQuotes;
    if (char == ',' && !inQuotes) return i;
  }
  return -1;
}
