import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// One line of the table of contents.
class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.chapter,
    required this.depth,
  });

  final String title;

  /// Which file of the book (in reading order) it opens.
  final int chapter;

  /// 0 for a top-level entry, 1 under it, and so on.
  final int depth;
}

/// A place where the words you searched for are.
class EpubSearchHit {
  const EpubSearchHit({
    required this.chapter,
    required this.fraction,
    required this.excerpt,
  });

  final int chapter;

  /// How far into the chapter, from 0 to 1.
  final double fraction;
  final String excerpt;
}

final _body = RegExp(r'<body[^>]*>([\s\S]*)</body>', caseSensitive: false);
final _scripts = RegExp(
  r'<(script|style)[^>]*>[\s\S]*?</\1>',
  caseSensitive: false,
);
final _svgImage = RegExp(
  r'<svg[^>]*>[\s\S]*?<image[^>]*?(?:xlink:)?href="([^"]+)"[^>]*>[\s\S]*?</svg>',
  caseSensitive: false,
);
final _tags = RegExp(r'<[^>]+>');
final _spaces = RegExp(r'\s+');
final _numericEntity = RegExp(r'&#(x?[0-9a-fA-F]+);');

const _namedEntities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&nbsp;': ' ',
  '&rsquo;': '’',
  '&lsquo;': '‘',
  '&rdquo;': '”',
  '&ldquo;': '“',
  '&mdash;': '—',
  '&ndash;': '–',
  '&hellip;': '…',
};

/// The words of a piece of HTML, without tags, with spaces tidied.
String htmlToText(String html) {
  var text = html.replaceAll(_scripts, ' ').replaceAll(_tags, ' ');
  text = text.replaceAllMapped(_numericEntity, (m) {
    final code = m[1]!;
    final value = code.startsWith('x') || code.startsWith('X')
        ? int.tryParse(code.substring(1), radix: 16)
        : int.tryParse(code);
    return value == null ? ' ' : String.fromCharCode(value);
  });
  for (final entry in _namedEntities.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text.replaceAll(_spaces, ' ').trim();
}

Iterable<XmlElement> _elements(XmlNode node, String local) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String? _attr(XmlElement element, String local) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == local) return attribute.value;
  }
  return null;
}

Uint8List _bytesOf(ArchiveFile file) {
  final Object? data = file.readBytes();
  return data is Uint8List ? data : Uint8List(0);
}

String _decodeHref(String href) {
  try {
    return Uri.decodeComponent(href);
  } catch (_) {
    return href;
  }
}

/// The title and authors written inside an EPUB, read without opening the
/// whole book. Several authors are joined with ", ". Null when the file is
/// not an EPUB; empty strings for what the book does not say.
({String title, String author})? epubTitleAndAuthor(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? find(String path) {
      for (final file in archive.files) {
        if (file.isFile && file.name == path) return file;
      }
      return null;
    }

    XmlDocument? parse(String path) {
      final file = find(path);
      if (file == null) return null;
      return XmlDocument.parse(utf8.decode(_bytesOf(file), allowMalformed: true));
    }

    final container = parse('META-INF/container.xml');
    if (container == null) return null;
    final rootfile = _elements(container, 'rootfile').firstOrNull;
    final opfPath = rootfile == null ? null : _attr(rootfile, 'full-path');
    final opf = opfPath == null ? null : parse(opfPath);
    if (opf == null) return null;
    final XmlNode metadata = _elements(opf, 'metadata').firstOrNull ?? opf;
    String clean(String text) => text.replaceAll(_spaces, ' ').trim();

    var title = '';
    for (final element in _elements(metadata, 'title')) {
      title = clean(element.innerText);
      if (title.isNotEmpty) break;
    }

    // EPUB 3 says who is an author with <meta refines="#id"
    // property="role">aut</meta>; EPUB 2 with opf:role="aut".
    final roles = <String, String>{};
    for (final meta in _elements(metadata, 'meta')) {
      final refines = _attr(meta, 'refines');
      if (_attr(meta, 'property') == 'role' && refines != null) {
        roles[refines.replaceFirst('#', '')] = clean(meta.innerText);
      }
    }
    final creators = <({String name, String? role})>[
      for (final creator in _elements(metadata, 'creator'))
        if (clean(creator.innerText) case final name when name.isNotEmpty)
          (
            name: name,
            role: _attr(creator, 'role') ?? roles[_attr(creator, 'id') ?? ''],
          ),
    ];
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

/// An EPUB book opened from its file: its chapters in reading order, the
/// table of contents and the pictures. An EPUB is a zip of web pages.
class EpubBook {
  EpubBook._(this._files, this.title, this.chapters, this.toc);

  final Map<String, ArchiveFile> _files;
  final String title;

  /// The paths of the chapter files inside the book, in reading order.
  final List<String> chapters;
  final List<EpubTocEntry> toc;

  final _text = <int, String>{};

  /// Opens a book from the bytes of its .epub file. Throws a
  /// [FormatException] when it is not an EPUB.
  static EpubBook open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('This is not an EPUB file.');
    }
    final files = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) file.name: file,
    };
    String read(String path) {
      final file = files[path];
      if (file == null) throw FormatException('Missing $path');
      return utf8.decode(_bytesOf(file), allowMalformed: true);
    }

    final container = XmlDocument.parse(read('META-INF/container.xml'));
    final rootfile = _elements(container, 'rootfile').firstOrNull;
    final opfPath = rootfile == null ? null : _attr(rootfile, 'full-path');
    if (opfPath == null) {
      throw const FormatException('The book has no contents list.');
    }
    final opfDir = p.posix.dirname(opfPath);
    String resolve(String dir, String href) =>
        p.posix.normalize(p.posix.join(dir == '.' ? '' : dir, href));

    final opf = XmlDocument.parse(read(opfPath));
    final manifest = <String, ({String path, String type, String props})>{};
    for (final item in _elements(opf, 'item')) {
      final id = _attr(item, 'id');
      final href = _attr(item, 'href');
      if (id == null || href == null) continue;
      manifest[id] = (
        path: resolve(opfDir, _decodeHref(href)),
        type: _attr(item, 'media-type') ?? '',
        props: _attr(item, 'properties') ?? '',
      );
    }
    final spineElement = _elements(opf, 'spine').firstOrNull;
    final chapters = <String>[
      for (final ref in _elements(opf, 'itemref'))
        if (manifest[_attr(ref, 'idref')]?.path case final path?)
          if (files.containsKey(path)) path,
    ];
    if (chapters.isEmpty) {
      throw const FormatException('The book has no chapters.');
    }
    final titleElement = _elements(opf, 'title').firstOrNull;
    final title = titleElement?.innerText.trim() ?? '';

    final index = <String, int>{
      for (var i = 0; i < chapters.length; i++) chapters[i]: i,
    };
    int? chapterOf(String dir, String href) {
      final path = resolve(dir, _decodeHref(href.split('#').first));
      return index[path];
    }

    final toc = <EpubTocEntry>[];
    // EPUB 3: a page with a <nav> table of contents.
    final nav = manifest.values
        .where((item) => item.props.split(' ').contains('nav'))
        .firstOrNull;
    if (nav != null && files.containsKey(nav.path)) {
      try {
        final doc = XmlDocument.parse(read(nav.path));
        final navs = _elements(doc, 'nav').toList();
        final tocNav = navs
                .where((n) => (_attr(n, 'type') ?? '').contains('toc'))
                .firstOrNull ??
            navs.firstOrNull;
        final dir = p.posix.dirname(nav.path);
        void walk(XmlElement list, int depth) {
          for (final li in list.childElements.where(
            (e) => e.name.local == 'li',
          )) {
            final a = li.childElements
                .where((e) => e.name.local == 'a' || e.name.local == 'span')
                .firstOrNull;
            final href = a == null ? null : _attr(a, 'href');
            final chapter = href == null ? null : chapterOf(dir, href);
            final label = a?.innerText.replaceAll(_spaces, ' ').trim() ?? '';
            if (chapter != null && label.isNotEmpty) {
              toc.add(EpubTocEntry(
                title: label,
                chapter: chapter,
                depth: depth,
              ));
            }
            for (final sub in li.childElements.where(
              (e) => e.name.local == 'ol',
            )) {
              walk(sub, depth + 1);
            }
          }
        }

        final top = tocNav == null
            ? null
            : _elements(tocNav, 'ol').firstOrNull;
        if (top != null) walk(top, 0);
      } catch (_) {
        toc.clear();
      }
    }
    // EPUB 2: the .ncx file named by the spine.
    if (toc.isEmpty) {
      final ncxId = spineElement == null ? null : _attr(spineElement, 'toc');
      final ncx = manifest[ncxId] ??
          manifest.values
              .where((item) => item.type == 'application/x-dtbncx+xml')
              .firstOrNull;
      if (ncx != null && files.containsKey(ncx.path)) {
        try {
          final doc = XmlDocument.parse(read(ncx.path));
          final dir = p.posix.dirname(ncx.path);
          void walk(XmlElement parent, int depth) {
            for (final point in parent.childElements.where(
              (e) => e.name.local == 'navPoint',
            )) {
              final label = _elements(point, 'text')
                  .firstOrNull
                  ?.innerText
                  .replaceAll(_spaces, ' ')
                  .trim();
              final content = point.childElements
                  .where((e) => e.name.local == 'content')
                  .firstOrNull;
              final src = content == null ? null : _attr(content, 'src');
              final chapter = src == null ? null : chapterOf(dir, src);
              if (chapter != null && label != null && label.isNotEmpty) {
                toc.add(EpubTocEntry(
                  title: label,
                  chapter: chapter,
                  depth: depth,
                ));
              }
              walk(point, depth + 1);
            }
          }

          final navMap = _elements(doc, 'navMap').firstOrNull;
          if (navMap != null) walk(navMap, 0);
        } catch (_) {
          toc.clear();
        }
      }
    }
    return EpubBook._(files, title, chapters, toc);
  }

  /// The chapter's page, ready to show: the inside of its `<body>`, without
  /// scripts or the book's own style sheets, and with pictures drawn in SVG
  /// (often the cover) turned into plain pictures.
  String chapterHtml(int chapter) {
    final file = _files[chapters[chapter]];
    if (file == null) return '';
    final source = utf8.decode(_bytesOf(file), allowMalformed: true);
    final body = _body.firstMatch(source)?.group(1) ?? source;
    return body
        .replaceAll(_scripts, '')
        .replaceAllMapped(_svgImage, (m) => '<img src="${m[1]}" />');
  }

  /// The chapter's words, for searching and for working out how far
  /// through the book you are.
  String chapterText(int chapter) =>
      _text[chapter] ??= htmlToText(chapterHtml(chapter));

  /// The bytes of a picture (or any file) a chapter refers to by [src].
  Uint8List? resource(int chapter, String src) {
    final dir = p.posix.dirname(chapters[chapter]);
    final path = p.posix.normalize(
      p.posix.join(dir == '.' ? '' : dir, _decodeHref(src.split('#').first)),
    );
    final file = _files[path];
    return file == null ? null : _bytesOf(file);
  }

  /// The chapter a link inside [chapter] goes to, or null for a link out
  /// of the book.
  int? linkTarget(int chapter, String href) {
    if (href.contains('://') || href.startsWith('mailto:')) return null;
    final target = href.split('#').first;
    if (target.isEmpty) return chapter;
    final dir = p.posix.dirname(chapters[chapter]);
    final path = p.posix.normalize(
      p.posix.join(dir == '.' ? '' : dir, _decodeHref(target)),
    );
    final i = chapters.indexOf(path);
    return i < 0 ? null : i;
  }

  final _compact = <int, String>{};

  /// The chapter's words with every space taken out: the measure that
  /// highlights are kept in on Windows, so they survive formatting and line
  /// breaks.
  String chapterCompactText(int chapter) =>
      _compact[chapter] ??= compactTextOf(chapterHtml(chapter));

  /// The words of the footnote a link in [chapter] points to: the element
  /// with the link's #id, in this chapter or another file of the book.
  /// Null when it cannot be found.
  String? noteText(int chapter, String href) {
    final hash = href.indexOf('#');
    if (hash < 0) return null;
    final id = _decodeHref(href.substring(hash + 1));
    final target = linkTarget(chapter, href);
    if (target == null || id.isEmpty) return null;
    final root = html_parser.parseFragment(chapterHtml(target));
    final element = _byId(root, id);
    if (element == null) return null;
    // A note's id is often on its number; the note is the whole aside,
    // list item or paragraph around it.
    var note = element;
    const blocks = {'aside', 'li', 'p', 'div', 'section', 'dd', 'td'};
    while (!blocks.contains(note.localName) && note.parent != null) {
      note = note.parent!;
    }
    final text = note.text.replaceAll(_spaces, ' ').trim();
    return text.isEmpty ? null : text;
  }

  /// The title of the contents entry for [chapter], or the one before it.
  String? chapterTitle(int chapter) {
    String? title;
    for (final entry in toc) {
      if (entry.chapter > chapter) break;
      title = entry.title;
    }
    return title;
  }

  /// Every place with [query] (any case), up to [limit] of them.
  List<EpubSearchHit> search(String query, {int limit = 200}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final hits = <EpubSearchHit>[];
    for (var c = 0; c < chapters.length && hits.length < limit; c++) {
      final text = chapterText(c);
      final lower = text.toLowerCase();
      var at = lower.indexOf(needle);
      while (at >= 0 && hits.length < limit) {
        final start = at - 60 < 0 ? 0 : at - 60;
        final end = at + needle.length + 60 > text.length
            ? text.length
            : at + needle.length + 60;
        hits.add(EpubSearchHit(
          chapter: c,
          fraction: text.isEmpty ? 0 : at / text.length,
          excerpt: '${start > 0 ? '...' : ''}${text.substring(start, end)}'
              '${end < text.length ? '...' : ''}',
        ));
        at = lower.indexOf(needle, at + needle.length);
      }
    }
    return hits;
  }
}

/// Where you are in an EPUB on Windows: the chapter and how far down it.
/// Written as "c:3:0.4521". Anything after a third ":" (a highlight's
/// time, to tell two highlights apart) is ignored.
class EpubSpot {
  const EpubSpot(this.chapter, this.fraction);

  final int chapter;
  final double fraction;

  String get locator => 'c:$chapter:${fraction.toStringAsFixed(4)}';

  static EpubSpot? parse(String? locator) {
    if (locator == null) return null;
    final parts = locator.split(':');
    if (parts.length < 3 || parts[0] != 'c') return null;
    final chapter = int.tryParse(parts[1]);
    final fraction = double.tryParse(parts[2]);
    if (chapter == null || chapter < 0 || fraction == null) return null;
    return EpubSpot(chapter, fraction.clamp(0.0, 1.0));
  }
}

/// How far through the whole book a spot is, from 0 to 1, counting each
/// chapter by its number of characters.
double bookProgress(List<int> chapterLengths, EpubSpot spot) {
  final total = chapterLengths.fold<int>(0, (sum, n) => sum + n);
  if (total <= 0 || chapterLengths.isEmpty) return 0;
  final chapter = spot.chapter.clamp(0, chapterLengths.length - 1);
  var before = 0;
  for (var i = 0; i < chapter; i++) {
    before += chapterLengths[i];
  }
  final value = (before + spot.fraction * chapterLengths[chapter]) / total;
  return value.clamp(0.0, 1.0);
}

/// The spot for a place in the whole book (from the position slider).
EpubSpot spotForProgress(List<int> chapterLengths, double progress) {
  final total = chapterLengths.fold<int>(0, (sum, n) => sum + n);
  if (total <= 0 || chapterLengths.isEmpty) return const EpubSpot(0, 0);
  final target = progress.clamp(0.0, 1.0) * total;
  var before = 0;
  for (var i = 0; i < chapterLengths.length; i++) {
    final length = chapterLengths[i];
    if (target <= before + length || i == chapterLengths.length - 1) {
      final fraction = length <= 0 ? 0.0 : (target - before) / length;
      return EpubSpot(i, fraction.clamp(0.0, 1.0));
    }
    before += length;
  }
  return EpubSpot(chapterLengths.length - 1, 1);
}

final _anySpace = RegExp(r'\s+');

dom.Element? _byId(dom.Node node, String id) {
  for (final child in node.nodes) {
    if (child is! dom.Element) continue;
    if (child.attributes['id'] == id) return child;
    final found = _byId(child, id);
    if (found != null) return found;
  }
  return null;
}

void _textNodes(dom.Node node, void Function(dom.Text text) visit) {
  for (final child in node.nodes.toList()) {
    if (child is dom.Text) {
      visit(child);
    } else if (child is dom.Element) {
      _textNodes(child, visit);
    }
  }
}

/// The words of a chapter's HTML with every space taken out, as the page
/// shows them (entities read, tags gone).
String compactTextOf(String html) {
  final buffer = StringBuffer();
  _textNodes(
    html_parser.parseFragment(html),
    (text) => buffer.write(text.data.replaceAll(_anySpace, '')),
  );
  return buffer.toString();
}

/// Where a selected passage is in a chapter's compact text (see
/// [compactTextOf]): the place nearest [near] (0 to 1, how far down the
/// chapter you are) when it is there more than once. Null when it is not
/// there, for example when the selection ran across a list's numbers.
({int start, int end})? findPassage(
  String compact,
  String selected, {
  double near = 0,
}) {
  final needle = selected.replaceAll(_anySpace, '');
  if (needle.length < 2 || compact.isEmpty) return null;
  final target = near.clamp(0.0, 1.0) * compact.length;
  int? best;
  var at = compact.indexOf(needle);
  while (at >= 0) {
    if (best == null || (at - target).abs() < (best - target).abs()) best = at;
    at = compact.indexOf(needle, at + 1);
  }
  return best == null ? null : (start: best, end: best + needle.length);
}

/// A highlight's place on Windows: a chapter and a range of its compact
/// text. Written as "r:3:120:180".
class HighlightRange {
  const HighlightRange(this.chapter, this.start, this.end);

  final int chapter;
  final int start;
  final int end;

  String get locator => 'r:$chapter:$start:$end';

  static HighlightRange? parse(String locator) {
    final parts = locator.split(':');
    if (parts.length != 4 || parts[0] != 'r') return null;
    final chapter = int.tryParse(parts[1]);
    final start = int.tryParse(parts[2]);
    final end = int.tryParse(parts[3]);
    if (chapter == null || start == null || end == null) return null;
    if (chapter < 0 || start < 0 || end <= start) return null;
    return HighlightRange(chapter, start, end);
  }
}

/// A passage to mark: a range of the compact text and the name of its
/// colour.
typedef PassageMark = ({int start, int end, String colour});

bool _isNoteRef(dom.Element link) {
  final href = link.attributes['href'] ?? '';
  if (!href.contains('#') || href.contains('://')) return false;
  final type = '${link.attributes['epub:type'] ?? ''} '
      '${link.attributes['role'] ?? ''}';
  if (type.contains('backlink')) return false;
  if (type.contains('noteref')) return true;
  // Books without those marks: a superscript link to a place.
  final inSup = link.parent?.localName == 'sup';
  final hasSup = link.nodes.whereType<dom.Element>().any(
        (e) => e.localName == 'sup',
      );
  return inSup || hasSup;
}

/// The address a footnote link gets, so a tap shows the note instead of
/// going to it.
const noteScheme = 'chapterly-note:';

/// Gets a chapter's page ready to show on Windows: footnote links are
/// marked (their address starts with [noteScheme]) and [marks] are wrapped
/// in `<mark data-colour="...">`, even across bold, italic or links.
String prepareChapterHtml(String html, {List<PassageMark> marks = const []}) {
  final root = html_parser.parseFragment(html);
  void links(dom.Node node) {
    for (final child in node.nodes) {
      if (child is! dom.Element) continue;
      if (child.localName == 'a' && _isNoteRef(child)) {
        child.attributes['href'] = '$noteScheme${child.attributes['href']}';
      }
      links(child);
    }
  }

  links(root);
  if (marks.isNotEmpty) {
    var position = 0;
    _textNodes(root, (text) {
      final raw = text.data;
      final length = raw.replaceAll(_anySpace, '').length;
      final from = position;
      position += length;
      if (length == 0) return;
      final touching = marks
          .where((m) => m.start < from + length && m.end > from)
          .toList();
      if (touching.isEmpty) return;
      String? colourAt(int compactIndex) {
        for (final m in touching) {
          if (compactIndex >= m.start && compactIndex < m.end) return m.colour;
        }
        return null;
      }

      // Each character's colour: a letter by its own place, a space by the
      // letters on both sides of it.
      final colours = List<String?>.filled(raw.length, null);
      var seen = from;
      for (var i = 0; i < raw.length; i++) {
        if (_anySpace.hasMatch(raw[i])) {
          final before = seen > from ? colourAt(seen - 1) : null;
          final after = colourAt(seen);
          colours[i] = before != null && before == after ? before : null;
        } else {
          colours[i] = colourAt(seen);
          seen++;
        }
      }
      final parent = text.parentNode;
      if (parent == null) return;
      var start = 0;
      while (start < raw.length) {
        var end = start + 1;
        while (end < raw.length && colours[end] == colours[start]) {
          end++;
        }
        final piece = raw.substring(start, end);
        final colour = colours[start];
        final dom.Node node;
        if (colour == null) {
          node = dom.Text(piece);
        } else {
          node = dom.Element.tag('mark')
            ..attributes['data-colour'] = colour
            ..append(dom.Text(piece));
        }
        parent.insertBefore(node, text);
        start = end;
      }
      text.remove();
    });
  }
  return root.outerHtml;
}
