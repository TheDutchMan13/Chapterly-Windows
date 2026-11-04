/// Reads a server code: `chapterly-server:1|<host>:<port>|<token>`, as the
/// book server prints it with "add-user" and "new-token". Returns the
/// address (`host:port`) and the token, or null when [text] is anything else.
///
/// The same function is in the Android app; keep both the same.
({String address, String token})? parseServerCode(String text) {
  final parts = text.trim().split('|');
  if (parts.length != 3 || parts[0] != 'chapterly-server:1') return null;
  final address = parts[1];
  final token = parts[2];
  if (!_address.hasMatch(address) || !_token.hasMatch(token)) return null;
  final port = int.parse(address.substring(address.lastIndexOf(':') + 1));
  if (port < 1 || port > 65535) return null;
  return (address: address, token: token);
}

/// A host (an IPv4 address or a name) and a port of up to five digits.
final _address = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?:[0-9]{1,5}$');

/// URL-safe characters only.
final _token = RegExp(r'^[A-Za-z0-9_.~-]+$');
