import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'isbn_update.dart' show isbn13Of;

// The same code is in the Windows app; keep the two copies alike.

/// The columns of a Goodreads library export, in Goodreads' order.
/// StoryGraph's importer reads this format too.
const goodreadsColumns = [
  'Book Id',
  'Title',
  'Author',
  'Author l-f',
  'Additional Authors',
  'ISBN',
  'ISBN13',
  'My Rating',
  'Average Rating',
  'Publisher',
  'Binding',
  'Number of Pages',
  'Year Published',
  'Original Publication Year',
  'Date Read',
  'Date Added',
  'Bookshelves',
  'Bookshelves with positions',
  'Exclusive Shelf',
  'My Review',
  'Spoiler',
  'Private Notes',
  'Read Count',
  'Owned Copies',
];

final _formulaStart = RegExp(r'^[=+\-@\t\r]');

String _cell(String value) {
  // A cell starting with = or + could run as a formula in a spreadsheet.
  final safe = _formulaStart.hasMatch(value) ? "'$value" : value;
  if (safe.contains(RegExp(r'[",\n\r]'))) {
    return '"${safe.replaceAll('"', '""')}"';
  }
  return safe;
}

/// Goodreads writes ISBNs as ="0441172717" so spreadsheets keep them as
/// text. Only digits and X ever go inside.
String _isbnCell(String? isbn) => isbn == null ? '=""' : '="$isbn"';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime? date) => date == null
    ? ''
    : '${date.year}/${_two(date.month)}/${_two(date.day)}';

/// "Brandon Sanderson" as "Sanderson, Brandon".
String authorLastFirst(String author) {
  final name = author.split(RegExp(r'\s*(,|&|\band\b)\s*')).first.trim();
  final parts = name.split(RegExp(r'\s+'));
  if (parts.length < 2) return name;
  return '${parts.last}, ${parts.sublist(0, parts.length - 1).join(' ')}';
}

/// A tag as a Goodreads shelf name: lower case, hyphens for spaces.
String goodreadsShelfName(String tag) => tag
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String goodreadsExclusiveShelf(Shelf shelf) => switch (shelf) {
      Shelf.finished => 'read',
      Shelf.inProgress => 'currently-reading',
      Shelf.forLater || Shelf.wishlist => 'to-read',
      Shelf.unfinished => 'did-not-finish',
    };

String _binding(BookFormat? format) => switch (format) {
      BookFormat.paperback => 'Paperback',
      BookFormat.hardcover => 'Hardcover',
      BookFormat.ebook => 'Kindle Edition',
      BookFormat.audiobook => 'Audiobook',
      null => '',
    };

/// The title the way Goodreads writes it: "The Way of Kings (The Stormlight
/// Archive, #1)". Goodreads and StoryGraph read the series from there.
String goodreadsTitle(Book book) {
  final series = book.series?.trim() ?? '';
  if (series.isEmpty) return book.title;
  final number = book.seriesNumber;
  return '${book.title} ($series${number == null ? '' : ', #$number'})';
}

/// Your books as a Goodreads library export, which Goodreads and StoryGraph
/// can import. Deleted books are left out. Your notes go in Private Notes,
/// so they are not posted as a public review.
String encodeGoodreadsCsv(List<Book> books) {
  final lines = <String>[goodreadsColumns.join(',')];
  var id = 0;
  for (final book in books) {
    if (book.deletedAt != null) continue;
    id++;
    final digits = (book.isbn ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '');
    final isbn10 = digits.length == 10 ? digits.toUpperCase() : null;
    final isbn13 = isbn13Of(digits) ?? (digits.length == 13 ? digits : null);
    final shelves = <String>{
      for (final tag in book.tags)
        if (goodreadsShelfName(tag).isNotEmpty) goodreadsShelfName(tag),
      if (book.shelf == Shelf.wishlist) 'wishlist',
      if (book.favorite) 'favorites',
    };
    final exclusive = goodreadsExclusiveShelf(book.shelf);
    final reads = book.previousReadings.length +
        (book.shelf == Shelf.finished ? 1 : 0);
    final cells = <String>[
      '$id',
      _cell(goodreadsTitle(book)),
      _cell(book.author),
      _cell(authorLastFirst(book.author)),
      '',
      _isbnCell(isbn10),
      _isbnCell(isbn13),
      '${book.rating ?? 0}',
      '',
      '',
      _binding(book.format),
      book.pages?.toString() ?? '',
      '',
      book.firstPublishYear?.toString() ?? '',
      _date(book.finishedAt),
      _date(book.addedAt),
      _cell(shelves.join(', ')),
      _cell([for (final shelf in shelves) '$shelf (#$id)'].join(', ')),
      exclusive,
      '',
      '',
      _cell(book.notes ?? ''),
      '$reads',
      book.format == BookFormat.paperback ||
              book.format == BookFormat.hardcover
          ? '1'
          : '0',
    ];
    lines.add(cells.join(','));
  }
  return '${lines.join('\n')}\n';
}
