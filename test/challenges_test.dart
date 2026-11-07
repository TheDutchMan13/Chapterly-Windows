import 'package:chapterly/data/challenges.dart';
import 'package:chapterly/data/hardcover_client.dart';
import 'package:chapterly/data/series.dart';
import 'package:chapterly/data/series_check.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Book _read(
  String id, {
  required DateTime finished,
  String author = 'Author',
  int? pages,
  List<String> tags = const [],
  String? series,
  int? number,
  Shelf shelf = Shelf.finished,
}) =>
    Book(
      id: id,
      title: 'Book $id',
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026),
      finishedAt: finished,
      pages: pages,
      tags: tags,
      series: series,
      seriesNumber: number,
    );

ReadingChallenge _challenge(ChallengeKind kind, {int target = 4, String? tag}) =>
    ReadingChallenge(
      id: 'c1',
      name: 'Spring',
      kind: kind,
      target: target,
      start: DateTime(2027, 3, 1),
      end: DateTime(2027, 5, 31),
      tag: tag,
    );

void main() {
  final books = [
    _read('a', finished: DateTime(2027, 2, 28), pages: 100),
    _read('b', finished: DateTime(2027, 3, 1), pages: 200, tags: ['Horror']),
    _read('c', finished: DateTime(2027, 5, 31, 23), pages: 300, author: 'Other'),
    _read('d', finished: DateTime(2027, 6, 1), pages: 400),
    _read('e', finished: DateTime(2027, 4, 2), shelf: Shelf.inProgress),
  ];

  group('challenges', () {
    test('count books finished between the dates, both days included', () {
      final p = challengeProgress(_challenge(ChallengeKind.books), books,
          now: DateTime(2027, 7, 1));
      expect(p.count, 2);
      expect(p.ended, isTrue);
      expect(p.describe(), '2 of 4 books · ended May 31');
    });

    test('pages, tags and different authors', () {
      expect(
        challengeProgress(_challenge(ChallengeKind.pages), books).count,
        500,
      );
      expect(
        challengeProgress(
          _challenge(ChallengeKind.tag, tag: 'horror'),
          books,
        ).count,
        1,
      );
      expect(
        challengeProgress(_challenge(ChallengeKind.authors), books).count,
        2,
      );
    });

    test('days left and pace while it runs', () {
      final p = challengeProgress(
        _challenge(ChallengeKind.books, target: 92),
        books,
        now: DateTime(2027, 3, 10),
      );
      // Day 10 of 92: 10 expected, 2 finished in the range.
      expect(p.daysLeft, 83);
      expect(p.ahead, -8);
      expect(p.describe(), contains('83 days left · 8 behind pace'));
      final before = challengeProgress(
        _challenge(ChallengeKind.books),
        books,
        now: DateTime(2027, 1, 1),
      );
      expect(before.notStarted, isTrue);
      expect(before.describe(), contains('starts Mar 1'));
    });

    test('saved and read back; bad entries are left out', () {
      final challenge = _challenge(ChallengeKind.tag, tag: 'Horror');
      final back = decodeChallenges(encodeChallenges([challenge]));
      expect(back, hasLength(1));
      expect(back.single.tag, 'Horror');
      expect(back.single.start, DateTime(2027, 3, 1));
      expect(decodeChallenges('[{"id":"x"}]'), isEmpty);
      expect(decodeChallenges('nonsense'), isEmpty);
    });
  });

  group('checking every series', () {
    test('missing books, and which come after the last one you have', () {
      final mine = [
        _read('1', finished: DateTime(2027), series: 'Saga', number: 1),
        _read('3', finished: DateTime(2027), series: 'Saga', number: 3),
      ];
      final saga = seriesOverview(mine).single;
      final gap = SeriesGap(
        series: saga,
        missing: missingFrom(saga, const [
          HardcoverSeriesBook(number: 4, title: 'Four'),
          HardcoverSeriesBook(number: 1, title: 'One'),
          HardcoverSeriesBook(number: 2, title: 'Two'),
          HardcoverSeriesBook(number: 3, title: 'Three'),
        ]),
      );
      expect([for (final b in gap.missing) b.number], [2, 4]);
      expect(gap.highestOwned, 3);
      expect([for (final b in gap.newer) b.title], ['Four']);
    });
  });
}
