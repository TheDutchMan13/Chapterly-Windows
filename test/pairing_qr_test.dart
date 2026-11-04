import 'dart:math';

import 'package:chapterly/data/pairing_qr.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clock that only moves when the test waits.
class _Clock {
  DateTime now = DateTime(2026, 11, 4);

  DateTime read() => now;

  Future<void> wait(Duration duration) async {
    now = now.add(duration);
  }
}

QrPairing _pairing(
  _Clock clock, {
  required Future<List<String>> Function() find,
  required Future<String?> Function(String address, String code) tryPair,
}) =>
    QrPairing(
      find: find,
      tryPair: tryPair,
      now: clock.read,
      wait: clock.wait,
    );

const _wrong = 'The pairing code is wrong. Check it on your phone under '
    'Settings > Sync with a PC.';

void main() {
  group('codes and payload', () {
    test('a new code is 16 letters and numbers the phone accepts', () {
      final code = newPairingCode();
      expect(code, matches(RegExp(r'^[A-Z0-9]{16}$')));
      expect(normalizeSyncCode(code), code);
      expect(code, isNot(matches(RegExp('[OIL01]'))));
    });

    test('every code is different', () {
      final codes = {for (var i = 0; i < 50; i++) newPairingCode()};
      expect(codes.length, 50);
    });

    test('a seeded generator gives a repeatable code', () {
      expect(newPairingCode(Random(7)), newPairingCode(Random(7)));
    });

    test('the payload is exactly chapterly-pair:1:<CODE>', () {
      expect(
        pairingQrPayload('ABCDEFGHJKMNPQRS'),
        'chapterly-pair:1:ABCDEFGHJKMNPQRS',
      );
      final code = newPairingCode();
      expect(pairingQrPayload(code), 'chapterly-pair:1:$code');
    });

    test('a code of the wrong shape has no payload', () {
      expect(() => pairingQrPayload('SHORT'), throwsArgumentError);
    });
  });

  group('QrPairing', () {
    test('pairs on the third poll and stops', () async {
      final clock = _Clock();
      var finds = 0;
      final tried = <String>[];
      final pairing = _pairing(
        clock,
        find: () async {
          finds++;
          return ['192.168.1.20:8765'];
        },
        tryPair: (address, code) async {
          tried.add('$address $code');
          return tried.length < 3 ? _wrong : null;
        },
      );
      final result = await pairing.run('ABCDEFGHJKMNPQRS');
      expect(result.outcome, QrPairingOutcome.paired);
      expect(result.address, '192.168.1.20:8765');
      expect(finds, 3);
      expect(tried.last, '192.168.1.20:8765 ABCDEFGHJKMNPQRS');
      expect(clock.now.difference(DateTime(2026, 11, 4)).inSeconds, 6);
    });

    test('keeps going while no phone is found or the code is refused',
        () async {
      final clock = _Clock();
      var finds = 0;
      final pairing = _pairing(
        clock,
        find: () async => ++finds < 4 ? const [] : ['10.0.0.5:8765'],
        tryPair: (address, code) async => finds < 6 ? _wrong : null,
      );
      final result = await pairing.run('ABCDEFGHJKMNPQRS');
      expect(result.outcome, QrPairingOutcome.paired);
      expect(finds, 6);
    });

    test('tries every phone found and keeps the one that accepts', () async {
      final clock = _Clock();
      final pairing = _pairing(
        clock,
        find: () async => ['10.0.0.5:8765', '10.0.0.6:8765'],
        tryPair: (address, code) async =>
            address.startsWith('10.0.0.6') ? null : _wrong,
      );
      final result = await pairing.run('ABCDEFGHJKMNPQRS');
      expect(result.address, '10.0.0.6:8765');
    });

    test('a lasting problem is reported and polling goes on', () async {
      final clock = _Clock();
      var rounds = 0;
      final problems = <String?>[];
      final pairing = _pairing(
        clock,
        find: () async => ['10.0.0.5:8765'],
        tryPair: (address, code) async {
          rounds++;
          if (rounds == 1) return updatePhoneForSyncMessage;
          return rounds < 3 ? _wrong : null;
        },
      );
      final result = await pairing.run(
        'ABCDEFGHJKMNPQRS',
        onProblem: problems.add,
      );
      expect(result.outcome, QrPairingOutcome.paired);
      expect(problems, [updatePhoneForSyncMessage, null]);
    });

    test('an error while pairing counts as not yet', () async {
      final clock = _Clock();
      var rounds = 0;
      final pairing = _pairing(
        clock,
        find: () async {
          if (++rounds == 1) throw StateError('network down');
          return ['10.0.0.5:8765'];
        },
        tryPair: (address, code) async {
          if (rounds == 2) throw StateError('closed');
          return null;
        },
      );
      final result = await pairing.run('ABCDEFGHJKMNPQRS');
      expect(result.outcome, QrPairingOutcome.paired);
      expect(rounds, 3);
    });

    test('stops after cancel', () async {
      final clock = _Clock();
      late final QrPairing pairing;
      var finds = 0;
      pairing = _pairing(
        clock,
        find: () async {
          if (++finds == 2) pairing.cancel();
          return const [];
        },
        tryPair: (address, code) async => _wrong,
      );
      final result = await pairing.run('ABCDEFGHJKMNPQRS');
      expect(result.outcome, QrPairingOutcome.cancelled);
      expect(finds, 2);
    });

    test('does not scan again once cancelled before it starts', () async {
      final clock = _Clock();
      var finds = 0;
      final pairing = _pairing(
        clock,
        find: () async {
          finds++;
          return const [];
        },
        tryPair: (address, code) async => _wrong,
      )..cancel();
      final result = await pairing.run('ABCDEFGHJKMNPQRS');
      expect(result.outcome, QrPairingOutcome.cancelled);
      expect(finds, 0);
    });

    test('times out after five minutes of polling every three seconds',
        () async {
      final clock = _Clock();
      var finds = 0;
      final pairing = _pairing(
        clock,
        find: () async {
          finds++;
          return ['10.0.0.5:8765'];
        },
        tryPair: (address, code) async => _wrong,
      );
      final result = await pairing.run('ABCDEFGHJKMNPQRS');
      expect(result.outcome, QrPairingOutcome.timedOut);
      expect(finds, 100);
    });
  });
}
