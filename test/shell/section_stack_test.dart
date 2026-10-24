import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/shell/section_stack.dart';

/// Records whether it is currently allowed to run (TickerMode).
class _Probe extends StatefulWidget {
  const _Probe(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.log.add('${widget.name}:${TickerMode.valuesOf(context).enabled}');
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('hidden sections are paused and visible ones resumed', (
    tester,
  ) async {
    final log = <String>[];
    Widget stack(int index) => Directionality(
      textDirection: TextDirection.ltr,
      child: SectionStack(
        index: index,
        count: 2,
        builder: (i) => _Probe(log, 's$i'),
      ),
    );

    await tester.pumpWidget(stack(0));
    expect(log, ['s0:true']);

    await tester.pumpWidget(stack(1));
    expect(log, containsAll(['s0:false', 's1:true']));

    log.clear();
    await tester.pumpWidget(stack(0));
    expect(log, containsAll(['s0:true', 's1:false']));
  });

  testWidgets('sections are built only once visited', (tester) async {
    final built = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SectionStack(
          index: 0,
          count: 3,
          builder: (i) {
            built.add(i);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(built, [0]);
  });
}
