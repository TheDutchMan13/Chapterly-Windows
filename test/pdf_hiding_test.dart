import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/pdf_hiding.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, String title, {List<String> tags = const []}) => Book(
      id: id,
      title: title,
      author: 'Writer',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026, 1, int.parse(id)),
      tags: tags,
      collections: const ['Mine'],
      updatedAt: DateTime(2026, 1, 1),
    );

EbookLink _link(EbookFormat format) => EbookLink(
      path: 'x',
      name: 'x',
      bytes: 1,
      format: format,
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('only books whose single file is a PDF and with no audio are hidden',
      () {
    final hidden = pdfOnlyBookIds(
      ebooks: {
        '1': _link(EbookFormat.pdf),
        '2': _link(EbookFormat.epub),
        '3': _link(EbookFormat.pdf),
      },
      hasAudio: (id) => id == '3',
    );
    expect(hidden, {'1'});
  });

  test('a linked PDF counts, but not next to an EPUB or another file', () {
    final hidden = pdfOnlyBookIds(
      ebooks: {'2': _link(EbookFormat.epub)},
      linked: {
        '1': r'D:\Books\Manual.PDF',
        '2': r'D:\Books\Same.pdf',
        '3': r'D:\Books\Novel.mobi',
        '4': r'D:\Audio\Story',
      },
      hasAudio: (_) => false,
    );
    expect(hidden, {'1'});
  });

  test('the setting is off at first and is remembered', () {
    final settings = AppSettings();
    expect(settings.hidePdfBooks, isFalse);
    settings.setHidePdfBooks(true);
    expect(settings.hidePdfBooks, isTrue);
  });

  test('hidden books leave shelves, search, collections and tags but stay saved',
      () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.replaceAll([
      _book('1', 'Manual', tags: ['guides']),
      _book('2', 'Novel', tags: ['fiction']),
    ]);
    var hide = false;
    repository.hiddenIds = () => hide ? {'1'} : const <String>{};

    expect(repository.booksOn(Shelf.forLater), hasLength(2));
    hide = true;
    expect(repository.booksOn(Shelf.forLater).map((b) => b.id), ['2']);
    expect(repository.booksOn(Shelf.forLater, query: 'Manual'), isEmpty);
    expect(repository.booksInCollection('Mine').map((b) => b.id), ['2']);
    expect(repository.allTags, ['fiction']);
    expect(repository.tagCounts, {'fiction': 1});
    // Still there for saving, syncing and backups.
    expect(repository.allBooks, hasLength(2));
    expect(repository.byId('1'), isNotNull);

    hide = false;
    expect(repository.booksOn(Shelf.forLater), hasLength(2));
    expect(repository.allTags, ['fiction', 'guides']);
  });
}
