import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/google_books_client.dart';
import 'package:chapterly/data/hardcover_client.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/tidy_text.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/fix_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The same tests are in the Android app.

Book _book(String id, String title, String author) => Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      coverUrl: 'https://example.com/$id.jpg',
      isbn: '9780385518345',
      series: 'Series $id',
      seriesNumber: 1,
    );

void main() {
  group('titles', () {
    test('HTML characters are decoded, once', () {
      expect(tidyText('Bush&#39;s Wars'), "Bush's Wars");
      expect(tidyText('Bush&#x27;s Wars'), "Bush's Wars");
      expect(tidyText('Pride &amp; Prejudice'), 'Pride & Prejudice');
      expect(tidyText('&quot;Dune&quot;'), '"Dune"');
      // Decoded one time only: the result is not decoded again.
      expect(tidyText('Tom &amp;#39; Jerry'), 'Tom &#39; Jerry');
    });

    test('what is not a real character reference is left alone', () {
      expect(tidyText('Cats &foo; Dogs'), 'Cats &foo; Dogs');
      expect(tidyText('A &#0; B'), 'A &#0; B');
      expect(tidyText('A &#7; B'), 'A &#7; B');
      expect(tidyText('A &#xD800; B'), 'A &#xD800; B');
      expect(tidyText('Q&A: a guide'), 'Q&A: a guide');
      expect(tidyText('AT&T and me'), 'AT&T and me');
    });

    test('extra spaces and line breaks go, the rest stays as written', () {
      expect(tidyText('  Tom   Clancy \n'), 'Tom Clancy');
      expect(tidyText('Jack Ryan 25 - Line of Sight'),
          'Jack Ryan 25 - Line of Sight');
      expect(tidyText('Silo Series #1'), 'Silo Series #1');
      expect(tidyText('ISIS'), 'ISIS');
      expect(tidyText('Café Ünïcode ✓'), 'Café Ünïcode ✓');
      expect(tidyText(''), '');
    });
  });

  group('authors', () {
    test('catalogue style: semicolons, years and Last, First', () {
      expect(tidyAuthor('Gordon, Michael R., 1951-;Trainor, Bernard E., 1928-'),
          'Michael R. Gordon, Bernard E. Trainor');
      expect(tidyAuthor('Yassin-Kassab, Robin; Al-Shami, Leila;'),
          'Robin Yassin-Kassab, Leila Al-Shami');
      expect(tidyAuthor('Neil Sheehan; Hedrick Smith'),
          'Neil Sheehan, Hedrick Smith');
      expect(tidyAuthor('Leander Kahney;'), 'Leander Kahney');
      expect(tidyAuthor('Smith, John, 1950-'), 'John Smith');
      expect(tidyAuthor('Smith, John (1950-2020)'), 'John Smith');
    });

    test('a list of authors is never reordered', () {
      expect(tidyAuthor('Lee Child, Andrew Child'), 'Lee Child, Andrew Child');
      expect(tidyAuthor("Norah O'Donnell, Kate Andersen Brower"),
          "Norah O'Donnell, Kate Andersen Brower");
      expect(tidyAuthor('Frank Herbert'), 'Frank Herbert');
      expect(tidyAuthor('Unknown'), 'Unknown');
      expect(tidyAuthor(''), '');
    });

    test('a name with Jr. is only stripped of its years, not flipped', () {
      expect(tidyAuthor('King, Martin Luther, Jr., 1929-1968'),
          'King, Martin Luther, Jr.');
    });

    test('a mix of styles is not flipped', () {
      expect(tidyAuthor('Gordon, Michael R.; Neil Sheehan'),
          'Gordon, Michael R., Neil Sheehan');
    });

    test('tidying twice changes nothing more', () {
      for (final author in [
        'Gordon, Michael R., 1951-;Trainor, Bernard E., 1928-',
        'Yassin-Kassab, Robin; Al-Shami, Leila;',
        'Lee Child, Andrew Child',
        'King, Martin Luther, Jr., 1929-1968',
      ]) {
        final once = tidyAuthor(author);
        expect(tidyAuthor(once), once, reason: author);
      }
    });
  });

  test('damaged text is recognised, real text is not', () {
    expect(looksDamaged('¶Eêå\x08#Eö_ðû\x02¢E\x1d\x19[\x19\x00'), isTrue);
    expect(looksDamaged('Broken � title'), isTrue);
    expect(looksDamaged('Café Ünïcode ✓ 日本語\n'.trim()), isFalse);
    expect(looksDamaged("Bush's Wars"), isFalse);
  });

  test('lookups come back clean', () {
    final google = GoogleBook.fromJson({
      'volumeInfo': {
        'title': 'Bush&#39;s  Wars',
        'authors': ['Frank &amp; Sons', 'Jane Austen'],
      },
    })!;
    expect(google.title, "Bush's Wars");
    expect(google.author, 'Frank & Sons, Jane Austen');
    final open = OpenLibraryBook.fromJson({
      'title': 'Pride &amp; Prejudice ',
      'author_name': ['Jane  Austen'],
    });
    expect(open.title, 'Pride & Prejudice');
    expect(open.author, 'Jane Austen');
  });

  group('Fix library', () {
    Future<BookRepository> open(WidgetTester tester, List<Book> books) async {
      // Tall enough to show every step and the results without scrolling.
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.replaceAll(books);
      final offline = MockClient((_) async => http.Response('{}', 404));
      await tester.pumpWidget(MaterialApp(
        home: FixLibraryScreen(
          repository: repository,
          client: OpenLibraryClient(client: offline),
          hardcover: HardcoverClient(token: () => null, client: offline),
          google: GoogleBooksClient(client: offline, pause: Duration.zero),
        ),
      ));
      return repository;
    }

    // Runs only the Titles and authors step.
    Future<void> runTitlesOnly(WidgetTester tester) async {
      for (final step in [
        'Series spelled two ways',
        'From your book files',
        'ISBNs',
        'Covers',
        'Larger covers',
      ]) {
        await tester.tap(find.text(step));
        await tester.pump();
      }
      await tester.tap(find.text('Check my library'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the changes first and changes nothing until Apply',
        (tester) async {
      final repository = await open(tester, [
        _book('1', 'Bush&#39;s Wars', 'Frank Herbert'),
        _book('2', 'Dune', 'Gordon, Michael R., 1951-;Trainor, Bernard E., 1928-'),
        _book('3', 'Emma', 'Jane Austen'),
        _book('4', '¶Eêå\x08#Eö', '¾Týÿ +LöMãè\x0e'),
      ]);
      expect(find.text('Titles and authors'), findsOneWidget);
      await runTitlesOnly(tester);

      // Found, but nothing is changed yet.
      expect(find.textContaining("Bush's Wars"), findsOneWidget);
      expect(find.textContaining('Michael R. Gordon, Bernard E. Trainor'),
          findsOneWidget);
      expect(find.textContaining('Emma'), findsNothing);
      expect(find.textContaining('damaged'), findsOneWidget);
      expect(repository.byId('1')!.title, 'Bush&#39;s Wars');
      expect(repository.byId('2')!.author,
          'Gordon, Michael R., 1951-;Trainor, Bernard E., 1928-');

      await tester.tap(find.text('Apply 2 changes'));
      await tester.pumpAndSettle();
      expect(repository.byId('1')!.title, "Bush's Wars");
      expect(repository.byId('1')!.author, 'Frank Herbert');
      expect(repository.byId('2')!.title, 'Dune');
      expect(repository.byId('2')!.author,
          'Michael R. Gordon, Bernard E. Trainor');
      // Everything else about the books stays as it was.
      expect(repository.byId('1')!.series, 'Series 1');
      expect(repository.byId('1')!.isbn, '9780385518345');
      expect(repository.byId('3')!.title, 'Emma');
      // The damaged book was only reported.
      expect(repository.byId('4')!.title, '¶Eêå\x08#Eö');
    });

    testWidgets('an unticked change is not applied', (tester) async {
      final repository = await open(tester, [
        _book('1', 'Bush&#39;s Wars', 'Frank Herbert'),
      ]);
      await runTitlesOnly(tester);
      expect(find.text('Apply 1 change'), findsOneWidget);
      await tester.tap(find.text('All / none'));
      await tester.pump();
      expect(find.text('Apply 1 change'), findsNothing);
      expect(repository.byId('1')!.title, 'Bush&#39;s Wars');
    });
  });

  test('setTitlesAndAuthors never blanks a book', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.replaceAll([_book('1', 'Dune', 'Frank Herbert')]);
    await repository.setTitlesAndAuthors({'1': ('  ', '')});
    expect(repository.byId('1')!.title, 'Dune');
    expect(repository.byId('1')!.author, 'Frank Herbert');
    await repository.setTitlesAndAuthors({'1': (' Dune Messiah ', 'F. Herbert')});
    expect(repository.byId('1')!.title, 'Dune Messiah');
    expect(repository.byId('1')!.author, 'F. Herbert');
  });
}
