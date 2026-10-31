import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// The same file is in the Android and the Windows app.

/// The title and authors written inside an EPUB, read without opening the
/// whole book. Several authors are joined with ", ". Null when the file is
/// not an EPUB; empty strings for what the book does not say.
///
/// Needs no packages: an EPUB is a zip, and only two small files in it are
/// read (the container and the package file).
({String title, String author})? epubTitleAndAuthor(Uint8List bytes) {
  try {
    final zip = _ZipFiles(bytes);
    final container = zip.text('META-INF/container.xml');
    if (container == null) return null;
    final rootfile = RegExp(r'<(?:\w+:)?rootfile\b[^>]*>').firstMatch(container);
    final opfPath = rootfile == null ? null : _attribute(rootfile[0]!, 'full-path');
    final opf = opfPath == null ? null : zip.text(opfPath);
    if (opf == null) return null;
    final metadata =
        RegExp(r'<(?:\w+:)?metadata\b[\s\S]*?</(?:\w+:)?metadata>').firstMatch(opf)?[0] ??
            opf;

    var title = '';
    for (final match in RegExp(
      r'<(?:\w+:)?title\b[^>]*>([\s\S]*?)</(?:\w+:)?title>',
    ).allMatches(metadata)) {
      title = _text(match[1]!);
      if (title.isNotEmpty) break;
    }

    // EPUB 3 says who is an author with <meta refines="#id"
    // property="role">aut</meta>; EPUB 2 with opf:role="aut".
    final roles = <String, String>{};
    for (final match in RegExp(
      r'<(?:\w+:)?meta\b([^>]*)>([\s\S]*?)</(?:\w+:)?meta>',
    ).allMatches(metadata)) {
      final refines = _attribute(match[1]!, 'refines');
      if (refines != null && _attribute(match[1]!, 'property') == 'role') {
        roles[refines.replaceFirst('#', '')] = _text(match[2]!);
      }
    }
    final creators = <({String name, String? role})>[];
    for (final match in RegExp(
      r'<(?:\w+:)?creator\b([^>]*)>([\s\S]*?)</(?:\w+:)?creator>',
    ).allMatches(metadata)) {
      final name = _text(match[2]!);
      if (name.isEmpty) continue;
      final attributes = match[1]!;
      creators.add((
        name: name,
        role: _attribute(attributes, 'role') ??
            roles[_attribute(attributes, 'id') ?? ''],
      ));
    }
    final authors = creators.where((other) => other.role == 'aut').toList();
    final names = [
      for (final creator in authors.isNotEmpty
          ? authors
          : creators.where((other) => other.role == null))
        creator.name,
    ];
    return (title: title, author: names.take(3).join(', '));
  } catch (_) {
    return null;
  }
}

/// The value of an attribute in a tag's text, ignoring any prefix on its
/// name (opf:role, xml:lang).
String? _attribute(String tag, String name) {
  final match = RegExp(
    '(?:^|\\s)(?:\\w+:)?$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
  ).firstMatch(tag);
  if (match == null) return null;
  return _decodeEntities(match[1] ?? match[2] ?? '');
}

/// The words in a piece of XML: no tags, entities undone, spaces tidied.
String _text(String xml) {
  final plain = xml
      .replaceAllMapped(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), (m) => m[1]!)
      .replaceAll(RegExp(r'<[^>]*>'), ' ');
  return _decodeEntities(plain).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _decodeEntities(String text) {
  return text.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos);'),
      (match) {
    final entity = match[1]!;
    switch (entity) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = entity.startsWith('#x') || entity.startsWith('#X')
        ? int.tryParse(entity.substring(2), radix: 16)
        : int.tryParse(entity.substring(1));
    return code == null || code <= 0 || code > 0x10FFFF
        ? ' '
        : String.fromCharCode(code);
  });
}

/// A few files read out of a zip, from its central directory. Handles
/// stored and deflated files, which is all an EPUB uses.
class _ZipFiles {
  _ZipFiles(this._bytes) : _data = ByteData.sublistView(_bytes) {
    _readDirectory();
  }

  final Uint8List _bytes;
  final ByteData _data;
  final _entries = <String, ({int method, int size, int offset})>{};

  void _readDirectory() {
    // The end-of-directory record is in the last 64 KB.
    var end = -1;
    final lowest = _bytes.length - 22 - 65535;
    for (var i = _bytes.length - 22; i >= 0 && i >= lowest; i--) {
      if (_data.getUint32(i, Endian.little) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const FormatException('Not a zip file.');
    final count = _data.getUint16(end + 10, Endian.little);
    var at = _data.getUint32(end + 16, Endian.little);
    for (var i = 0; i < count; i++) {
      if (at + 46 > _bytes.length ||
          _data.getUint32(at, Endian.little) != 0x02014b50) {
        break;
      }
      final method = _data.getUint16(at + 10, Endian.little);
      final size = _data.getUint32(at + 20, Endian.little);
      final nameLength = _data.getUint16(at + 28, Endian.little);
      final extraLength = _data.getUint16(at + 30, Endian.little);
      final commentLength = _data.getUint16(at + 32, Endian.little);
      final offset = _data.getUint32(at + 42, Endian.little);
      final name = utf8.decode(
        _bytes.sublist(at + 46, at + 46 + nameLength),
        allowMalformed: true,
      );
      _entries[name] = (method: method, size: size, offset: offset);
      at += 46 + nameLength + extraLength + commentLength;
    }
  }

  /// The text of the file at [path] in the zip, or null when it is not
  /// there or cannot be read.
  String? text(String path) {
    final entry = _entries[path];
    if (entry == null) return null;
    final header = entry.offset;
    if (header + 30 > _bytes.length ||
        _data.getUint32(header, Endian.little) != 0x04034b50) {
      return null;
    }
    final start = header +
        30 +
        _data.getUint16(header + 26, Endian.little) +
        _data.getUint16(header + 28, Endian.little);
    if (start + entry.size > _bytes.length) return null;
    final stored = _bytes.sublist(start, start + entry.size);
    final List<int> content;
    switch (entry.method) {
      case 0:
        content = stored;
      case 8:
        content = ZLibCodec(raw: true).decode(stored);
      default:
        return null;
    }
    return utf8.decode(content, allowMalformed: true);
  }
}
