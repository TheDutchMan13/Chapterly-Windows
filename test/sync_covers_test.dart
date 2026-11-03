import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/data/sync_three_way.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

String _picture(String seed, [int size = 3000]) =>
    'data:image/jpeg;base64,${seed * size}';

Book _book(String id, {String? cover}) => Book(
      id: id,
      title: 'Book $id',
      author: 'A',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      coverUrl: cover,
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('cover names', () {
    test('the same picture always has the same name', () {
      final a = coverHash(_picture('a'));
      expect(coverHash(_picture('a')), a);
      expect(coverHash(_picture('b')), isNot(a));
      expect(isCoverHash(a), isTrue);
      expect(a, hasLength(32));
    });

    test('a reference names its cover, and only a real one does', () {
      final hash = coverHash(_picture('a'));
      expect(hashOfCoverRef(coverRef(hash)), hash);
      expect(hashOfCoverRef('cover:nope'), isNull);
      expect(hashOfCoverRef('https://example.com/cover.jpg'), isNull);
      expect(hashOfCoverRef(null), isNull);
      expect(hashOfCoverRef('cover:${hash.toUpperCase()}'), isNull);
    });
  });

  group('swapping pictures for references', () {
    test('a picture becomes a reference and comes back', () {
      final picture = _picture('a');
      final pool = CoverPool();
      final refs = withCoverRefs([_book('1', cover: picture)], pool);
      expect(refs.single.coverUrl, startsWith(coverRefPrefix));
      expect(refs.single.coverUrl!.length, lessThan(60));
      expect(pool.length, 1);
      final back = withCoverPictures(refs, pool);
      expect(back.single.coverUrl, picture);
    });

    test('web addresses and missing covers are left alone', () {
      final pool = CoverPool();
      final books = [
        _book('1', cover: 'https://example.com/c.jpg'),
        _book('2'),
      ];
      expect(withCoverRefs(books, pool).map((b) => b.coverUrl),
          ['https://example.com/c.jpg', null]);
      expect(pool.length, 0);
      expect(withCoverPictures(books, pool).map((b) => b.coverUrl),
          ['https://example.com/c.jpg', null]);
    });

    test('two books with the same picture share one', () {
      final pool = CoverPool();
      final refs = withCoverRefs([
        _book('1', cover: _picture('a')),
        _book('2', cover: _picture('a')),
      ], pool);
      expect(refs[0].coverUrl, refs[1].coverUrl);
      expect(pool.length, 1);
    });

    test('a reference with no picture is never turned into a cover', () {
      final ref = coverRef(coverHash(_picture('a')));
      final books = [_book('1', cover: ref)];
      final pool = CoverPool();
      expect(missingCovers(books, pool), [coverHash(_picture('a'))]);
      expect(
        () => withCoverPictures(books, pool),
        throwsA(isA<MissingCovers>()),
      );
    });

    test('the names a library refers to', () {
      final pool = CoverPool();
      final refs = withCoverRefs([
        _book('1', cover: _picture('a')),
        _book('2', cover: _picture('b')),
        _book('3', cover: _picture('a')),
      ], pool);
      expect(coverHashesOf(refs), hasLength(2));
      expect(missingCovers(refs, CoverPool()), hasLength(2));
      expect(missingCovers(refs, pool), isEmpty);
    });
  });

  group('a picture from another device', () {
    test('is kept when it has the name it was sent under', () {
      final picture = _picture('a');
      final pool = CoverPool()..put(coverHash(picture), picture);
      expect(pool[coverHash(picture)], picture);
    });

    test('is refused under another name, or when it is not a picture', () {
      final pool = CoverPool();
      final other = coverHash(_picture('b'));
      expect(() => pool.put(other, _picture('a')), throwsFormatException);
      final text = 'hello';
      expect(() => pool.put(coverHash(text), text), throwsFormatException);
      expect(() => pool.put('nope', _picture('a')), throwsFormatException);
      expect(pool.length, 0);
    });
  });

  group('the copy of the last sync', () {
    test('a picture saved in it by an older app becomes a reference', () {
      final picture = _picture('a');
      final saved = {'id': '1', 'title': 'T', 'coverUrl': picture};
      final fixed = jsonWithCoverRef(saved);
      expect(fixed['coverUrl'], coverRef(coverHash(picture)));
      expect(fixed['title'], 'T');
      expect(jsonWithCoverRef({'id': '2', 'coverUrl': 'https://x/y.jpg'})['coverUrl'],
          'https://x/y.jpg');
      expect(jsonWithCoverRef({'id': '3'}).containsKey('coverUrl'), isFalse);
    });

    test('is kept with references, so it stays small', () async {
      final base = SyncBase();
      await base.save([_book('1', cover: _picture('a', 50000))]);
      final saved = base.books['1']!['coverUrl'] as String;
      expect(saved, startsWith(coverRefPrefix));
    });
  });

  test('a few at a time, and all of them', () async {
    var running = 0;
    var most = 0;
    final done = <int>[];
    await forEachLimited(List.generate(20, (i) => i), (i) async {
      running++;
      if (running > most) most = running;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      running--;
      done.add(i);
    }, at: 3);
    expect(done..sort(), List.generate(20, (i) => i));
    expect(most, lessThanOrEqualTo(3));
  });
}
