import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/legal/legal_screen.dart';

void main() {
  testWidgets('LegalScreen shows the privacy title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LegalScreen(doc: LegalDoc.privacy)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Política de privacidad'), findsWidgets);
    expect(find.textContaining('AES-256-GCM'), findsOneWidget);
  });
}
