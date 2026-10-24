import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sync/account_form.dart';

void main() {
  test('the Google sentence only shows when Google is supported', () {
    final withGoogle = accountSyncExplanation(supportsGoogle: true);
    final without = accountSyncExplanation(supportsGoogle: false);

    expect(without, contains('Con email'));
    expect(without, contains('empezar de cero'));
    expect(without, isNot(contains('Google')));
    expect(withGoogle, startsWith(without));
    expect(withGoogle, contains('Con Google, la clave de cifrado la guarda'));
  });
}
