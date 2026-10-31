import 'dart:io';

import 'package:path/path.dart' as p;

import '../audio/audio_library.dart';
import '../ebook/ebook_library.dart';
import '../models/book.dart';
import 'book_repository.dart';
import 'cover_image.dart';
import 'file_match.dart';

// Windows app only: using a Calibre library folder as a source of book
// details and covers.
//
// Calibre keeps each book in its own folder ("Frank Herbert/Dune (12)/")
// with the book file, a cover.jpg and a metadata.opf that lists its title,
// author, series, tags, ISBN and date. Those two small files are read; the
// metadata.db database is not needed.

/// What Calibre knows about one book.
class CalibreInfo {
  const CalibreInfo({
    this.title = '',
    this.author = '',
    this.isbn,
    this.series,
    this.seriesNumber,
    this.tags = const [],
    this.year,
    this.coverPath,
  });

  final String title;
  final String author;
  final String? isbn;
  final String? series;
  final int? seriesNumber;
  final List<String> tags;

  /// Year of the book's date in Calibre. Null when Calibre has none.
  final int? year;

  /// The cover.jpg next to the book, when there is one.
  final String? coverPath;
}

/// The details in the text of a Calibre metadata.opf file. Null when it has
/// no title.
CalibreInfo? parseCalibreOpf(String xml, {String? coverPath}) {
  final metadata = RegExp(
        r'<(?:\w+:)?metadata\b[\s\S]*?</(?:\w+:)?metadata>',
      ).firstMatch(xml)?[0] ??
      xml;

  String title = '';
  for (final match in RegExp(
    r'<(?:\w+:)?title\b[^>]*>([\s\S]*?)</(?:\w+:)?title>',
  ).allMatches(metadata)) {
    title = _text(match[1]!);
    if (title.isNotEmpty) break;
  }
  if (title.isEmpty) return null;

  final authors = <String>[];
  for (final match in RegExp(
    r'<(?:\w+:)?creator\b([^>]*)>([\s\S]*?)</(?:\w+:)?creator>',
  ).allMatches(metadata)) {
    final role = _attribute(match[1]!, 'role');
    final name = _text(match[2]!);
    if (name.isNotEmpty && (role == null || role == 'aut')) {
      authors.add(name);
    }
  }

  String? isbn;
  for (final match in RegExp(
    r'<(?:\w+:)?identifier\b([^>]*)>([\s\S]*?)</(?:\w+:)?identifier>',
  ).allMatches(metadata)) {
    final scheme = (_attribute(match[1]!, 'scheme') ?? '').toLowerCase();
    final value = _text(match[2]!);
    if (scheme == 'isbn' || value.toLowerCase().startsWith('urn:isbn:')) {
      final digits = value.replaceAll(RegExp(r'[^0-9Xx]'), '');
      if (digits.length == 10 || digits.length == 13) {
        isbn = digits.toUpperCase();
        break;
      }
    }
  }

  String? series;
  double? index;
  for (final match in RegExp(r'<(?:\w+:)?meta\b([^>]*?)/?>').allMatches(metadata)) {
    final name = _attribute(match[1]!, 'name');
    final content = _attribute(match[1]!, 'content');
    if (name == 'calibre:series' && content != null && content.trim().isNotEmpty) {
      series = content.trim();
    } else if (name == 'calibre:series_index' && content != null) {
      index = double.tryParse(content.trim());
    }
  }

  final tags = <String>[];
  for (final match in RegExp(
    r'<(?:\w+:)?subject\b[^>]*>([\s\S]*?)</(?:\w+:)?subject>',
  ).allMatches(metadata)) {
    final tag = _text(match[1]!);
    if (tag.isNotEmpty && !tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
      tags.add(tag);
    }
  }

  // Calibre writes 0101-01-01 for "no date".
  int? year;
  final date = RegExp(r'<(?:\w+:)?date\b[^>]*>\s*(\d{4})')
      .firstMatch(metadata)?[1];
  final parsed = date == null ? null : int.tryParse(date);
  if (parsed != null && parsed >= 1000 && parsed <= 2200) year = parsed;

  return CalibreInfo(
    title: title,
    author: authors.take(3).join(', '),
    isbn: isbn,
    series: series,
    seriesNumber:
        series != null && index != null && index >= 1 ? index.round() : null,
    tags: tags,
    year: year,
    coverPath: coverPath,
  );
}

/// The Calibre details for the book in [directory], from its metadata.opf.
/// Null when the folder has none (it is not a Calibre book folder).
Future<CalibreInfo?> readCalibreFolder(String directory) async {
  try {
    final opf = File(p.join(directory, 'metadata.opf'));
    if (!await opf.exists()) return null;
    final cover = File(p.join(directory, 'cover.jpg'));
    return parseCalibreOpf(
      await opf.readAsString(),
      coverPath: await cover.exists() ? cover.path : null,
    );
  } catch (_) {
    return null;
  }
}

/// Whether [folder] is the top of a Calibre library.
bool isCalibreLibrary(String folder) =>
    File(p.join(folder, 'metadata.db')).existsSync();

/// Fills in what the book does not have yet from Calibre: the cover, series,
/// tags, ISBN and year. Nothing the book already has is changed. Returns
/// whether anything was filled in.
Future<bool> fillFromCalibre(
  BookRepository repository,
  String bookId,
  CalibreInfo info,
) async {
  final book = repository.byId(bookId);
  if (book == null) return false;
  String? cover;
  if ((book.coverUrl ?? '').isEmpty && info.coverPath != null) {
    cover = await _coverFrom(info.coverPath!);
  }
  return repository.fillBlanks(
    bookId,
    isbn: info.isbn,
    year: info.year,
    series: info.series,
    seriesNumber: info.seriesNumber,
    tags: info.tags,
    coverUrl: cover,
  );
}

Future<String?> _coverFrom(String path) async {
  try {
    final file = File(path);
    if (await file.length() > 20 * 1024 * 1024) return null;
    return await makeDataCover(await file.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// One book folder of a Calibre library.
class CalibreBook {
  const CalibreBook({
    required this.info,
    required this.directory,
    required this.bookFiles,
    required this.audioFiles,
  });

  final CalibreInfo info;
  final String directory;

  /// The EPUB and PDF files, best format (EPUB) first.
  final List<String> bookFiles;
  final List<String> audioFiles;
}

/// Every book in a Calibre library folder (any folder holding a
/// metadata.opf), skipping Calibre's own trash.
Future<List<CalibreBook>> findCalibreBooks(String root) async {
  final byDirectory = <String, List<File>>{};
  try {
    await for (final entity
        in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final parts = p.split(p.relative(entity.path, from: root));
      if (parts.any((part) => part.toLowerCase() == '.caltrash')) continue;
      byDirectory.putIfAbsent(p.dirname(entity.path), () => []).add(entity);
    }
  } catch (_) {
    // A folder that cannot be read: what was found so far is used.
  }
  final books = <CalibreBook>[];
  for (final entry in byDirectory.entries) {
    final names = [for (final file in entry.value) p.basename(file.path)];
    if (!names.contains('metadata.opf')) continue;
    final info = await readCalibreFolder(entry.key);
    if (info == null) continue;
    final bookFiles = [
      for (final file in entry.value)
        if (ebookFormatOf(file.path) != null) file.path,
    ]..sort((a, b) {
        final epubA = ebookFormatOf(a) == EbookFormat.epub ? 0 : 1;
        final epubB = ebookFormatOf(b) == EbookFormat.epub ? 0 : 1;
        return epubA != epubB ? epubA - epubB : naturalCompare(a, b);
      });
    final audioFiles = [
      for (final file in entry.value)
        if (isAudioFileName(file.path)) file.path,
    ]..sort(naturalCompare);
    books.add(CalibreBook(
      info: info,
      directory: entry.key,
      bookFiles: bookFiles,
      audioFiles: audioFiles,
    ));
  }
  books.sort((a, b) => naturalCompare(
        a.info.title.toLowerCase(),
        b.info.title.toLowerCase(),
      ));
  return books;
}

/// What an import does with one Calibre book.
enum CalibreOutcome {
  /// Not in your library: it is added.
  add,

  /// Clearly a book you have: only blank details are filled in.
  fill,

  /// Might be a book you have, but not clearly: left alone.
  unsure,
}

class CalibrePlanEntry {
  const CalibrePlanEntry(this.book, this.outcome, [this.match]);

  final CalibreBook book;
  final CalibreOutcome outcome;

  /// The book in your library, for [CalibreOutcome.fill].
  final Book? match;
}

/// Decides what to do with each Calibre book. A book is only added when
/// nothing in your library looks like it.
List<CalibrePlanEntry> planCalibreImport(
  List<CalibreBook> calibre,
  List<Book> library,
) {
  final added = <String>{};
  final entries = <CalibrePlanEntry>[];
  for (final book in calibre) {
    final matches = findMatchingBooks(
      library,
      title: book.info.title,
      author: book.info.author,
    );
    if (matches.isEmpty) {
      // The same book twice in Calibre is added once.
      final key = '${titleKey(book.info.title)}|${titleKey(book.info.author)}';
      entries.add(CalibrePlanEntry(
        book,
        added.add(key) ? CalibreOutcome.add : CalibreOutcome.unsure,
      ));
    } else if (isSureMatch(matches)) {
      entries.add(CalibrePlanEntry(book, CalibreOutcome.fill, matches.first.book));
    } else {
      entries.add(CalibrePlanEntry(book, CalibreOutcome.unsure));
    }
  }
  return entries;
}

// ---- Reading the XML

String? _attribute(String tag, String name) {
  final match = RegExp(
    '(?:^|\\s)(?:\\w+:)?$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
  ).firstMatch(tag);
  if (match == null) return null;
  return _decodeEntities(match[1] ?? match[2] ?? '');
}

String _text(String xml) {
  final plain = xml
      .replaceAllMapped(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), (m) => m[1]!)
      .replaceAll(RegExp(r'<[^>]*>'), ' ');
  return _decodeEntities(plain).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _decodeEntities(String text) {
  return text.replaceAllMapped(
    RegExp(r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos);'),
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
    },
  );
}
