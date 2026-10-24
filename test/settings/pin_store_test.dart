import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/settings/pin_store.dart';

void main() {
  test('constantTimeEquals compares whole strings', () {
    expect(constantTimeEquals('1234', '1234'), isTrue);
    expect(constantTimeEquals('1234', '1235'), isFalse);
    expect(constantTimeEquals('1234', '123'), isFalse);
    expect(constantTimeEquals('', ''), isTrue);
  });

  test('isValidPin accepts exactly four digits', () {
    expect(isValidPin('0000'), isTrue);
    expect(isValidPin('123'), isFalse);
    expect(isValidPin('12a4'), isFalse);
    expect(isValidPin('12345'), isFalse);
  });
}
