import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chapterly/audio/audio_probe.dart';
import 'package:chapterly/audio/audio_tags.dart';
import 'package:chapterly/data/file_match.dart';
import 'package:chapterly/ebook/epub_info.dart';
import 'package:chapterly/ebook/pdf_info.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// A zip with the files stored as they are, or deflated as real EPUBs
/// mostly are.
Uint8List _zip(Map<String, List<int>> files, {bool deflate = false}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) => b.add([
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final original = entry.value;
    final data = deflate ? ZLibCodec(raw: true).encode(original) : original;
    final method = deflate ? 8 : 0;
    final crc = _crc32(original);
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0);
    u16(out, method);
    u16(out, 0);
    u16(out, 0x21);
    u32(out, crc);
    u32(out, data.length);
    u32(out, original.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(data);

    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, method);
    u16(central, 0);
    u16(central, 0x21);
    u32(central, crc);
    u32(central, data.length);
    u32(central, original.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name);
  }
  final centralOffset = out.length;
  final centralBytes = central.toBytes();
  out.add(centralBytes);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, files.length);
  u16(out, files.length);
  u32(out, centralBytes.length);
  u32(out, centralOffset);
  u16(out, 0);
  return out.toBytes();
}

List<int> _text(String s) => utf8.encode(s);

Uint8List _epub(String metadata, {bool deflate = false}) => _zip({
      'mimetype': _text('application/epub+zip'),
      'META-INF/container.xml': _text('<?xml version="1.0"?>'
          '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" '
          'media-type="application/oebps-package+xml"/></rootfiles>'
          '</container>'),
      'OEBPS/content.opf': _text('<?xml version="1.0"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:opf="http://www.idpf.org/2007/opf" version="3.0">'
          '<metadata>$metadata</metadata>'
          '<manifest><item id="c1" href="c1.xhtml" '
          'media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="c1"/></spine></package>'),
      'OEBPS/c1.xhtml': _text('<html><body><p>Hi</p></body></html>'),
    }, deflate: deflate);

List<int> _u32(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

List<int> _box(String type, List<int> content) =>
    [..._u32(content.length + 8), ...latin1.encode(type), ...content];

List<int> _ilstItem(String type, String value) => _box(type, _box('data', [
      0, 0, 0, 1, // UTF-8 text
      0, 0, 0, 0, // locale
      ...utf8.encode(value),
    ]));

List<int> _syncSafe(int v) =>
    [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];

/// An ID3v2 frame with UTF-8 (v2.4) or Latin-1 (v2.3) text.
List<int> _frame(int version, String id, String text) {
  final body = version == 4
      ? [3, ...utf8.encode(text)]
      : [0, ...latin1.encode(text)];
  return [
    ...ascii.encode(id),
    ...(version == 4 ? _syncSafe(body.length) : _u32(body.length)),
    0, 0, // flags
    ...body,
  ];
}

Uint8List _mp3(int version, List<List<int>> frames) {
  final tag = [for (final f in frames) ...f, ...List.filled(20, 0)];
  return Uint8List.fromList([
    ...ascii.encode('ID3'), version, 0, 0, ..._syncSafe(tag.length),
    ...tag,
    ...List.filled(200, 0xFF), // audio
  ]);
}

Book _book(String id, String title, String author) => Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
    );

void main() {
  group('file names', () {
    test('are cleaned of folders, extensions, underscores and brackets', () {
      expect(cleanFileName(r'C:\Books\Dune_(1965) [epub].epub'), 'Dune');
      expect(cleanFileName('Project Hail Mary.m4b'), 'Project Hail Mary');
      expect(cleanFileName('Vol. 2'), 'Vol. 2');
    });

    test('split into parts at dashes or "by"', () {
      expect(fileNameParts('Dune - Frank Herbert.epub'),
          ['Dune', 'Frank Herbert']);
      expect(fileNameParts('Brandon Sanderson - Mistborn 01 - The Final Empire'),
          ['Brandon Sanderson', 'Mistborn 01', 'The Final Empire']);
      expect(fileNameParts('Dune by Frank Herbert.pdf'),
          ['Dune', 'Frank Herbert']);
      expect(fileNameParts('Spider-Man.epub'), ['Spider-Man']);
    });

    test('give a first guess at a new book', () {
      final two = guessFromFileName('Dune - Frank Herbert.epub');
      expect((two.title, two.author), ('Dune', 'Frank Herbert'));
      final three =
          guessFromFileName('Brandon Sanderson - Mistborn 01 - The Final Empire');
      expect((three.title, three.author),
          ('The Final Empire', 'Brandon Sanderson'));
      final one = guessFromFileName('Emma.epub');
      expect((one.title, one.author), ('Emma', ''));
    });
  });

  group('matching', () {
    final books = [
      _book('dune', 'Dune', 'Frank Herbert'),
      _book('messiah', 'Dune Messiah', 'Frank Herbert'),
      _book('empire', 'The Final Empire', 'Brandon Sanderson'),
      _book('hail', 'Project Hail Mary', 'Andy Weir'),
      _book('it', 'It', 'Stephen King'),
    ];

    test('scores titles, ignoring case, punctuation and a leading "the"', () {
      expect(titleScore('The Final Empire', 'final empire'), 100);
      expect(titleScore('Dune: Book One', 'Dune'), 85);
      expect(titleScore('The Final Empire', 'Mistborn 01 The Final Empire'), 65);
      expect(titleScore('Dune', 'Emma'), 0);
      expect(titleScore('It', 'Itinerary'), 0);
    });

    test('finds the book from the title and author in the file', () {
      final matches =
          findMatchingBooks(books, title: 'Dune', author: 'Frank Herbert');
      expect(matches.first.book.id, 'dune');
      expect(isSureMatch(matches), isTrue);
    });

    test('finds the book from a file name either way round', () {
      for (final name in [
        'Andy Weir - Project Hail Mary.m4b',
        'Project Hail Mary - Andy Weir.m4b',
      ]) {
        final matches = findMatchingBooks(books, nameParts: fileNameParts(name));
        expect(matches.first.book.id, 'hail', reason: name);
        expect(isSureMatch(matches), isTrue, reason: name);
      }
      final series = findMatchingBooks(
        books,
        nameParts: fileNameParts(
            'Brandon Sanderson - Mistborn 01 - The Final Empire.epub'),
      );
      expect(series.first.book.id, 'empire');
    });

    test('an author that does not fit makes it unsure', () {
      final matches =
          findMatchingBooks(books, title: 'Dune', author: 'Somebody Else');
      expect(matches.first.book.id, 'dune');
      expect(isSureMatch(matches), isFalse);
    });

    test('two close books are not a sure match', () {
      final matches = findMatchingBooks([
        _book('a', 'Emma', ''),
        _book('b', 'Emma', ''),
      ], title: 'Emma');
      expect(matches.length, 2);
      expect(isSureMatch(matches), isFalse);
    });

    test('nothing matches an unknown book, and the trash is left out', () {
      expect(findMatchingBooks(books, title: 'Middlemarch'), isEmpty);
      final trashed = _book('t', 'Middlemarch', 'George Eliot')
          .copyWith(deletedAt: () => DateTime(2026));
      expect(findMatchingBooks([trashed], title: 'Middlemarch'), isEmpty);
    });
  });

  group('EPUB title and author', () {
    test('reads the title and the authors, not the narrator', () {
      final info = epubTitleAndAuthor(_epub(
        '<dc:title>Emma</dc:title>'
        '<dc:creator id="a1">Jane Austen</dc:creator>'
        '<meta refines="#a1" property="role">aut</meta>'
        '<dc:creator id="n1">A Reader</dc:creator>'
        '<meta refines="#n1" property="role">nrr</meta>',
      ));
      expect(info?.title, 'Emma');
      expect(info?.author, 'Jane Austen');
    });

    test('reads EPUB 2 roles and joins several authors', () {
      final info = epubTitleAndAuthor(_epub(
        '<dc:title>Good Omens</dc:title>'
        '<dc:creator opf:role="aut">Terry Pratchett</dc:creator>'
        '<dc:creator opf:role="aut">Neil Gaiman</dc:creator>',
      ));
      expect(info?.author, 'Terry Pratchett, Neil Gaiman');
    });

    test('creators without roles count as authors', () {
      final info = epubTitleAndAuthor(
          _epub('<dc:title> Dune </dc:title><dc:creator>Frank Herbert</dc:creator>'));
      expect((info?.title, info?.author), ('Dune', 'Frank Herbert'));
    });

    test('reads a compressed EPUB, with entities and CDATA', () {
      final info = epubTitleAndAuthor(_epub(
        '<dc:title><![CDATA[Pride & Prejudice]]></dc:title>'
        '<dc:creator opf:role="aut">Jane Austen &amp; Friends</dc:creator>',
        deflate: true,
      ));
      expect(info?.title, 'Pride & Prejudice');
      expect(info?.author, 'Jane Austen & Friends');
    });

    test('is null for a file that is not an EPUB', () {
      expect(epubTitleAndAuthor(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('PDF title and author', () {
    Uint8List pdf(String body) => Uint8List.fromList(latin1.encode(body));

    test('come from the object the trailer names, not a bookmark', () {
      final info = pdfTitleAndAuthor(pdf('%PDF-1.4\n'
          '5 0 obj << /Title (Chapter 1) /Parent 4 0 R >> endobj\n'
          '7 0 obj << /Title (Emma \\(a novel\\)) /Author (Jane Austen) >> endobj\n'
          'trailer << /Root 1 0 R /Info 7 0 R >>\n%%EOF'));
      expect(info.title, 'Emma (a novel)');
      expect(info.author, 'Jane Austen');
    });

    test('read UTF-16 hex strings and octal escapes', () {
      final info = pdfTitleAndAuthor(pdf('%PDF-1.7\n'
          '12 0 obj\n<< /Title <FEFF004400FC006E0065> /Author (Caf\\351) >>\nendobj\n'
          'trailer << /Info 12 0 R >>'));
      expect(info.title, 'Düne');
      expect(info.author, 'Café');
    });

    test('are empty when the information is not there', () {
      final info = pdfTitleAndAuthor(pdf('%PDF-1.5\nno trailer here'));
      expect((info.title, info.author), ('', ''));
    });
  });

  group('audio tags', () {
    test('come from an M4B', () async {
      final bytes = Uint8List.fromList([
        ..._box('ftyp', [...ascii.encode('M4B '), ..._u32(0)]),
        ..._box('moov', _box('udta', _box('meta', [
          0, 0, 0, 0, // version and flags
          ..._box('hdlr', List.filled(25, 0)),
          ..._box('ilst', [
            ..._ilstItem('\u00A9nam', 'Project Hail Mary'),
            ..._ilstItem('\u00A9ART', 'Andy Weir'),
            ..._ilstItem('\u00A9wrt', 'Ray Porter'),
          ]),
        ]))),
      ]);
      final tags = await readAudioTags(MemoryByteSource(bytes));
      expect(tags.bookTitle, 'Project Hail Mary');
      expect(tags.author, 'Andy Weir');
    });

    test('come from ID3v2.3 and v2.4, the album being the book', () async {
      for (final version in [3, 4]) {
        final tags = await readAudioTags(MemoryByteSource(_mp3(version, [
          _frame(version, 'TIT2', 'Chapter 1'),
          _frame(version, 'TALB', 'The Hobbit'),
          _frame(version, 'TPE2', 'J. R. R. Tolkien'),
        ])));
        expect(tags.title, 'Chapter 1', reason: 'v2.$version');
        expect(tags.bookTitle, 'The Hobbit', reason: 'v2.$version');
        expect(tags.author, 'J. R. R. Tolkien', reason: 'v2.$version');
      }
    });

    test('come from ID3v1 when there is no ID3v2', () async {
      List<int> field(String text) =>
          [...latin1.encode(text), ...List.filled(30 - text.length, 0)];
      final bytes = Uint8List.fromList([
        ...List.filled(300, 0xFF),
        ...ascii.encode('TAG'),
        ...field('Chapter 3'),
        ...field('Andy Weir'),
        ...field('The Martian'),
        ...List.filled(128 - 93, 0),
      ]);
      final tags = await readAudioTags(MemoryByteSource(bytes));
      expect((tags.bookTitle, tags.author), ('The Martian', 'Andy Weir'));
    });

    test('are empty for anything else', () async {
      final tags = await readAudioTags(
          MemoryByteSource(Uint8List.fromList(List.filled(64, 7))));
      expect(tags.isEmpty, isTrue);
    });
  });
}
