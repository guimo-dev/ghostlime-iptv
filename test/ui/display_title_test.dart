import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/display_title.dart';

void main() {
  test('strips country prefix and extracts year and tags', () {
    final t = displayTitle('ES - The Storm - 2026 (SUB)  ');
    expect(t.title, 'The Storm');
    expect(t.details, ['2026', 'SUB']);
  });

  test('handles square-bracket tags and no year', () {
    final t = displayTitle('ES - Insidious: Out of the Further - 2026 [4K]');
    expect(t.title, 'Insidious: Out of the Further');
    expect(t.details, ['2026', '4K']);
  });

  test('keeps hyphens inside the title', () {
    final t = displayTitle('ES - Spider-Man: Brand New Day - 2026');
    expect(t.title, 'Spider-Man: Brand New Day');
    expect(t.details, ['2026']);
  });

  test('channel-like names without pattern stay as they are', () {
    final t = displayTitle('M. Deportes 1 HD');
    expect(t.title, 'M. Deportes 1 HD');
    expect(t.details, isEmpty);
  });

  test('series names with multi tags', () {
    final t = displayTitle(
      'ES - Tragedia en el Estadio Corregidora [MULTI-SUB]',
    );
    expect(t.title, 'Tragedia en el Estadio Corregidora');
    expect(t.details, ['MULTI-SUB']);
  });

  test('never returns an empty title', () {
    expect(displayTitle('ES - ').title, 'ES -');
  });

  test('distinctNames suffixes later repeats only', () {
    expect(distinctNames(['La 1', 'La 2', 'La 1', 'La 1']), [
      'La 1',
      'La 2',
      'La 1 · 2',
      'La 1 · 3',
    ]);
    expect(distinctNames(['A', 'B']), ['A', 'B']);
  });
}
