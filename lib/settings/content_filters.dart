import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../player/play_target.dart';
import 'app_settings.dart';

final _adultPattern = RegExp(
  r'(?<![\p{L}\p{N}+])(xxx|adults?|adultos?|porn|\+18|18\+)(?![\p{L}\p{N}+])',
  caseSensitive: false,
  unicode: true,
);

/// Whether a category name looks like adult content: `xxx`, `adult(s|o|os)`,
/// `porn`, `+18` or `18+` as whole words, ignoring case.
bool isAdultCategory(String name) => _adultPattern.hasMatch(name);

/// Whether [category] may be shown: hidden when it is adult and
/// `settings.hideAdult` is on, or when it is locked and the lock is on and not
/// [unlocked] for this session.
bool isCategoryVisible({
  required AppSettings settings,
  required bool unlocked,
  required int playlistId,
  required MediaKind kind,
  required Category category,
}) {
  if (settings.hideAdult && isAdultCategory(category.name)) return false;
  final lockKey = '$playlistId/${kind.name}/${category.id}';
  if (settings.parentalLock &&
      !unlocked &&
      settings.lockedCategories.contains(lockKey)) {
    return false;
  }
  return true;
}

/// The [items] (all of one kind) outside the [hidden] category ids, resolving
/// each category through its series when it is an episode. Items that are no
/// longer in the catalog have no category and are kept.
List<Progress> visibleProgress(
  List<Progress> items,
  CatalogDb db,
  int playlistId,
  Set<String> hidden,
) => items.where((p) {
  final category = db.categoryOfItem(
    playlistId,
    p.target.kind,
    p.target.seriesKey ?? p.target.key,
  );
  return !hidden.contains(category);
}).toList();

/// Ids of the [categories] that [isCategoryVisible] hides, to filter items by
/// their `categoryId` (items of unknown categories are kept).
Set<String> hiddenCategoryIds({
  required AppSettings settings,
  required bool unlocked,
  required int playlistId,
  required MediaKind kind,
  required List<Category> categories,
}) => {
  for (final category in categories)
    if (!isCategoryVisible(
      settings: settings,
      unlocked: unlocked,
      playlistId: playlistId,
      kind: kind,
      category: category,
    ))
      category.id,
};
