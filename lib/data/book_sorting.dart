import '../models/book.dart';
import 'app_settings.dart';

int _direction(int result, bool ascending) => ascending ? result : -result;

/// Compares two optional values. Books with no value always go last.
int _compareOptional<T extends Comparable<Object>>(
  T? a,
  T? b,
  bool ascending,
) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return _direction(a.compareTo(b), ascending);
}

/// The Next up order: books you have placed come first, in your order. The
/// rest follow by priority (high first, none last), then the book that has
/// waited longest.
int compareNextUp(Book a, Book b) {
  final byPlace = _compareOptional(a.queuePosition, b.queuePosition, true);
  if (byPlace != 0) return byPlace;
  int rank(Book book) => book.priority?.index ?? -1;
  final byPriority = rank(b).compareTo(rank(a));
  if (byPriority != 0) return byPriority;
  return a.addedAt.compareTo(b.addedAt);
}

/// Returns a sorted copy of [books].
List<Book> sortBooks(
  List<Book> books,
  SortField field, {
  required bool ascending,
}) {
  final sorted = [...books];
  sorted.sort((a, b) => switch (field) {
        SortField.dateAdded =>
          _direction(a.addedAt.compareTo(b.addedAt), ascending),
        SortField.title => _direction(
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            ascending,
          ),
        SortField.author => _direction(
            a.author.toLowerCase().compareTo(b.author.toLowerCase()),
            ascending,
          ),
        SortField.rating => _compareOptional(a.rating, b.rating, ascending),
        SortField.pages => _compareOptional(a.pages, b.pages, ascending),
        SortField.dateFinished =>
          _compareOptional(a.finishedAt, b.finishedAt, ascending),
        SortField.publicationYear => _compareOptional(
            a.firstPublishYear, b.firstPublishYear, ascending),
        SortField.dateModified =>
          _direction(a.updatedAt.compareTo(b.updatedAt), ascending),
        SortField.format =>
          _compareOptional(a.format?.index, b.format?.index, ascending),
        SortField.priority =>
          _compareOptional(a.priority?.index, b.priority?.index, ascending),
        SortField.nextUp => _direction(compareNextUp(a, b), ascending),
        SortField.favorite => _direction(
            a.favorite == b.favorite ? 0 : (a.favorite ? 1 : -1),
            ascending,
          ),
      });
  return sorted;
}
