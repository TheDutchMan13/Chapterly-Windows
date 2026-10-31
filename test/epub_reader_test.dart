import 'dart:convert';
import 'dart:typed_data';

import 'package:chapterly/ebook/epub_book.dart';
import 'package:chapterly/screens/reader_screen.dart';
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

/// A zip with the files stored as they are (no compression).
Uint8List _zip(Map<String, List<int>> files) {
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
    final data = entry.value;
    final crc = _crc32(data);
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0x21);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(data);

    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0x21);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
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

Uint8List _sampleEpub() => _zip({
      'mimetype': _text('application/epub+zip'),
      'META-INF/container.xml': _text('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
      'OEBPS/content.opf': _text('''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Emma</dc:title>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="pic" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>'''),
      'OEBPS/nav.xhtml': _text('''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="text/ch1.xhtml">Chapter I</a>
        <ol><li><a href="text/ch2.xhtml#s">Chapter II</a></li></ol>
      </li>
    </ol>
  </nav>
</body>
</html>'''),
      'OEBPS/text/ch1.xhtml': _text('''<html><head><style>p { color: red }</style></head>
<body class="x"><p>Emma Woodhouse, handsome &amp; clever.</p>
<img src="../images/pic.png"/><a href="ch2.xhtml#s">On</a></body></html>'''),
      'OEBPS/text/ch2.xhtml': _text('''<html><body><p>Miss Taylor married Mr. Weston.</p>
<script>alert(1)</script></body></html>'''),
      'OEBPS/images/pic.png': [1, 2, 3, 4],
    });

void main() {
  test('an EPUB opens with its chapters, contents and pictures', () {
    final book = EpubBook.open(_sampleEpub());
    expect(book.title, 'Emma');
    expect(book.chapters, ['OEBPS/text/ch1.xhtml', 'OEBPS/text/ch2.xhtml']);
    expect([for (final e in book.toc) e.title], ['Chapter I', 'Chapter II']);
    expect([for (final e in book.toc) e.chapter], [0, 1]);
    expect([for (final e in book.toc) e.depth], [0, 1]);

    final first = book.chapterHtml(0);
    expect(first, contains('Emma Woodhouse'));
    expect(first, isNot(contains('<style')));
    expect(book.chapterHtml(1), isNot(contains('alert')));
    expect(book.chapterText(0), contains('handsome & clever.'));

    expect(book.resource(0, '../images/pic.png'), [1, 2, 3, 4]);
    expect(book.linkTarget(0, 'ch2.xhtml#s'), 1);
    expect(book.linkTarget(0, 'https://example.org'), isNull);
    expect(book.chapterTitle(1), 'Chapter II');
  });

  test('search finds the words in any case', () {
    final book = EpubBook.open(_sampleEpub());
    final hits = book.search('TAYLOR');
    expect(hits.single.chapter, 1);
    expect(hits.single.excerpt, contains('Miss Taylor'));
    expect(book.search('   '), isEmpty);
  });

  test('a file that is not an EPUB says so', () {
    expect(
      () => EpubBook.open(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<FormatException>()),
    );
  });

  test('a place in the book is written and read back', () {
    const spot = EpubSpot(3, 0.25);
    expect(spot.locator, 'c:3:0.2500');
    final back = EpubSpot.parse('c:3:0.2500:1793430000000');
    expect(back?.chapter, 3);
    expect(back?.fraction, 0.25);
    expect(EpubSpot.parse('epubcfi(/6/8)'), isNull);
  });

  test('progress counts each chapter by its length', () {
    const lengths = [100, 300];
    expect(bookProgress(lengths, const EpubSpot(0, 0.5)), 0.125);
    expect(bookProgress(lengths, const EpubSpot(1, 0.5)), 0.625);
    final spot = spotForProgress(lengths, 0.625);
    expect(spot.chapter, 1);
    expect(spot.fraction, closeTo(0.5, 0.0001));
    expect(spotForProgress(lengths, 0).chapter, 0);
    expect(spotForProgress(lengths, 1).chapter, 1);
  });

  test('highlighted passages are marked in the page', () {
    const html = '<p>Emma Woodhouse, handsome &amp; clever.</p>';
    expect(
      markHighlights(html, ['handsome & clever']),
      '<p>Emma Woodhouse, <mark>handsome &amp; clever</mark>.</p>',
    );
    // A passage split by formatting is left alone.
    expect(markHighlights(html, ['not here']), html);
  });
}
