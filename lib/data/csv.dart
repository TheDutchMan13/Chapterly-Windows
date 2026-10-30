import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'book_repository.dart' show parseTags;
import 'date_format.dart';

const csvColumns = [
  'Title',
  'Author',
  'Shelf',
  'Rating',
  'Pages',
  'Date Started',
  'Date Finished',
  'Tags',
  'ISBN',
  'First Published',
  'Date Added',
  'Cover URL',
  'Format',
  'Favorite',
  'Notes',
  'Series',
  'Series Number',
];

String _csvCell(String value) {
  final needsQuotes = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  return needsQuotes ? '"${value.replaceAll('"', '""')}"' : value;
}

String _date(DateTime? date) => date == null ? '' : formatDate(date);

/// The library as CSV that opens in a spreadsheet and can be imported again.
String encodeBooksCsv(List<Book> books) {
  final lines = <String>[csvColumns.map(_csvCell).join(',')];
  for (final book in books) {
    final cells = [
      book.title,
      book.author,
      book.shelf.label,
      book.rating?.toString() ?? '',
      book.pages?.toString() ?? '',
      _date(book.startedAt),
      _date(book.finishedAt),
      book.tags.join(';'),
      book.isbn ?? '',
      book.firstPublishYear?.toString() ?? '',
      formatDate(book.addedAt),
      book.coverUrl ?? '',
      book.format?.label ?? '',
      book.favorite ? 'yes' : '',
      book.notes ?? '',
      book.series ?? '',
      book.seriesNumber?.toString() ?? '',
    ];
    lines.add(cells.map(_csvCell).join(','));
  }
  return '${lines.join('\n')}\n';
}

/// Splits CSV text into rows of cells. Handles quoted cells, doubled quotes,
/// commas and line breaks inside quotes, and both \n and \r\n line endings.
List<List<String>> parseCsv(String text) {
  final input = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows
      .where((r) => !(r.length == 1 && r.first.trim().isEmpty))
      .toList();
}

class CsvImportResult {
  const CsvImportResult({required this.books, required this.skipped});

  final List<Book> books;

  /// Rows that had no title, or were not books (Libib also lists films,
  /// music and games).
  final int skipped;
}

String _cell(List<String> row, List<int> columns) {
  for (final column in columns) {
    if (column < row.length) {
      final value = row[column].trim();
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

String? _isbnFrom(List<String> row, List<int> columns) {
  for (final column in columns) {
    if (column < row.length) {
      final digits = row[column].replaceAll(RegExp(r'[^0-9Xx]'), '');
      if (digits.isNotEmpty) return digits;
    }
  }
  return null;
}

Shelf _shelfFrom(String value) => switch (value.trim().toLowerCase()) {
      'finished' || 'read' || 'completed' => Shelf.finished,
      'in progress' || 'currently-reading' || 'reading' => Shelf.inProgress,
      'unfinished' ||
      'stopped-reading' ||
      'did not finish' ||
      'did-not-finish' ||
      'dnf' ||
      'abandoned' =>
        Shelf.unfinished,
      _ => Shelf.forLater,
    };

/// The year in "1965", "1965-08-01" or "August 1965".
int? _parseYear(String value) {
  final match = RegExp(r'(?<!\d)(\d{4})(?!\d)').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  return year > 0 ? year : null;
}

int? _parseRating(String value) {
  final number = num.tryParse(value);
  if (number == null) return null;
  final rounded = number.round();
  return rounded >= 1 && rounded <= 5 ? rounded : null;
}

int? _parsePositiveInt(String value) {
  final number = int.tryParse(value);
  return number != null && number > 0 ? number : null;
}

const _goodreadsShelfNames = {'read', 'currently-reading', 'to-read'};

List<String> _parseImportedTags(String value) => [
      for (final tag in parseTags(value.replaceAll(';', ',')))
        if (!_goodreadsShelfNames.contains(tag.toLowerCase())) tag,
    ];

/// Reads a CSV made by Chapterly, or exported from Goodreads, StoryGraph or
/// Libib. Columns are found by their header names. Throws [FormatException] with a message for
/// the user if the file does not look like a book list.
CsvImportResult importBooksFromCsv(String text, {DateTime? now}) {
  final timestamp = now ?? DateTime.now();
  final rows = parseCsv(text);
  if (rows.isEmpty) throw const FormatException('The file is empty.');

  final header = [for (final name in rows.first) name.trim().toLowerCase()];
  List<int> find(List<String> names) => [
        for (final name in names)
          if (header.contains(name)) header.indexOf(name),
      ];

  final titleColumns = find(['title']);
  if (titleColumns.isEmpty) {
    throw const FormatException(
      'No "Title" column found. Is this a list of books?',
    );
  }
  final authorColumns = find(['author', 'author_text', 'authors', 'creators']);
  final shelfColumns = find(['shelf', 'exclusive shelf', 'read status', 'status']);
  final ratingColumns = find(['rating', 'my rating', 'star rating']);
  final pagesColumns = find(['pages', 'number of pages', 'length']);
  final startedColumns = find(['date started', 'start_date', 'began']);
  final finishedColumns = find([
    'date finished',
    'date read',
    'finish_date',
    'last date read',
    'completed',
  ]);
  final tagColumns = find(['tags', 'bookshelves']);
  final isbnColumns = find([
    'isbn13',
    'isbn_13',
    'isbn',
    'isbn_10',
    'isbn/uid',
    'ean_isbn13',
    'upc_isbn10',
  ]);
  final yearColumns = find([
    'first published',
    'original publication year',
    'publish_date',
  ]);
  final addedColumns = find(['date added', 'added']);
  final typeColumns = find(['item_type']);
  final coverColumns = find(['cover url']);
  final formatColumns = find(['format', 'binding']);
  final favoriteColumns = find(['favorite', 'favourite']);
  final notesColumns = find(['notes', 'my review', 'review']);
  final seriesColumns = find(['series']);
  final seriesNumberColumns = find(['series number']);

  final books = <Book>[];
  var skipped = 0;
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    final title = _cell(row, titleColumns);
    final type = _cell(row, typeColumns).toLowerCase();
    if (title.isEmpty || (type.isNotEmpty && type != 'book')) {
      skipped++;
      continue;
    }
    final cover = _cell(row, coverColumns);
    books.add(Book(
      id: newBookId(),
      title: title,
      author: _cell(row, authorColumns),
      shelf: _shelfFrom(_cell(row, shelfColumns)),
      addedAt: parseDate(_cell(row, addedColumns)) ?? timestamp,
      tags: _parseImportedTags(_cell(row, tagColumns)),
      isbn: _isbnFrom(row, isbnColumns),
      coverUrl: cover.isEmpty ? null : cover,
      firstPublishYear: _parseYear(_cell(row, yearColumns)),
      pages: _parsePositiveInt(_cell(row, pagesColumns)),
      rating: _parseRating(_cell(row, ratingColumns)),
      startedAt: parseDate(_cell(row, startedColumns)),
      finishedAt: parseDate(_cell(row, finishedColumns)),
      format: parseBookFormat(_cell(row, formatColumns)),
      favorite: const {'yes', 'true', '1', 'x'}
          .contains(_cell(row, favoriteColumns).toLowerCase()),
      notes: _cell(row, notesColumns).isEmpty
          ? null
          : _cell(row, notesColumns),
      series: _cell(row, seriesColumns).isEmpty
          ? null
          : _cell(row, seriesColumns),
      seriesNumber: _parsePositiveInt(_cell(row, seriesNumberColumns)),
    ));
  }
  return CsvImportResult(books: books, skipped: skipped);
}
