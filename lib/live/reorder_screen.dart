import 'package:flutter/material.dart';

import '../tv/tv_initial_focus.dart';
import '../ui/backdrop.dart';
import '../ui/bottom_action_bar.dart';
import '../ui/content_width.dart';

/// One row of [ReorderScreen].
class ReorderItem {
  const ReorderItem({
    required this.id,
    required this.label,
    this.hidden = false,
  });

  final String id;
  final String label;
  final bool hidden;

  ReorderItem withHidden(bool value) =>
      ReorderItem(id: id, label: label, hidden: value);
}

enum _Move { up, down, top, bottom }

/// Lets the user reorder [items] by dragging or with Up/Down/Top/Bottom
/// actions (keyboard and remote friendly), and optionally hide them.
///
/// Pops the new list, or `null` when cancelled.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({
    super.key,
    required this.title,
    required this.items,
    this.allowHide = false,
    this.note,
  });

  final String title;
  final List<ReorderItem> items;
  final bool allowHide;

  /// Optional hint shown above the list.
  final String? note;

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  late final List<ReorderItem> _items = List.of(widget.items);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
  }

  void _move(int index, _Move move) {
    final target = switch (move) {
      _Move.up => index - 1,
      _Move.down => index + 1,
      _Move.top => 0,
      _Move.bottom => _items.length - 1,
    };
    if (target < 0 || target >= _items.length || target == index) return;
    setState(() => _items.insert(target, _items.removeAt(index)));
  }

  @override
  Widget build(BuildContext context) {
    // Phones: Cancelar and Guardar at the bottom, within the thumb's reach.
    final bottomActions = usesBottomActions(context);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.title),
          actions: bottomActions
              ? null
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _items),
                    child: const Text('Guardar'),
                  ),
                  const SizedBox(width: 12),
                ],
        ),
        body: Column(
          children: [
            if (widget.note != null)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(widget.note!),
                ),
              ),
            Expanded(
              // On a TV the first row takes the focus.
              child: TvInitialFocus(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      ReorderableListView.builder(
                        padding: ContentWidth.paddingFor(
                          constraints.maxWidth,
                          EdgeInsets.zero,
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: _items.length,
                        onReorderItem: _onReorder,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return ListTile(
                            key: ValueKey(item.id),
                            dense: true,
                            leading: widget.allowHide
                                ? Checkbox(
                                    value: !item.hidden,
                                    semanticLabel: 'Visible',
                                    onChanged: (visible) => setState(
                                      () => _items[index] = item.withHidden(
                                        visible == false,
                                      ),
                                    ),
                                  )
                                : null,
                            title: Text(
                              item.label,
                              style: item.hidden
                                  ? TextStyle(
                                      color: Theme.of(context).disabledColor,
                                    )
                                  : null,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<_Move>(
                                  tooltip: 'Mover',
                                  icon: const Icon(Icons.swap_vert),
                                  onSelected: (move) => _move(index, move),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: _Move.up,
                                      child: Text('Subir'),
                                    ),
                                    PopupMenuItem(
                                      value: _Move.down,
                                      child: Text('Bajar'),
                                    ),
                                    PopupMenuItem(
                                      value: _Move.top,
                                      child: Text('Al principio'),
                                    ),
                                    PopupMenuItem(
                                      value: _Move.bottom,
                                      child: Text('Al final'),
                                    ),
                                  ],
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                ),
              ),
            ),
            if (bottomActions)
              BottomActionBar(
                onCancel: () => Navigator.pop(context),
                onSave: () => Navigator.pop(context, _items),
              ),
          ],
        ),
      ),
    );
  }
}
