import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// The title and author in a PDF's document information, when they are
/// written plainly in the file. Empty strings for what cannot be found,
/// such as when the information sits inside a compressed part.
///
/// The trailer says which object holds the information ("/Info 12 0 R");
/// bookmarks also have a /Title, so the first /Title in the file is not it.
({String title, String author}) pdfTitleAndAuthor(Uint8List bytes) {
  const none = (title: '', author: '');
  try {
    // One character per byte, so positions match and nothing is lost.
    final text = latin1.decode(bytes);
    final ref = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text).lastOrNull;
    if (ref == null) return none;
    // A later copy of an object (an edit saved at the end) wins.
    final start = RegExp('(?:^|[^0-9])${ref[1]}\\s+${ref[2]}\\s+obj')
        .allMatches(text)
        .lastOrNull;
    if (start == null) return none;
    final end = text.indexOf('endobj', start.end);
    final dict = text.substring(
      start.end,
      end < 0 ? math.min(start.end + 65536, text.length) : end,
    );
    return (title: _field(dict, 'Title'), author: _field(dict, 'Author'));
  } catch (_) {
    return none;
  }
}

/// The text of `/key` in a dictionary: a `(literal)` or a `<hex>` string.
String _field(String dict, String key) {
  final match = RegExp('/$key(?![A-Za-z0-9])\\s*([(<])').firstMatch(dict);
  if (match == null) return '';
  final at = match.end - 1;
  final bytes = match[1] == '(' ? _literal(dict, at) : _hex(dict, at);
  return _decode(bytes).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The bytes of a literal string starting with the "(" at [start]:
/// nested brackets are kept, escapes are undone.
List<int> _literal(String s, int start) {
  final out = <int>[];
  var depth = 0;
  var i = start;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x5C) {
      // A backslash escape.
      i++;
      if (i >= s.length) break;
      final e = s.codeUnitAt(i);
      if (e >= 0x30 && e <= 0x37) {
        // Up to three octal digits.
        var value = 0;
        var digits = 0;
        while (digits < 3 &&
            i < s.length &&
            s.codeUnitAt(i) >= 0x30 &&
            s.codeUnitAt(i) <= 0x37) {
          value = value * 8 + s.codeUnitAt(i) - 0x30;
          i++;
          digits++;
        }
        out.add(value & 0xFF);
        continue;
      }
      switch (e) {
        case 0x6E: // n
          out.add(10);
        case 0x72: // r
          out.add(13);
        case 0x74: // t
          out.add(9);
        case 0x62: // b
          out.add(8);
        case 0x66: // f
          out.add(12);
        case 0x0D: // A line break after the backslash joins lines.
          if (i + 1 < s.length && s.codeUnitAt(i + 1) == 0x0A) i++;
        case 0x0A:
          break;
        default:
          out.add(e);
      }
      i++;
      continue;
    }
    if (c == 0x28) {
      depth++;
      if (depth == 1) {
        i++;
        continue;
      }
    } else if (c == 0x29) {
      depth--;
      if (depth == 0) break;
    }
    out.add(c);
    i++;
  }
  return out;
}

/// The bytes of a hex string starting with the `<` at [start].
List<int> _hex(String s, int start) {
  final end = s.indexOf('>', start);
  if (end < 0) return const [];
  var digits = s.substring(start + 1, end).replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  if (digits.length.isOdd) digits += '0';
  return [
    for (var i = 0; i < digits.length; i += 2)
      int.parse(digits.substring(i, i + 2), radix: 16),
  ];
}

/// PDF text is UTF-16 when it starts with FE FF, UTF-8 when it starts with
/// the UTF-8 mark, and otherwise close enough to Latin-1.
String _decode(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final units = <int>[
      for (var i = 2; i + 1 < bytes.length; i += 2) (bytes[i] << 8) | bytes[i + 1],
    ];
    return String.fromCharCodes(units);
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  return latin1.decode(bytes);
}
