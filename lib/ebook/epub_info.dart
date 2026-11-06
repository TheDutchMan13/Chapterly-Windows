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

/// The series, ISBN and cover picture written inside an EPUB.
class EpubDetails {
  const EpubDetails({this.series, this.seriesNumber, this.isbn, this.cover});

  final String? series;

  /// The book's number in the series; null when it is not a whole number.
  final int? seriesNumber;

  /// Digits only (and a final X for an ISBN-10).
  final String? isbn;

  /// The cover picture's bytes.
  final Uint8List? cover;

  bool get isEmpty => series == null && isbn == null && cover == null;
}

/// Reads the series (Calibre's or EPUB 3's "belongs-to-collection"), the
/// ISBN and the cover picture of an EPUB. Null when it is not an EPUB.
EpubDetails? epubDetails(Uint8List bytes) {
  try {
    final zip = _ZipFiles(bytes);
    final container = zip.text('META-INF/container.xml');
    if (container == null) return null;
    final rootfile = RegExp(r'<(?:\w+:)?rootfile\b[^>]*>').firstMatch(container);
    final opfPath = rootfile == null ? null : _attribute(rootfile[0]!, 'full-path');
    final opf = opfPath == null ? null : zip.text(opfPath);
    if (opf == null) return null;
    final folder = opfPath!.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    // ---- series
    String? series;
    String? position;
    final metas = RegExp(r'<(?:\w+:)?meta\b([^>]*?)(?:/>|>([\s\S]*?)</(?:\w+:)?meta>)')
        .allMatches(opf)
        .toList();
    for (final meta in metas) {
      final attributes = meta[1]!;
      final name = _attribute(attributes, 'name');
      final content = _attribute(attributes, 'content');
      if (name == 'calibre:series' && (content ?? '').trim().isNotEmpty) {
        series = content!.trim();
      } else if (name == 'calibre:series_index') {
        position = content;
      }
    }
    if (series == null) {
      for (final meta in metas) {
        final attributes = meta[1]!;
        if (_attribute(attributes, 'property') != 'belongs-to-collection') {
          continue;
        }
        final name = _text(meta[2] ?? '');
        if (name.isEmpty) continue;
        final id = _attribute(attributes, 'id');
        var isSeries = true;
        for (final other in metas) {
          final refines = _attribute(other[1]!, 'refines')?.replaceFirst('#', '');
          if (id == null || refines != id) continue;
          final property = _attribute(other[1]!, 'property');
          final value = _text(other[2] ?? '');
          if (property == 'group-position') position = value;
          if (property == 'collection-type' && value != 'series') isSeries = false;
        }
        if (isSeries) {
          series = name;
          break;
        }
        position = null;
      }
    }
    int? number;
    final value = double.tryParse((position ?? '').trim());
    if (value != null && value > 0 && value == value.roundToDouble()) {
      number = value.round();
    }

    // ---- ISBN
    String? isbn;
    for (final match in RegExp(
      r'<(?:\w+:)?identifier\b([^>]*)>([\s\S]*?)</(?:\w+:)?identifier>',
    ).allMatches(opf)) {
      final scheme = (_attribute(match[1]!, 'scheme') ?? '').toLowerCase();
      final text = _text(match[2]!);
      final lower = text.toLowerCase();
      if (scheme != 'isbn' && !lower.contains('isbn') &&
          !RegExp(r'^[\d\s-]{10,17}[\dXx]?$').hasMatch(text)) {
        continue;
      }
      final digits = text.replaceAll(RegExp(r'[^0-9Xx]'), '');
      if (_validIsbn(digits)) {
        isbn = digits.toUpperCase();
        break;
      }
    }

    // ---- cover
    final items = <String, ({String href, String type, String properties})>{};
    for (final match in RegExp(r'<(?:\w+:)?item\b([^>]*)>').allMatches(opf)) {
      final attributes = match[1]!;
      final id = _attribute(attributes, 'id');
      final href = _attribute(attributes, 'href');
      if (id == null || href == null) continue;
      items[id] = (
        href: href,
        type: _attribute(attributes, 'media-type') ?? '',
        properties: _attribute(attributes, 'properties') ?? '',
      );
    }
    String? coverHref;
    for (final item in items.values) {
      if (item.properties.split(' ').contains('cover-image')) {
        coverHref = item.href;
        break;
      }
    }
    if (coverHref == null) {
      for (final meta in metas) {
        if (_attribute(meta[1]!, 'name') == 'cover') {
          final id = _attribute(meta[1]!, 'content');
          final item = id == null ? null : items[id];
          if (item != null && item.type.startsWith('image/')) {
            coverHref = item.href;
          }
        }
      }
    }
    if (coverHref == null) {
      for (final entry in items.entries) {
        if (entry.value.type.startsWith('image/') &&
            '${entry.key} ${entry.value.href}'.toLowerCase().contains('cover')) {
          coverHref = entry.value.href;
          break;
        }
      }
    }
    Uint8List? cover;
    if (coverHref != null) {
      cover = zip.bytes(_resolve(folder, coverHref));
    }
    return EpubDetails(
      series: series,
      seriesNumber: series == null ? null : number,
      isbn: isbn,
      cover: cover,
    );
  } catch (_) {
    return null;
  }
}

/// [href] (relative to the package file's [folder]) as a path in the zip.
String _resolve(String folder, String href) {
  var path = href.split('#').first;
  try {
    path = Uri.decodeComponent(path);
  } catch (_) {
    // Keep it as it is.
  }
  final parts = <String>[];
  for (final part in (path.startsWith('/') ? path.substring(1) : '$folder$path')
      .split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// Whether [digits] is an ISBN-10 or ISBN-13 with a right check digit.
bool _validIsbn(String digits) {
  final d = digits.toUpperCase();
  if (RegExp(r'^\d{13}$').hasMatch(d)) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(d[i]) * (i.isEven ? 1 : 3);
    }
    return (10 - sum % 10) % 10 == int.parse(d[12]);
  }
  if (RegExp(r'^\d{9}[\dX]$').hasMatch(d)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final v = d[i] == 'X' ? 10 : int.parse(d[i]);
      sum += v * (10 - i);
    }
    return sum % 11 == 0;
  }
  return false;
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

  /// The bytes of the file at [path] in the zip, or null when it is not
  /// there or cannot be read.
  Uint8List? bytes(String path) {
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
    switch (entry.method) {
      case 0:
        return stored;
      case 8:
        return _inflate(stored);
      default:
        return null;
    }
  }

  /// The text of the file at [path] in the zip, or null when it is not
  /// there or cannot be read.
  String? text(String path) {
    final content = bytes(path);
    return content == null ? null : utf8.decode(content, allowMalformed: true);
  }
}

/// The most one file inside an EPUB may unpack to. A real cover or package
/// file is far smaller; a damaged or hostile EPUB could otherwise unpack to
/// gigabytes and crash the app.
const maxUnpackedBytes = 64 * 1024 * 1024;

class _TooBig implements Exception {
  const _TooBig();
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.limit);

  final int limit;
  final _out = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (_out.length + chunk.length > limit) throw const _TooBig();
    _out.add(chunk);
  }

  @override
  void close() {}

  Uint8List take() => _out.takeBytes();
}

/// Unpacks a deflated zip entry, or null when it is damaged or would be
/// bigger than [limit].
Uint8List? _inflate(Uint8List stored, {int limit = maxUnpackedBytes}) {
  final sink = _CappedSink(limit);
  try {
    final input = ZLibDecoder(raw: true).startChunkedConversion(sink);
    // Small pieces, so no single step can unpack to much more than the limit.
    const piece = 16 * 1024;
    for (var start = 0; start < stored.length; start += piece) {
      final end = start + piece < stored.length ? start + piece : stored.length;
      input.add(Uint8List.sublistView(stored, start, end));
    }
    input.close();
    return sink.take();
  } catch (_) {
    // Too big, or not valid deflate data.
    return null;
  }
}

/// For tests: [_inflate] with a small limit.
Uint8List? inflateForTest(Uint8List stored, int limit) =>
    _inflate(stored, limit: limit);
