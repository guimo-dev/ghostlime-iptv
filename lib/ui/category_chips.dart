import 'package:flutter/material.dart';

/// One chip of [CategoryChips].
typedef ChipItem = ({String id, String label, IconData? icon});

/// Horizontally scrolling, focusable category chips with optional trailing
/// actions (sort, organize).
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.trailing = const [],
  });

  final List<ChipItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return Center(
                  child: ChoiceChip(
                    avatar: item.icon == null
                        ? null
                        : Icon(item.icon, size: 16),
                    label: Text(item.label),
                    selected: item.id == selectedId,
                    onSelected: (_) => onSelected(item.id),
                  ),
                );
              },
            ),
          ),
          ...trailing,
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}
