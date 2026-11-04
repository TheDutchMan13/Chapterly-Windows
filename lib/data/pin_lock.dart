import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A random salt, so the same PIN never gives the same stored value twice.
String newPinSalt([Random? random]) {
  final source = random ?? Random.secure();
  return base64UrlEncode(List.generate(16, (_) => source.nextInt(256)));
}

/// How PINs were stored before 1.21.0: one salted SHA-256. Still read, and
/// replaced by [hashNewPin] the next time the PIN is typed right.
String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

/// PBKDF2 with HMAC-SHA256 (RFC 8018).
Uint8List pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations, [
  int length = 32,
]) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder(copy: false);
  for (var block = 1; out.length < length; block++) {
    var u = hmac.convert([
      ...salt,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}

/// How many PBKDF2 rounds a new PIN gets.
const pinHashIterations = 100000;

const _pbkdf2Prefix = 'pbkdf2';

/// What is stored for a new PIN: "pbkdf2$rounds$salt$hash", the salt and
/// hash in base64url. Slow on purpose, so a copied settings file can't be
/// tried against every PIN quickly.
String hashNewPin(String pin, {int iterations = pinHashIterations, Random? random}) {
  final source = random ?? Random.secure();
  final salt = List.generate(16, (_) => source.nextInt(256));
  final hash = pbkdf2Sha256(utf8.encode(pin), salt, iterations);
  return '$_pbkdf2Prefix\$$iterations\$${base64UrlEncode(salt)}\$'
      '${base64UrlEncode(hash)}';
}

/// Whether [stored] is in the old format, to be replaced on the next right
/// PIN.
bool isOldPinHash(String stored) => !stored.startsWith('$_pbkdf2Prefix\$');

/// Whether [pin] is the PIN behind [stored]: the PBKDF2 format, or the old
/// one with its [oldSalt].
bool pinMatches(String pin, String stored, {String? oldSalt}) {
  if (isOldPinHash(stored)) {
    return oldSalt != null && _sameText(hashPin(pin, oldSalt), stored);
  }
  final parts = stored.split(r'$');
  if (parts.length != 4) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1 || iterations > 10000000) {
    return false;
  }
  try {
    final salt = base64Url.decode(parts[2]);
    final hash = base64Url.decode(parts[3]);
    final got = pbkdf2Sha256(utf8.encode(pin), salt, iterations, hash.length);
    return _sameBytes(got, hash);
  } on FormatException {
    return false;
  }
}

bool _sameText(String a, String b) => _sameBytes(utf8.encode(a), utf8.encode(b));

/// Compares without stopping at the first difference.
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Counts wrong PINs across every PIN prompt (the lock screen, changing or
/// removing the PIN, deleting a profile) and makes you wait after too many,
/// longer each time. Kept in the settings, so restarting Chapterly does not
/// start the count again.
class PinGuard {
  PinGuard(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static Future<PinGuard> load() async =>
      PinGuard(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const _failuresKey = 'pinGuardFailures';
  static const _untilKey = 'pinGuardUntil';

  /// Wrong PINs allowed before the first wait.
  static const freeTries = 5;
  static const firstWait = Duration(seconds: 30);
  static const longestWait = Duration(hours: 1);

  int get failures => _prefs.getInt(_failuresKey) ?? 0;

  /// The wait after [failures] wrong PINs in a row: none for the first
  /// [freeTries] - 1, then 30 seconds, doubling each time, up to an hour.
  static Duration waitAfter(int failures) {
    if (failures < freeTries) return Duration.zero;
    final doublings = min(failures - freeTries, 7);
    final wait = firstWait * pow(2, doublings).toInt();
    return wait > longestWait ? longestWait : wait;
  }

  /// How long until a PIN may be tried again; zero when it may.
  Duration get waitLeft {
    final until = _prefs.getInt(_untilKey);
    if (until == null) return Duration.zero;
    final left = DateTime.fromMillisecondsSinceEpoch(until).difference(_now());
    if (left.isNegative) return Duration.zero;
    // A clock put back can't make the wait longer than the longest.
    return left > longestWait ? longestWait : left;
  }

  /// Counts a wrong PIN. Returns the wait it starts (zero for none).
  Future<Duration> recordFailure() async {
    final count = failures + 1;
    await _prefs.setInt(_failuresKey, count);
    final wait = waitAfter(count);
    if (wait > Duration.zero) {
      await _prefs.setInt(
        _untilKey,
        _now().add(wait).millisecondsSinceEpoch,
      );
    }
    return wait;
  }

  /// A right PIN: the count starts again.
  Future<void> recordSuccess() async {
    await _prefs.remove(_failuresKey);
    await _prefs.remove(_untilKey);
  }
}

/// "Too many tries. Wait 30 seconds." for [wait].
String pinWaitMessage(Duration wait) {
  final seconds = (wait.inMilliseconds / 1000).ceil();
  if (seconds <= 90) return 'Too many tries. Wait $seconds seconds.';
  final minutes = (seconds / 60).ceil();
  return 'Too many tries. Wait $minutes minutes.';
}

/// Checks a PIN with [check] through the shared [PinGuard]. Returns null
/// when it was right, or the message to show (wrong, or wait).
Future<String?> checkPinGuarded(bool Function() check, {PinGuard? guard}) async {
  final pins = guard ?? await PinGuard.load();
  final left = pins.waitLeft;
  if (left > Duration.zero) return pinWaitMessage(left);
  if (check()) {
    await pins.recordSuccess();
    return null;
  }
  final wait = await pins.recordFailure();
  return wait > Duration.zero ? pinWaitMessage(wait) : 'Wrong PIN.';
}
