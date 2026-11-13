import 'dart:async';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/pin_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the PIN is checked without holding up the window', () async {
    final stored = hashNewPin('2468');
    // A timer that fires every few milliseconds must keep firing while the
    // check runs; the old check, on the main thread, let it starve.
    var longestGap = Duration.zero;
    var last = DateTime.now();
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = DateTime.now();
      final gap = now.difference(last);
      if (gap > longestGap) longestGap = gap;
      last = now;
    });
    last = DateTime.now();
    final right = await pinMatchesAsync('2468', stored);
    final wrong = await pinMatchesAsync('2469', stored);
    timer.cancel();
    expect(right, isTrue);
    expect(wrong, isFalse);
    expect(longestGap, lessThan(const Duration(milliseconds: 150)));
  });

  test('settings check the PIN off the main thread too', () async {
    final settings = AppSettings()..setPin('4821');
    expect(await settings.checkPinAsync('4821'), isTrue);
    expect(await settings.checkPinAsync('0000'), isFalse);
  });
}
