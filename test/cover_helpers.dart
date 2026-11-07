import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/models/book.dart';

/// The picture a book shows: kept apart from it since 1.45.0, so read from
/// [repository] when the book holds a reference.
Future<String?> pictureOf(BookRepository repository, Book? book) async {
  final url = book?.coverUrl;
  final hash = hashOfCoverRef(url);
  return hash == null ? url : repository.readCover(hash);
}
