import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';

/// The columns of the table view.
enum TableColumn {
  title,
  author,
  shelf,
  rating,
  pages,
  format,
  started,
  finished,
  added,
  tags,
}

extension TableColumnInfo on TableColumn {
  String get label => switch (this) {
        TableColumn.title => 'Title',
        TableColumn.author => 'Author',
        TableColumn.shelf => 'Shelf',
        TableColumn.rating => 'Rating',
        TableColumn.pages => 'Pages',
        TableColumn.format => 'Format',
        TableColumn.started => 'Started',
        TableColumn.finished => 'Finished',
        TableColumn.added => 'Added',
        TableColumn.tags => 'Tags',
      };

  /// The column's width in logical pixels. The title column grows to fill
  /// any room left over.
  double get width => switch (this) {
        TableColumn.title => 280,
        TableColumn.author => 190,
        TableColumn.shelf => 120,
        TableColumn.rating => 100,
        TableColumn.pages => 70,
        TableColumn.format => 100,
        TableColumn.started => 100,
        TableColumn.finished => 100,
        TableColumn.added => 100,
        TableColumn.tags => 180,
      };

  /// Whether the column can be typed into directly (double-click).
  bool get typable =>
      this == TableColumn.title ||
      this == TableColumn.author ||
      this == TableColumn.pages;

  /// Whether a click on the cell opens a list to pick from.
  bool get pickable =>
      this == TableColumn.shelf ||
      this == TableColumn.rating ||
      this == TableColumn.format;
}

int _compareText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Compares two values that may be missing. Missing values go last,
/// whichever way the column is sorted, so this returns them separately.
int? _missing(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return null;
}

/// Sorts [books] by [column]. Books with nothing in that column come last
/// either way. Ties are broken by title.
List<Book> sortByColumn(
  List<Book> books,
  TableColumn column, {
  required bool ascending,
}) {
  int compare(Book a, Book b) {
    Object? valueOf(Book book) => switch (column) {
          TableColumn.title => book.title,
          TableColumn.author => book.author.isEmpty ? null : book.author,
          TableColumn.shelf => book.shelf.index,
          TableColumn.rating => book.rating,
          TableColumn.pages => book.pages,
          TableColumn.format => book.format?.index,
          TableColumn.started => book.startedAt,
          TableColumn.finished => book.finishedAt,
          TableColumn.added => book.addedAt,
          TableColumn.tags => book.tags.isEmpty ? null : book.tags.join(', '),
        };
    final va = valueOf(a);
    final vb = valueOf(b);
    final missing = _missing(va, vb);
    if (missing != null && missing != 0) return missing;
    var result = 0;
    if (missing == null) {
      result = switch ((va, vb)) {
        (final String x, final String y) => _compareText(x, y),
        (final int x, final int y) => x.compareTo(y),
        (final DateTime x, final DateTime y) => x.compareTo(y),
        _ => 0,
      };
      if (!ascending) result = -result;
    }
    return result != 0 ? result : _compareText(a.title, b.title);
  }

  return [...books]..sort(compare);
}

/// The text a cell shows.
String cellText(
  Book book,
  TableColumn column, {
  required String Function(DateTime) date,
  required String Function(int) rating,
}) =>
    switch (column) {
      TableColumn.title => book.title,
      TableColumn.author => book.author,
      TableColumn.shelf => book.shelf.label,
      TableColumn.rating => book.rating == null ? '' : rating(book.rating!),
      TableColumn.pages => book.pages?.toString() ?? '',
      TableColumn.format => book.format?.label ?? '',
      TableColumn.started =>
        book.startedAt == null ? '' : date(book.startedAt!),
      TableColumn.finished =>
        book.finishedAt == null ? '' : date(book.finishedAt!),
      TableColumn.added => date(book.addedAt),
      TableColumn.tags => book.tags.join(', '),
    };
