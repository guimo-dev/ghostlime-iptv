import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Supabase email templates, one per authentication email.
const _templateNames = [
  'confirmar-alta',
  'recuperar-contrasena',
  'codigo-acceso',
  'cambio-email',
  'reautenticacion',
];

void main() {
  for (final name in _templateNames) {
    test('$name template shows the code and has no link or tracking', () {
      final html = File('supabase/templates/$name.html').readAsStringSync();
      expect(html, contains('{{ .Token }}'));
      expect(html, isNot(contains('{{ .ConfirmationURL }}')));
      expect(html, contains('Si no has sido tú, ignora este correo.'));
      final images = RegExp(r'<img\s[^>]*src="([^"]+)"').allMatches(html);
      expect(images.map((match) => match.group(1)), [
        'https://github.com/guimo-dev/ghostlime-iptv/raw/main/branding/ghostlime-192.png',
      ]);
    });
  }
}
