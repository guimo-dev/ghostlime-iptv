import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../catalog/sorting.dart';
import '../live/reorder_screen.dart';
import '../live/sort_sheet.dart';

/// Shows the sort sheet for one category and saves the choice (own sort,
/// default, reset or manual order). Returns whether anything changed.
Future<bool> editChannelSort(
  BuildContext context, {
  required CatalogDb db,
  required int playlistId,
  required MediaKind kind,
  required String categoryId,
  required Set<String> favorites,
}) async {
  final result = await showSortSheet(
    context,
    current: db.channelSort(playlistId, kind, categoryId),
    isOwn: db.hasOwnChannelSort(playlistId, kind, categoryId),
  );
  if (result == null || !context.mounted) return false;
  if (result.resetToDefault) {
    db.deleteChannelSort(playlistId, kind, categoryId);
  } else if (result.editManual) {
    return _editManualOrder(
      context,
      db: db,
      playlistId: playlistId,
      kind: kind,
      categoryId: categoryId,
      favorites: favorites,
      sort: result.sort,
    );
  } else {
    db.saveChannelSort(playlistId, kind, categoryId, result.sort);
    if (result.makeDefault) {
      // The default keeps no manual order: keys belong to one category.
      db.saveDefaultChannelSort(result.sort.copyWith(manualOrder: const []));
    }
  }
  return true;
}

/// Opens the reorder screen starting from [sort] and saves the result as the
/// category's manual order, keeping items missing from the catalog right now.
Future<bool> _editManualOrder(
  BuildContext context, {
  required CatalogDb db,
  required int playlistId,
  required MediaKind kind,
  required String categoryId,
  required Set<String> favorites,
  required ChannelSort sort,
}) async {
  final start = sortChannels(
    db.channels(playlistId, categoryId),
    sort,
    favorites,
  );
  final items = await Navigator.of(context).push<List<ReorderItem>>(
    MaterialPageRoute(
      builder: (_) => ReorderScreen(
        title: 'Ordenar',
        note: sort.favoritesFirst
            ? 'Con «Favoritos primero» activo, los favoritos siempre '
                  'quedan arriba.'
            : null,
        items: [for (final c in start) ReorderItem(id: c.key, label: c.name)],
      ),
    ),
  );
  if (items == null) return false;
  final previous = db.hasOwnChannelSort(playlistId, kind, categoryId)
      ? db.channelSort(playlistId, kind, categoryId).manualOrder
      : const <String>[];
  db.saveChannelSort(
    playlistId,
    kind,
    categoryId,
    sort.copyWith(
      mode: SortMode.manual,
      manualOrder: mergeManualOrder([
        for (final item in items) item.id,
      ], previous),
    ),
  );
  return true;
}

/// Shows the category sheet (mode, or manual order and hiding) and saves it.
/// Returns the new sort, or `null` when cancelled.
Future<CategorySort?> editCategorySort(
  BuildContext context, {
  required CatalogDb db,
  required int playlistId,
  required MediaKind kind,
  required List<Category> allCategories,
  required CategorySort current,
}) async {
  final result = await showCategorySortSheet(context, current: current.mode);
  if (result == null || !context.mounted) return null;
  var sort = current.copyWith(mode: result.mode);
  if (result.editManual) {
    final items = await Navigator.of(context).push<List<ReorderItem>>(
      MaterialPageRoute(
        builder: (_) => ReorderScreen(
          title: 'Ordenar y ocultar categorías',
          allowHide: true,
          items: [
            for (final c in sortCategories(
              allCategories,
              current,
              includeHidden: true,
            ))
              ReorderItem(
                id: c.id,
                label: c.name,
                hidden: current.hidden.contains(c.id),
              ),
          ],
        ),
      ),
    );
    if (items == null) return null;
    // Keep order and hidden state of categories missing right now.
    final presentIds = {for (final c in allCategories) c.id};
    sort = CategorySort(
      mode: SortMode.manual,
      manualOrder: mergeManualOrder([
        for (final item in items) item.id,
      ], current.manualOrder),
      hidden: {
        for (final item in items)
          if (item.hidden) item.id,
        ...current.hidden.difference(presentIds),
      },
    );
  }
  db.saveCategorySort(playlistId, kind, sort);
  return sort;
}
