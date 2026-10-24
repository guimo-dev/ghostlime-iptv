final _prefix = RegExp(r'^[A-Z]{2,4}\s+-\s+');
final _tag = RegExp(r'\s*[\[(]([^\])]+)[\])]\s*$');
final _year = RegExp(r'\s+-\s+((?:19|20)\d{2})\s*$');

/// Splits a provider name such as `ES - The Storm - 2026 (SUB)` into a clean
/// title (`The Storm`) and its details (`2026`, `SUB`), for display only.
///
/// Names that do not follow the pattern are returned trimmed, without details.
({String title, List<String> details}) displayTitle(String name) {
  var title = name.trim().replaceFirst(_prefix, '');
  final tags = <String>[];
  String? year;
  // Tags and the year may come in either order at the end; peel them off.
  while (true) {
    final tag = _tag.firstMatch(title);
    if (tag != null) {
      tags.insert(0, tag[1]!.trim());
      title = title.substring(0, tag.start).trimRight();
      continue;
    }
    final match = _year.firstMatch(title);
    if (match != null && year == null) {
      year = match[1];
      title = title.substring(0, match.start).trimRight();
      continue;
    }
    break;
  }
  if (title.isEmpty) return (title: name.trim(), details: const []);
  return (title: title, details: [?year, ...tags]);
}

/// Returns [names] with each repeat after the first suffixed ` · 2`, ` · 3`…,
/// so channels that share a name can be told apart in a list.
List<String> distinctNames(List<String> names) {
  final seen = <String, int>{};
  return [
    for (final name in names)
      switch (seen.update(name, (n) => n + 1, ifAbsent: () => 1)) {
        1 => name,
        final n => '$name · $n',
      },
  ];
}
