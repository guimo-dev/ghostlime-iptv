import 'package:flutter/material.dart';

import '../catalog/sorting.dart';

/// What the user chose in the channel sort sheet.
typedef SortSheetResult = ({
  ChannelSort sort,
  bool makeDefault,
  bool resetToDefault,
  bool editManual,
});

/// What the user chose in the category sort sheet.
typedef CategorySheetResult = ({SortMode mode, bool editManual});

const _modeLabels = {
  SortMode.original: 'Original',
  SortMode.alphaAsc: 'A→Z',
  SortMode.alphaDesc: 'Z→A',
  SortMode.manual: 'Manual',
};

Widget _modeSelector(SortMode mode, ValueChanged<SortMode> onChanged) {
  return SegmentedButton<SortMode>(
    segments: [
      for (final entry in _modeLabels.entries)
        ButtonSegment(value: entry.key, label: Text(entry.value)),
    ],
    selected: {mode},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

/// Bottom sheet to choose how a category's channels are sorted.
///
/// [isOwn] tells whether the category has its own sort (enables "reset").
Future<SortSheetResult?> showSortSheet(
  BuildContext context, {
  required ChannelSort current,
  required bool isOwn,
}) {
  var sort = current;
  return showModalBottomSheet<SortSheetResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        SortSheetResult result({
          bool makeDefault = false,
          bool resetToDefault = false,
          bool editManual = false,
        }) => (
          sort: sort,
          makeDefault: makeDefault,
          resetToDefault: resetToDefault,
          editManual: editManual,
        );

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ordenar canales',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _modeSelector(
                sort.mode,
                (mode) => setState(() => sort = sort.copyWith(mode: mode)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Favoritos primero'),
                value: sort.favoritesFirst,
                onChanged: (value) =>
                    setState(() => sort = sort.copyWith(favoritesFirst: value)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, result(editManual: true)),
                    child: const Text('Ordenar a mano…'),
                  ),
                  // A manual order belongs to one category: no manual default.
                  if (sort.mode != SortMode.manual)
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, result(makeDefault: true)),
                      child: const Text('Usar como predeterminado'),
                    ),
                  if (isOwn)
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, result(resetToDefault: true)),
                      child: const Text('Volver al predeterminado'),
                    ),
                  FilledButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(context, result()),
                    child: const Text('Aplicar'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Bottom sheet to choose how categories are sorted, or to edit them by hand.
Future<CategorySheetResult?> showCategorySortSheet(
  BuildContext context, {
  required SortMode current,
}) {
  var mode = current;
  return showModalBottomSheet<CategorySheetResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Organizar categorías',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _modeSelector(mode, (value) => setState(() => mode = value)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, (mode: mode, editManual: true)),
                  child: const Text('Ordenar y ocultar…'),
                ),
                FilledButton(
                  autofocus: true,
                  onPressed: () =>
                      Navigator.pop(context, (mode: mode, editManual: false)),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
