import 'catalog_models.dart';

/// How a list of channels or categories is ordered.
enum SortMode { original, alphaAsc, alphaDesc, manual }

SortMode _modeFromJson(Object? value) => SortMode.values.firstWhere(
  (mode) => mode.name == value,
  orElse: () => SortMode.original,
);

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

/// Ordering preferences for the channels of one category.
class ChannelSort {
  const ChannelSort({
    this.mode = SortMode.original,
    this.favoritesFirst = false,
    this.manualOrder = const [],
  });

  /// Restores preferences saved with [toJson]; unknown values fall back to defaults.
  factory ChannelSort.fromJson(Map<String, Object?> json) => ChannelSort(
    mode: _modeFromJson(json['mode']),
    favoritesFirst: json['favoritesFirst'] == true,
    manualOrder: _stringList(json['manualOrder']),
  );

  final SortMode mode;

  /// Whether favorites go on top (ordered among themselves by [mode]).
  final bool favoritesFirst;

  /// Channel keys in the user's order, used when [mode] is manual.
  final List<String> manualOrder;

  /// Returns a copy with the given fields replaced.
  ChannelSort copyWith({
    SortMode? mode,
    bool? favoritesFirst,
    List<String>? manualOrder,
  }) => ChannelSort(
    mode: mode ?? this.mode,
    favoritesFirst: favoritesFirst ?? this.favoritesFirst,
    manualOrder: manualOrder ?? this.manualOrder,
  );

  /// JSON form for storage.
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'favoritesFirst': favoritesFirst,
    'manualOrder': manualOrder,
  };
}

/// Ordering and visibility preferences for a playlist's categories.
class CategorySort {
  const CategorySort({
    this.mode = SortMode.original,
    this.manualOrder = const [],
    this.hidden = const {},
  });

  /// Restores preferences saved with [toJson]; unknown values fall back to defaults.
  factory CategorySort.fromJson(Map<String, Object?> json) => CategorySort(
    mode: _modeFromJson(json['mode']),
    manualOrder: _stringList(json['manualOrder']),
    hidden: _stringList(json['hidden']).toSet(),
  );

  final SortMode mode;

  /// Category ids in the user's order, used when [mode] is manual.
  final List<String> manualOrder;

  /// Ids of categories the user has hidden.
  final Set<String> hidden;

  /// Returns a copy with the given fields replaced.
  CategorySort copyWith({
    SortMode? mode,
    List<String>? manualOrder,
    Set<String>? hidden,
  }) => CategorySort(
    mode: mode ?? this.mode,
    manualOrder: manualOrder ?? this.manualOrder,
    hidden: hidden ?? this.hidden,
  );

  /// JSON form for storage.
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'manualOrder': manualOrder,
    'hidden': hidden.toList(),
  };
}

const _diacritics = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ý': 'y',
  'ÿ': 'y',
};

/// Lowercases [text] and strips common Latin diacritics, for sorting and search.
String foldText(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_diacritics[char] ?? char);
  }
  return buffer.toString();
}

final _chunkPattern = RegExp(r'\d+|\D+');

/// A name folded and split into digit and non-digit chunks, computed once so
/// sorting does not redo it on every comparison.
class _NaturalKey {
  _NaturalKey(String name)
    : chunks = [
        for (final m in _chunkPattern.allMatches(foldText(name))) m[0]!,
      ] {
    numbers = [for (final chunk in chunks) int.tryParse(chunk)];
  }

  final List<String> chunks;

  /// Numeric value of each chunk, or `null` when it is not a number.
  late final List<int?> numbers;

  /// Compares chunk by chunk; digit runs compare as numbers.
  int compareTo(_NaturalKey other) {
    for (var i = 0; i < chunks.length && i < other.chunks.length; i++) {
      final numX = numbers[i];
      final numY = other.numbers[i];
      final result = numX != null && numY != null
          ? numX.compareTo(numY)
          : chunks[i].compareTo(other.chunks[i]);
      if (result != 0) return result;
    }
    return chunks.length.compareTo(other.chunks.length);
  }
}

/// Natural, case- and accent-insensitive comparison: digit runs compare as
/// numbers, so "Canal 2" sorts before "Canal 10".
int naturalCompare(String a, String b) =>
    _NaturalKey(a).compareTo(_NaturalKey(b));

/// [currentKeys] reordered by [savedOrder]: saved keys that still exist, in
/// saved order, then keys not in [savedOrder] in their current order.
List<String> applyManualOrder(
  List<String> currentKeys,
  List<String> savedOrder,
) {
  final present = currentKeys.toSet();
  final ordered = [
    for (final key in savedOrder)
      if (present.contains(key)) key,
  ];
  final placed = ordered.toSet();
  return [
    ...ordered,
    for (final key in currentKeys)
      if (!placed.contains(key)) key,
  ];
}

/// The [edited] manual order plus the keys of [previous] that are absent from
/// it (items missing from the current catalog), each re-inserted after its
/// nearest preceding key in [previous], so they get their place back when
/// they return. Keys with no present predecessor go first.
List<String> mergeManualOrder(List<String> edited, List<String> previous) {
  final result = List.of(edited);
  final placed = edited.toSet();
  for (var i = 0; i < previous.length; i++) {
    final key = previous[i];
    if (placed.contains(key)) continue;
    var insertAt = 0;
    for (var j = i - 1; j >= 0; j--) {
      final index = result.indexOf(previous[j]);
      if (index != -1) {
        insertAt = index + 1;
        break;
      }
    }
    result.insert(insertAt, key);
    placed.add(key);
  }
  return result;
}

/// Stable sort of [items] by [mode], using [keyOf] for manual order and
/// [nameOf] for alphabetical modes.
List<T> _sortBy<T>(
  List<T> items,
  SortMode mode,
  List<String> manualOrder,
  String Function(T) keyOf,
  String Function(T) nameOf,
) {
  switch (mode) {
    case SortMode.original:
      return List.of(items);
    case SortMode.manual:
      final byKey = {for (final item in items) keyOf(item): item};
      return [
        for (final key in applyManualOrder(
          items.map(keyOf).toList(),
          manualOrder,
        ))
          byKey[key] as T,
      ];
    case SortMode.alphaAsc:
    case SortMode.alphaDesc:
      final sign = mode == SortMode.alphaAsc ? 1 : -1;
      final keys = [for (final item in items) _NaturalKey(nameOf(item))];
      // Sort indices so equal names keep their original order (List.sort is not stable).
      final indices = List.generate(items.length, (i) => i)
        ..sort((i, j) {
          final result = sign * keys[i].compareTo(keys[j]);
          return result != 0 ? result : i.compareTo(j);
        });
      return [for (final i in indices) items[i]];
  }
}

/// Orders [channels] by [sort]; with `favoritesFirst`, channels whose key is in
/// [favoriteKeys] go on top, keeping the same order inside each block.
List<Channel> sortChannels(
  List<Channel> channels,
  ChannelSort sort,
  Set<String> favoriteKeys,
) {
  final sorted = _sortBy(
    channels,
    sort.mode,
    sort.manualOrder,
    (c) => c.key,
    (c) => c.name,
  );
  if (!sort.favoritesFirst) return sorted;
  return [
    ...sorted.where((c) => favoriteKeys.contains(c.key)),
    ...sorted.where((c) => !favoriteKeys.contains(c.key)),
  ];
}

/// Orders [categories] by [sort] and drops hidden ones unless [includeHidden].
List<Category> sortCategories(
  List<Category> categories,
  CategorySort sort, {
  bool includeHidden = false,
}) {
  final sorted = _sortBy(
    categories,
    sort.mode,
    sort.manualOrder,
    (c) => c.id,
    (c) => c.name,
  );
  if (includeHidden) return sorted;
  return sorted.where((c) => !sort.hidden.contains(c.id)).toList();
}
