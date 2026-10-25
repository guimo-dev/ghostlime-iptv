import 'package:flutter/material.dart';

import '../catalog/sorting.dart';
import '../ui/choice_selector.dart';
import '../ui/form_factor.dart';

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

/// The sort options: chips on phones, segments on the desktop.
Widget _modeSelector(SortMode mode, ValueChanged<SortMode> onChanged) =>
    ChoiceSelector<SortMode>(
      options: _modeLabels,
      value: mode,
      onChanged: onChanged,
    );

/// The sheet's buttons: [secondary] ones and the [apply] one. On phones
/// [apply] goes alone on the last row, on the right, within the thumb's reach.
Widget _sheetActions(
  BuildContext context, {
  required List<Widget> secondary,
  required Widget apply,
}) {
  if (!usesPhoneLayout(context)) {
    return Wrap(spacing: 8, runSpacing: 8, children: [...secondary, apply]);
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      Wrap(spacing: 8, runSpacing: 8, children: secondary),
      Align(alignment: Alignment.centerRight, child: apply),
    ],
  );
}

/// Opens a bottom sheet with [content], scrollable when it does not fit.
Future<T?> _showSheet<T>(BuildContext context, WidgetBuilder content) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: content(context),
      ),
    ),
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
  return _showSheet<SortSheetResult>(
    context,
    (context) => StatefulBuilder(
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

        return Column(
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
            _sheetActions(
              context,
              secondary: [
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
              ],
              apply: FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, result()),
                child: const Text('Aplicar'),
              ),
            ),
          ],
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
  return _showSheet<CategorySheetResult>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) => Column(
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
          _sheetActions(
            context,
            secondary: [
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, (mode: mode, editManual: true)),
                child: const Text('Ordenar y ocultar…'),
              ),
            ],
            apply: FilledButton(
              autofocus: true,
              onPressed: () =>
                  Navigator.pop(context, (mode: mode, editManual: false)),
              child: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    ),
  );
}
