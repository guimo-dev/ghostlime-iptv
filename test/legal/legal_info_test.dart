import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/legal/legal_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legal texts exist and name the placeholders only via legalPlaceholders',
    () async {
      final marker = RegExp(r'\[[A-Z_]+\]');
      for (final doc in LegalDoc.values) {
        final text = await loadLegalText(doc);
        expect(text, startsWith('# '));
        expect(
          text,
          contains('Borrador pendiente de revisión por el responsable.'),
        );
        for (final match in marker.allMatches(text)) {
          expect(legalPlaceholders, contains(match.group(0)), reason: doc.name);
        }
      }
    },
  );

  test('hasPlaceholders detects each placeholder', () {
    for (final placeholder in legalPlaceholders) {
      expect(hasPlaceholders('contacto $placeholder'), isTrue);
    }
    expect(hasPlaceholders('texto limpio'), isFalse);
  });

  // Release guard: only runs when compiled with -Ddart.vm.product=true, so a
  // release pipeline fails while any placeholder is left in the texts.
  test('no placeholders left', () async {
    for (final doc in LegalDoc.values) {
      final text = await loadLegalText(doc);
      expect(hasPlaceholders(text), isFalse, reason: doc.name);
    }
  }, skip: !const bool.fromEnvironment('dart.vm.product'));
}
