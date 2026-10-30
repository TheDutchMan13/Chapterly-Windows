import 'package:chapterly/data/open_library_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the median page count when Open Library has one', () {
    final book = OpenLibraryBook.fromJson({
      'title': 'Dune',
      'number_of_pages_median': 604,
    });

    expect(book.pages, 604);
  });

  test('page count is null when missing or not a number', () {
    expect(OpenLibraryBook.fromJson({'title': 'A'}).pages, isNull);
    expect(
      OpenLibraryBook.fromJson({'title': 'A', 'number_of_pages_median': 0})
          .pages,
      isNull,
    );
  });
}
