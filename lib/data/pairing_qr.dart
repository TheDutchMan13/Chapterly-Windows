import 'dart:async';
import 'dart:math';

import 'pc_sync.dart' show normalizeSyncCode;

/// The letters and numbers a new pairing code is made of: A-Z and 0-9 without
/// the ones that look alike (I, L, O, 0 and 1), so 31 symbols.
const pairingCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// How long a pairing code is.
const pairingCodeLength = 16;

/// A new random pairing code of [pairingCodeLength] characters. Pass [random]
/// only in tests; the default is [Random.secure].
String newPairingCode([Random? random]) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < pairingCodeLength; i++) {
    buffer.write(
      pairingCodeAlphabet[source.nextInt(pairingCodeAlphabet.length)],
    );
  }
  return buffer.toString();
}

/// The text in the QR code the phone scans: `chapterly-pair:1:<CODE>`.
/// Throws an [ArgumentError] when [code] is not 16 letters and numbers.
String pairingQrPayload(String code) {
  final clean = normalizeSyncCode(code);
  if (clean == null) {
    throw ArgumentError.value(code, 'code', 'Not a 16 character pairing code');
  }
  return 'chapterly-pair:1:$clean';
}

/// Whether [message] (what pairing answered) is a real problem to show, as
/// opposed to a phone that simply has not scanned the code yet.
bool isLastingPairingProblem(String message) =>
    message.startsWith('Update Chapterly on your phone') ||
    message.contains('Update the Windows app');

/// How a [QrPairing] run ended.
enum QrPairingOutcome { paired, timedOut, cancelled }

/// The end of a [QrPairing] run. [address] is the phone when [outcome] is
/// [QrPairingOutcome.paired].
class QrPairingResult {
  const QrPairingResult(this.outcome, {this.address});

  final QrPairingOutcome outcome;
  final String? address;
}

/// Looks for the phone that scans the QR code: every few seconds it finds the
/// phones on the network and tries to pair each with the code in the QR code.
/// A phone that has not scanned the code refuses, which only means "not yet".
class QrPairing {
  QrPairing({
    required this.find,
    required this.tryPair,
    this.interval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 5),
    DateTime Function()? now,
    Future<void> Function(Duration duration)? wait,
  })  : _now = now ?? DateTime.now,
        _wait = wait ?? Future<void>.delayed;

  /// Finds phones, such as 192.168.1.20:8765. Only one scan runs at a time.
  final Future<List<String>> Function() find;

  /// Pairs with the phone at an address using a code. Returns null when it
  /// worked, or the problem to show.
  final Future<String?> Function(String address, String code) tryPair;

  final Duration interval;
  final Duration timeout;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _wait;

  final _cancelled = Completer<void>();

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Stops [run] as soon as the step it is in is done.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  /// Polls until a phone pairs, [timeout] passes or [cancel] is called.
  /// [onProblem] gets a lasting problem (such as a phone that needs updating),
  /// and null after a round that had none.
  Future<QrPairingResult> run(
    String code, {
    void Function(String? problem)? onProblem,
  }) async {
    final start = _now();
    while (!isCancelled && _now().difference(start) < timeout) {
      String? problem;
      List<String> phones;
      try {
        phones = await find();
      } catch (_) {
        phones = const [];
      }
      for (final address in phones) {
        if (isCancelled) break;
        String? answer;
        try {
          answer = await tryPair(address, code);
        } catch (_) {
          answer = 'Could not reach the phone.';
        }
        if (answer == null) {
          return QrPairingResult(QrPairingOutcome.paired, address: address);
        }
        if (isLastingPairingProblem(answer)) problem = answer;
      }
      if (isCancelled) break;
      onProblem?.call(problem);
      await Future.any([_wait(interval), _cancelled.future]);
    }
    return QrPairingResult(
      isCancelled ? QrPairingOutcome.cancelled : QrPairingOutcome.timedOut,
    );
  }
}

/// Shown when no phone scanned the code in time.
const qrPairingTimedOutMessage = 'No phone found. Check that Chapterly is open '
    'on the phone and both are on the same Wi-Fi';
