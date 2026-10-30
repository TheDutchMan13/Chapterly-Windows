import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_sorting.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book(String id, String title, {int? rating, int? pages}) => Book(
      id: id,
      title: title,
      author: 'Author $id',
      shelf: Shelf.finished,
      addedAt: DateTime(2025, 1, int.parse(id)),
      rating: rating,
      pages: pages,
    );

List<String> _ids(List<Book> books) => [for (final b in books) b.id];

void main() {
  final books = [
    _book('1', 'banana', rating: 3, pages: 200),
    _book('2', 'Apple'),
    _book('3', 'cherry', rating: 5, pages: 100),
  ];

  test('sorts by title ignoring case', () {
    expect(_ids(sortBooks(books, SortField.title, ascending: true)),
        ['2', '1', '3']);
    expect(_ids(sortBooks(books, SortField.title, ascending: false)),
        ['3', '1', '2']);
  });

  test('sorts by date added', () {
    expect(_ids(sortBooks(books, SortField.dateAdded, ascending: false)),
        ['3', '2', '1']);
  });

  test('books without a rating go last in both directions', () {
    expect(_ids(sortBooks(books, SortField.rating, ascending: false)),
        ['3', '1', '2']);
    expect(_ids(sortBooks(books, SortField.rating, ascending: true)),
        ['1', '3', '2']);
  });

  test('sorts by pages with missing values last', () {
    expect(_ids(sortBooks(books, SortField.pages, ascending: true)),
        ['3', '1', '2']);
  });

  test('sorting does not change the original list', () {
    sortBooks(books, SortField.title, ascending: true);
    expect(_ids(books), ['1', '2', '3']);
  });

  test('settings are remembered between launches', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.sortField, SortField.dateAdded);
    expect(settings.ascending, isFalse);

    settings.setSort(SortField.title);
    settings.toggleDisplay();
    settings.setGoal(2026, 20);

    final again = await AppSettings.load();
    expect(again.sortField, SortField.title);
    expect(again.ascending, isTrue);
    expect(again.display, DisplayMode.grid);
    expect(again.goalFor(2026), 20);

    again.setSort(SortField.title);
    expect(again.ascending, isFalse);
    again.setGoal(2026, null);
    expect(again.goalFor(2026), isNull);
  });
}
