/// The element of [ordered] right after the one matching [isCurrent], or
/// `null` when it is the last one or none matches.
T? nextAfter<T>(List<T> ordered, bool Function(T) isCurrent) {
  final index = ordered.indexWhere(isCurrent);
  if (index < 0 || index + 1 >= ordered.length) return null;
  return ordered[index + 1];
}
