import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A random salt, so the same PIN never gives the same stored value twice.
String newPinSalt([Random? random]) {
  final source = random ?? Random.secure();
  return base64UrlEncode(List.generate(16, (_) => source.nextInt(256)));
}

/// What is stored instead of the PIN itself.
String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();
