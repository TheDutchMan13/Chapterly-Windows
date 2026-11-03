import 'dart:io';

import '../data/book_repository.dart';
import 'ebook_files.dart';
import 'ebook_library.dart';

/// The reader's parts for the whole app, set up in main.dart. Null in tests
/// and until set up, and the reading parts of the screens then stay hidden.
class EbookReading {
  EbookReading._();

  static EbookLibrary? library;
  static EbookFiles? files;

  /// Where Chapterly keeps its copies of book files.
  static Directory? booksDir;

  /// The book open in the reader, if any, so a sync never moves its place
  /// while you read.
  static String? openBookId;

  /// Your books, so a note on a highlight also goes on the book's quote
  /// (and syncs with it).
  static BookRepository? repository;
}
