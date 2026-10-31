import 'dart:io';

import 'package:chapterly/audio/audio_files.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/ebook/ebook_files.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/ebook/ebook_reading.dart';
import 'package:chapterly/ebook/reader_style.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/book_file_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Copies by writing [content] to the target, or fails when told to.
class FakeEbookFiles implements EbookFiles {
  FakeEbookFiles({this.content = 'book', this.fail = false});

  final String content;
  final bool fail;
  final released = <String>[];

  @override
  Future<PickedFile?> pickBook() async => null;

  @override
  Future<int> copy(PickedFile picked, String path) async {
    if (fail) throw const FileSystemException('full');
    await File(path).writeAsString(content);
    return content.length;
  }

  @override
  Future<void> release(PickedFile picked) async =>
      released.add(picked.location);
}

EbookLink _link(String path, {EbookFormat format = EbookFormat.epub}) =>
    EbookLink(
      path: path,
      name: 'Emma.epub',
      bytes: 1200,
      format: format,
      addedAt: DateTime(2026, 10, 31),
    );

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('chapterly_ebook_');
  });

  tearDown(() async {
    EbookReading.library = null;
    EbookReading.files = null;
    EbookReading.booksDir = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('the reader opens EPUB and PDF files', () {
    expect(ebookFormatOf('Emma.EPUB'), EbookFormat.epub);
    expect(ebookFormatOf('notes.pdf'), EbookFormat.pdf);
    expect(ebookFormatOf('Emma.mobi'), isNull);
    expect(ebookFormatOf('epub'), isNull);
  });

  test('file sizes read like people say them', () {
    expect(formatFileSize(500), '500 bytes');
    expect(formatFileSize(2048), '2 KB');
    expect(formatFileSize(1258291), '1.2 MB');
    expect(formatFileSize(52428800), '50 MB');
  });

  test('the store keeps links, places, bookmarks, highlights and settings',
      () async {
    final file = File('${temp.path}/ebook_library.json');
    final library = await EbookLibrary.load(file);
    await library.setLink('b1', _link('${temp.path}/b1.epub'));
    await library.setPosition(
      'b1',
      const EbookPosition(locator: 'epubcfi(/6/8)', progress: 0.38),
    );
    await library.addBookmark(
      'b1',
      EbookBookmark(
        locator: 'epubcfi(/6/20)',
        progress: 0.7,
        label: 'Late',
        addedAt: DateTime(2026, 10, 31),
      ),
    );
    await library.addBookmark(
      'b1',
      EbookBookmark(
        locator: 'epubcfi(/6/4)',
        progress: 0.1,
        label: 'Early',
        addedAt: DateTime(2026, 10, 31),
      ),
    );
    // The same place twice is one bookmark.
    await library.addBookmark(
      'b1',
      EbookBookmark(
        locator: 'epubcfi(/6/4)',
        progress: 0.1,
        label: 'Again',
        addedAt: DateTime(2026, 10, 31),
      ),
    );
    await library.addHighlight(
      'b1',
      EbookHighlight(
        locator: 'epubcfi(/6/8,/1:0,/1:20)',
        text: 'handsome, clever, and rich',
        addedAt: DateTime(2026, 10, 31),
      ),
    );
    await library.setPrefs(
      const ReaderPrefs(theme: ReaderTheme.dark, fontSize: 22, scroll: true),
    );

    final again = await EbookLibrary.load(file);
    final link = again.linkFor('b1')!;
    expect(link.name, 'Emma.epub');
    expect(link.format, EbookFormat.epub);
    expect(link.position!.locator, 'epubcfi(/6/8)');
    expect(link.position!.progress, 0.38);
    // Bookmarks are in book order.
    expect([for (final b in link.bookmarks) b.label], ['Early', 'Late']);
    expect(link.highlights.single.text, 'handsome, clever, and rich');
    expect(again.prefs.theme, ReaderTheme.dark);
    expect(again.prefs.fontSize, 22);
    expect(again.prefs.scroll, isTrue);

    await again.removeBookmark('b1', 'epubcfi(/6/4)');
    await again.removeHighlight('b1', 'epubcfi(/6/8,/1:0,/1:20)');
    expect(again.linkFor('b1')!.bookmarks.single.label, 'Late');
    expect(again.linkFor('b1')!.highlights, isEmpty);

    final removed = await again.remove('b1');
    expect(removed?.path, '${temp.path}/b1.epub');
    expect(again.hasFile('b1'), isFalse);
  });

  test('a damaged store file loses only the links', () async {
    final file = File('${temp.path}/ebook_library.json');
    await file.writeAsString('not json');
    final library = await EbookLibrary.load(file);
    expect(library.hasFile('b1'), isFalse);
    expect(library.prefs, const ReaderPrefs());
  });

  test('reader settings stay within limits', () {
    expect(const ReaderPrefs().copyWith(fontSize: 99).fontSize,
        ReaderPrefs.maxFontSize);
    expect(const ReaderPrefs().copyWith(fontSize: 1).fontSize,
        ReaderPrefs.minFontSize);
    final junk = ReaderPrefs.fromJson({'theme': 'purple', 'fontSize': 'big'});
    expect(junk, const ReaderPrefs());
  });

  test('the current page follows the reader', () {
    // A PDF's own page.
    expect(
      currentPageFor(
        format: EbookFormat.pdf,
        progress: 0.5,
        bookPages: 300,
        pdfPage: 42,
      ),
      42,
    );
    // An EPUB: the same share of the printed pages.
    expect(
      currentPageFor(format: EbookFormat.epub, progress: 0.38, bookPages: 266),
      101,
    );
    expect(
      currentPageFor(format: EbookFormat.epub, progress: 0, bookPages: 266),
      1,
    );
    expect(
      currentPageFor(format: EbookFormat.epub, progress: 1.4, bookPages: 266),
      266,
    );
    // Nothing to go by.
    expect(
      currentPageFor(format: EbookFormat.epub, progress: 0.5, bookPages: null),
      isNull,
    );
  });

  test('adding a book file copies it and replaces the old copy', () async {
    final library = EbookLibrary();
    final files = FakeEbookFiles();
    final booksDir = Directory('${temp.path}/books');
    var stamp = 1000;
    DateTime now() => DateTime.fromMillisecondsSinceEpoch(stamp++);

    final first = await addBookFile(
      library: library,
      files: files,
      booksDir: booksDir,
      bookId: 'b1',
      picked: const PickedFile(location: 'content://a', name: 'Emma.epub'),
      now: now,
    );
    expect(first, isNull);
    final firstPath = library.linkFor('b1')!.path;
    expect(File(firstPath).existsSync(), isTrue);
    expect(library.linkFor('b1')!.bytes, 4);
    expect(files.released, ['content://a']);

    final second = await addBookFile(
      library: library,
      files: files,
      booksDir: booksDir,
      bookId: 'b1',
      picked: const PickedFile(location: 'content://b', name: 'Emma.pdf'),
      now: now,
    );
    expect(second, isNull);
    final link = library.linkFor('b1')!;
    expect(link.format, EbookFormat.pdf);
    expect(link.path, isNot(firstPath));
    expect(File(firstPath).existsSync(), isFalse);

    await removeBookFile(library, 'b1');
    expect(library.hasFile('b1'), isFalse);
    expect(File(link.path).existsSync(), isFalse);
  });

  test('a file the reader cannot open, or a failed copy, adds nothing',
      () async {
    final library = EbookLibrary();
    final booksDir = Directory('${temp.path}/books');
    final wrong = await addBookFile(
      library: library,
      files: FakeEbookFiles(),
      booksDir: booksDir,
      bookId: 'b1',
      picked: const PickedFile(location: 'content://a', name: 'Emma.mobi'),
    );
    expect(wrong, contains('EPUB and PDF'));
    expect(library.hasFile('b1'), isFalse);

    final failing = FakeEbookFiles(fail: true);
    final failed = await addBookFile(
      library: library,
      files: failing,
      booksDir: booksDir,
      bookId: 'b1',
      picked: const PickedFile(location: 'content://a', name: 'Emma.epub'),
    );
    expect(failed, isNotNull);
    expect(library.hasFile('b1'), isFalse);
    // The permission is let go of even when the copy fails.
    expect(failing.released, ['content://a']);
  });

  test('taps on the sides turn the page, in the middle show the tools', () {
    expect(tapZone(0.1), TapZone.back);
    expect(tapZone(0.5), TapZone.middle);
    expect(tapZone(0.9), TapZone.forward);
    expect(percentText(0.384), '38%');
  });

  test('the reader style wins over the book\'s own', () {
    final css = readerCss(
      const ReaderPrefs(font: ReaderFont.sans, lineSpacing: ReaderSpacing.large),
    );
    final body = css['body'] as Map;
    expect(body['font-family'], contains('sans-serif'));
    expect(body['font-family'], endsWith('!important'));
    expect(body['line-height'], '1.9 !important');
    expect(body['background'], '#f4ecd8 !important');
  });

  test('reading time joins the day\'s entry in the reading log', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(title: 'Emma', author: 'J', shelf: Shelf.inProgress);
    final id = repository.books.single.id;
    final day = DateTime(2026, 10, 31, 20);
    await repository.addReadingMinutes(id, day, 12);
    await repository.addReadingMinutes(id, day, 8);
    final log = repository.byId(id)!.readingLog;
    expect(log.single.minutes, 20);
    expect(log.single.pages, 0);
  });

  testWidgets('the Book file card offers to add a file, then to read it',
      (tester) async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(title: 'Emma', author: 'J', shelf: Shelf.inProgress);
    final book = repository.books.single;
    final library = EbookLibrary();
    EbookReading.library = library;
    EbookReading.files = FakeEbookFiles();
    EbookReading.booksDir = Directory('${temp.path}/books');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookFileCard(book: book, repository: repository),
        ),
      ),
    );
    expect(find.text('Add the book file'), findsOneWidget);

    await tester.runAsync(
      () => library.setLink(book.id, _link('${temp.path}/b1.epub')),
    );
    await tester.pump();
    expect(find.text('Emma.epub'), findsOneWidget);
    expect(find.text('Start reading'), findsOneWidget);

    await tester.runAsync(
      () => library.setPosition(
        book.id,
        const EbookPosition(locator: 'epubcfi(/6/8)', progress: 0.38),
      ),
    );
    await tester.pump();
    expect(find.text('Continue reading'), findsOneWidget);
    expect(find.text('38%'), findsOneWidget);
  });

  testWidgets('the Book file card is hidden without the reader',
      (tester) async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(title: 'Emma', author: 'J', shelf: Shelf.inProgress);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookFileCard(
            book: repository.books.single,
            repository: repository,
          ),
        ),
      ),
    );
    expect(find.text('Book file'), findsNothing);
  });
}
