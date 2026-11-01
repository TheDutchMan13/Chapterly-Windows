import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/saved_filters.dart';
import 'package:chapterly/data/series.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book(
  String id, {
  String title = 'T',
  String author = 'A',
  String? series,
  int? number,
  Shelf shelf = Shelf.forLater,
  List<String> tags = const [],
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026),
      series: series,
      seriesNumber: number,
      tags: tags,
    );

void main() {
  group('series', () {
    test('finds missing numbers, the next book and the main author', () {
      final overview = seriesOverview([
        _book('1', series: 'Dune', number: 1, shelf: Shelf.finished,
            author: 'Frank Herbert'),
        _book('3', series: 'dune ', number: 3, author: 'Frank Herbert'),
        _book('5', series: 'Dune', number: 5, author: 'Brian Herbert'),
        _book('x', series: 'Dune', author: 'Frank Herbert'),
        _book('n'),
      ]);
      expect(overview, hasLength(1));
      final dune = overview.single;
      expect(dune.name, 'Dune');
      expect(dune.author, 'Frank Herbert');
      expect([for (final b in dune.books) b.seriesNumber], [1, 3, 5]);
      expect(dune.missing, [2, 4]);
      expect(dune.unnumbered.single.id, 'x');
      expect(dune.next!.id, '3');
      expect(dune.finished, 1);
      expect(dune.total, 4);
      expect(dune.complete, isFalse);
    });

    test('books in the trash are left out', () {
      final trashed = _book('1', series: 'S', number: 1)
          .copyWith(deletedAt: () => DateTime(2026));
      expect(seriesOverview([trashed]), isEmpty);
    });
  });

  group('saved filters', () {
    test('survive saving and loading', () {
      const filter = SavedFilter(
        name: 'Unread fantasy',
        tags: {'fantasy'},
        excludedTags: {'dnf'},
        matchAllTags: false,
        formats: {BookFormat.ebook},
        favoritesOnly: true,
        finishYear: 2025,
        query: 'dragon',
      );
      final back = decodeSavedFilters(encodeSavedFilters([filter])).single;
      expect(back.name, 'Unread fantasy');
      expect(back.tags, {'fantasy'});
      expect(back.excludedTags, {'dnf'});
      expect(back.matchAllTags, isFalse);
      expect(back.formats, {BookFormat.ebook});
      expect(back.favoritesOnly, isTrue);
      expect(back.finishYear, 2025);
      expect(back.query, 'dragon');
      expect(back.describe(), contains('fantasy'));
    });

    test('bad saved text gives no filters', () {
      expect(decodeSavedFilters('nope'), isEmpty);
      expect(decodeSavedFilters('[{"name": ""}, 3]'), isEmpty);
    });
  });

  group('tags', () {
    late BookRepository repository;

    setUp(() async {
      repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.add(
          title: 'A', author: 'x', shelf: Shelf.forLater, tags: ['scifi']);
      await repository.add(
          title: 'B',
          author: 'x',
          shelf: Shelf.forLater,
          tags: ['scifi', 'Sci-Fi']);
      await repository.add(
          title: 'C', author: 'x', shelf: Shelf.forLater, tags: ['other']);
    });

    test('counts books per tag', () {
      expect(repository.tagCounts, {'scifi': 2, 'Sci-Fi': 1, 'other': 1});
    });

    test('renaming into an existing tag merges them', () async {
      await repository.renameTag('scifi', 'Sci-Fi');
      expect(repository.tagCounts, {'Sci-Fi': 2, 'other': 1});
      final b = repository.books.firstWhere((book) => book.title == 'B');
      expect(b.tags, ['Sci-Fi']);
    });

    test('deleting takes the tag off every book', () async {
      await repository.deleteTag('scifi');
      expect(repository.tagCounts, {'Sci-Fi': 1, 'other': 1});
    });

    test('settings follow a renamed or deleted tag', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      settings.setTagGoal(2026, 'scifi', 5);
      settings.setSavedFilters(const [
        SavedFilter(name: 'S', tags: {'scifi', 'other'}),
      ]);
      settings.renameTagEverywhere('scifi', 'Sci-Fi');
      expect(settings.tagGoalsFor(2026), {'Sci-Fi': 5});
      expect(settings.savedFilters.single.tags, {'Sci-Fi', 'other'});
      settings.renameTagEverywhere('other', null);
      expect(settings.savedFilters.single.tags, {'Sci-Fi'});
      final again = await AppSettings.load();
      expect(again.savedFilters.single.tags, {'Sci-Fi'});
      expect(again.tagGoalsFor(2026), {'Sci-Fi': 5});
    });

    test('the Library goal can be hidden and shown again', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.goalOnLibrary, isTrue);
      settings.setGoalOnLibrary(false);
      expect((await AppSettings.load()).goalOnLibrary, isFalse);
    });
  });
}
