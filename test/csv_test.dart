import 'package:chapterly/data/csv.dart';
import 'package:chapterly/data/date_format.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseCsv handles quotes, commas and line breaks in cells', () {
    final rows = parseCsv('a,"b,1","say ""hi""",\n"x\ny",2\r\n');

    expect(rows, hasLength(2));
    expect(rows[0], ['a', 'b,1', 'say "hi"', '']);
    expect(rows[1], ['x\ny', '2']);
  });

  test('exporting then importing keeps every field', () {
    final book = Book(
      id: '1',
      title: 'The "Odd" Book, Part 1',
      author: 'Jane Doe',
      shelf: Shelf.finished,
      addedAt: DateTime(2025, 2, 3),
      tags: const ['sci-fi', 'to reread'],
      isbn: '9780441172719',
      coverUrl: 'https://example.com/c.jpg',
      firstPublishYear: 1965,
      pages: 604,
      rating: 4,
      startedAt: DateTime(2025, 3, 1),
      finishedAt: DateTime(2025, 3, 15),
    );

    final csv = encodeBooksCsv([book]);
    final result = importBooksFromCsv(csv);

    expect(result.skipped, 0);
    final copy = result.books.single;
    expect(copy.title, 'The "Odd" Book, Part 1');
    expect(copy.author, 'Jane Doe');
    expect(copy.shelf, Shelf.finished);
    expect(copy.tags, ['sci-fi', 'to reread']);
    expect(copy.isbn, '9780441172719');
    expect(copy.coverUrl, 'https://example.com/c.jpg');
    expect(copy.firstPublishYear, 1965);
    expect(copy.pages, 604);
    expect(copy.rating, 4);
    expect(copy.startedAt, DateTime(2025, 3, 1));
    expect(copy.finishedAt, DateTime(2025, 3, 15));
    expect(copy.addedAt, DateTime(2025, 2, 3));
  });

  test('imports a Goodreads export', () {
    const header = 'Book Id,Title,Author,Author l-f,Additional Authors,ISBN,'
        'ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,'
        'Year Published,Original Publication Year,Date Read,Date Added,'
        'Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review';
    const dune = '1,Dune,Frank Herbert,"Herbert, Frank",,"=""0441172717""",'
        '"=""9780441172719""",5,4.3,Ace,Paperback,604,1990,1965,2020/05/12,'
        '2019/01/01,"sci-fi, favorites, read",,read,';
    const emma = '2,Emma,Jane Austen,"Austen, Jane",,"=""""","=""""",0,3.9,'
        'Penguin,Paperback,,2003,1815,,2021/02/02,to-read,,to-read,';

    final result = importBooksFromCsv([header, dune, emma].join('\n'));

    expect(result.books, hasLength(2));
    final first = result.books[0];
    expect(first.title, 'Dune');
    expect(first.author, 'Frank Herbert');
    expect(first.shelf, Shelf.finished);
    expect(first.rating, 5);
    expect(first.pages, 604);
    expect(first.isbn, '9780441172719');
    expect(first.firstPublishYear, 1965);
    expect(first.finishedAt, DateTime(2020, 5, 12));
    expect(first.tags, ['sci-fi', 'favorites']);

    final second = result.books[1];
    expect(second.shelf, Shelf.forLater);
    expect(second.rating, isNull);
    expect(second.isbn, isNull);
    expect(second.pages, isNull);
    expect(second.tags, isEmpty);
  });

  test('rows without a title are skipped', () {
    final result = importBooksFromCsv('Title,Author\nDune,Frank\n,Nobody\n');

    expect(result.books, hasLength(1));
    expect(result.skipped, 1);
  });

  test('a file with no Title column is rejected', () {
    expect(
      () => importBooksFromCsv('Name,Colour\nA,red\n'),
      throwsA(isA<FormatException>()),
    );
    expect(() => importBooksFromCsv(''), throwsA(isA<FormatException>()));
  });

  test('dates are written and read as yyyy-mm-dd', () {
    expect(formatDate(DateTime(2024, 3, 5)), '2024-03-05');
    expect(parseDate('2020/05/12'), DateTime(2020, 5, 12));
    expect(parseDate('2024-03-05T10:00:00Z'), DateTime(2024, 3, 5));
    expect(parseDate('nonsense'), isNull);
    expect(parseDate(''), isNull);
    expect(parseDate('2024-13-01'), isNull);
  });
}
