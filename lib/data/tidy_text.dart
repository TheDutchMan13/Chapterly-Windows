// The same file is in the Android app; keep the two copies alike.

/// Cleans text that came from outside: web lookups, book files and library
/// catalogues. It only fixes what is clearly wrong and leaves everything
/// else exactly as it was, so a title or name that is already fine comes
/// back unchanged.
///
/// Fixes: HTML characters (`Bush&#39;s Wars` becomes `Bush's Wars`), and
/// extra spaces and line breaks.
String tidyText(String text) {
  final plain = _decodeEntities(text);
  return plain.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// [tidyText] for an author, which also fixes names written the way library
/// catalogues write them: authors split with semicolons, a trailing
/// semicolon, and birth and death years after a name. When that is how the
/// name is written, "Gordon, Michael R., 1951-;Trainor, Bernard E., 1928-"
/// becomes "Michael R. Gordon, Bernard E. Trainor".
///
/// A plain list of authors, such as "Lee Child, Andrew Child", is never
/// reordered: a comma alone cannot tell "Last, First" from two names.
String tidyAuthor(String author) {
  final text = tidyText(author);
  final hasYear = _years.hasMatch(text);
  final catalogue = text.contains(';') || hasYear;
  if (!catalogue) return text;

  var years = false;
  final names = <String>[];
  for (final part in text.split(';')) {
    var name = part;
    if (_years.hasMatch(name)) years = true;
    name = name.replaceAll(_years, '');
    name = name.replaceAll(RegExp(r'[\s,]+$'), '').trim();
    if (name.isNotEmpty) names.add(name);
  }
  if (names.isEmpty) return text;
  // "Last, First" for every name: flip them all. Anything else (a title
  // such as "Jr." makes a second comma) is left as written.
  final flip = (years || text.contains(';')) &&
      names.every((name) => name.split(', ').length == 2);
  return [
    for (final name in names)
      if (flip) '${name.split(', ')[1]} ${name.split(', ')[0]}' else name,
  ].join(', ');
}

/// Whether [text] has characters that are never in a real title or name
/// (control characters, the replacement character): a damaged import.
bool looksDamaged(String text) => _damaged.hasMatch(text);

final _years = RegExp(r',?\s*\(?\b\d{4}\s*-\s*(\d{4})?\)?(?=\s*(;|,|$))');
final _damaged = RegExp('[\u0000-\u0008\u000b-\u001f\u007f-\u009f�]');

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _decodeEntities(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(
    RegExp(r'&(#\d{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,6});'),
    (match) {
      final body = match.group(1)!;
      if (body.startsWith('#')) {
        final hex = body.startsWith('#x') || body.startsWith('#X');
        final code = int.tryParse(
          body.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        // Not a control character or something outside Unicode.
        if (code == null ||
            code < 0x20 ||
            code > 0x10FFFF ||
            (code >= 0x7f && code <= 0x9f) ||
            (code >= 0xD800 && code <= 0xDFFF)) {
          return match.group(0)!;
        }
        return String.fromCharCode(code);
      }
      return _named[body.toLowerCase()] ?? match.group(0)!;
    },
  );
}
