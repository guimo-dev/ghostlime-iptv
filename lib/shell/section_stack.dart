import 'package:flutter/widgets.dart';

/// Shows section [index] of [count], building each section the first time it
/// is shown and keeping it alive afterwards.
///
/// Hidden sections run under `TickerMode(enabled: false)`, which `IndexedStack`
/// alone does not do: sections use it to pause work (e.g. stop a live preview
/// stream) and to reload their data when shown again.
class SectionStack extends StatefulWidget {
  const SectionStack({
    super.key,
    required this.index,
    required this.count,
    required this.builder,
  });

  final int index;
  final int count;
  final Widget Function(int index) builder;

  @override
  State<SectionStack> createState() => _SectionStackState();
}

class _SectionStackState extends State<SectionStack> {
  final Set<int> _visited = {};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.count; i++)
          TickerMode(
            enabled: i == widget.index,
            child: _visited.contains(i)
                ? widget.builder(i)
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
