import 'dart:io';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/calibre.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _opf = '''<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uuid_id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier opf:scheme="calibre" id="calibre_id">12</dc:identifier>
    <dc:identifier opf:scheme="ISBN">978-0-441-17271-9</dc:identifier>
    <dc:title>Dune &amp; Messiah</dc:title>
    <dc:creator opf:file-as="Herbert, Frank" opf:role="aut">Frank Herbert</dc:creator>
    <dc:contributor opf:role="bkp">calibre</dc:contributor>
    <dc:date>1969-10-01T07:00:00+00:00</dc:date>
    <dc:subject>Science Fiction</dc:subject>
    <dc:subject>Classic</dc:subject>
    <meta name="calibre:series" content="Dune"/>
    <meta name="calibre:series_index" content="2.0"/>
  </metadata>
</package>''';

Book _book(String id, String title, String author) => Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
    );

void main() {
  group('parseCalibreOpf', () {
    test('reads title, author, isbn, series, tags and year', () {
      final info = parseCalibreOpf(_opf)!;
      expect(info.title, 'Dune & Messiah');
      expect(info.author, 'Frank Herbert');
      expect(info.isbn, '9780441172719');
      expect(info.series, 'Dune');
      expect(info.seriesNumber, 2);
      expect(info.tags, ['Science Fiction', 'Classic']);
      expect(info.year, 1969);
    });

    test('ignores Calibre\'s "no date" and a missing title', () {
      final info = parseCalibreOpf(
        '<metadata><dc:title>X</dc:title><dc:date>0101-01-01T00:00:00+00:00</dc:date></metadata>',
      )!;
      expect(info.year, isNull);
      expect(info.series, isNull);
      expect(parseCalibreOpf('<metadata></metadata>'), isNull);
    });
  });

  group('Calibre folders', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('calibre_test'));
    tearDown(() => temp.deleteSync(recursive: true));

    void makeBook(String dir, String opf, {List<String> files = const []}) {
      Directory('${temp.path}/$dir').createSync(recursive: true);
      File('${temp.path}/$dir/metadata.opf').writeAsStringSync(opf);
      for (final file in files) {
        File('${temp.path}/$dir/$file').writeAsBytesSync([1, 2, 3]);
      }
    }

    test('finds books, their files and skips the trash', () async {
      makeBook('Frank Herbert/Dune (12)', _opf,
          files: ['Dune.pdf', 'Dune.epub', 'cover.jpg']);
      makeBook('.caltrash/b/Old (3)', _opf, files: ['Old.epub']);
      File('${temp.path}/metadata.db').writeAsBytesSync([0]);
      expect(isCalibreLibrary(temp.path), isTrue);
      final books = await findCalibreBooks(temp.path);
      expect(books, hasLength(1));
      expect(books.single.bookFiles.first, endsWith('Dune.epub'));
      expect(books.single.bookFiles, hasLength(2));
      expect(books.single.info.coverPath, endsWith('cover.jpg'));
    });

    test('a folder without metadata.opf is not a Calibre book', () async {
      Directory('${temp.path}/Plain').createSync();
      File('${temp.path}/Plain/x.epub').writeAsBytesSync([1]);
      expect(await readCalibreFolder('${temp.path}/Plain'), isNull);
      expect(await findCalibreBooks(temp.path), isEmpty);
    });

    test('plan: add new, fill matches, leave unsure and repeats', () async {
      makeBook('a/Dune (1)', _opf, files: ['Dune.epub']);
      makeBook('b/Other (2)', _opf.replaceAll('Dune &amp; Messiah', 'Brand New Book')
          .replaceAll('Frank Herbert', 'Someone Else'),
          files: ['o.epub']);
      makeBook('c/Other (3)', _opf.replaceAll('Dune &amp; Messiah', 'Brand New Book')
          .replaceAll('Frank Herbert', 'Someone Else'),
          files: ['o.epub']);
      final calibre = await findCalibreBooks(temp.path);
      final plan = planCalibreImport(
        calibre,
        [_book('1', 'Dune & Messiah', 'Frank Herbert')],
      );
      final outcomes = {
        for (final e in plan) '${e.book.info.title}|${e.outcome.name}': e,
      };
      expect(outcomes.keys, containsAll(['Dune & Messiah|fill', 'Brand New Book|add', 'Brand New Book|unsure']));
      expect(outcomes['Dune & Messiah|fill']!.match!.id, '1');
    });

    test('fills only blank details, with a cover', () async {
      final repository = BookRepository(InMemoryBookStore());
      await repository.add(
        title: 'Dune & Messiah',
        author: 'Frank Herbert',
        shelf: Shelf.finished,
        tags: ['mine'],
        isbn: '111',
      );
      final id = repository.allBooks.first.id;
      final cover = File('${temp.path}/cover.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 4, height: 4)));
      final info = parseCalibreOpf(_opf, coverPath: cover.path)!;
      expect(await fillFromCalibre(repository, id, info), isTrue);
      final book = repository.byId(id)!;
      expect(book.tags, ['mine']);
      expect(book.isbn, '111');
      expect(book.series, 'Dune');
      expect(book.seriesNumber, 2);
      expect(book.firstPublishYear, 1969);
      expect(book.coverUrl, startsWith('data:image/jpeg'));
      // Nothing left to fill the second time.
      expect(await fillFromCalibre(repository, id, info), isFalse);
    });
  });
}
