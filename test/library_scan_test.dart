import 'dart:io';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/library_scan.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book(String id, String title, String author) => Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
    );

ScanItem _item(ScanKind kind, String name, {String title = '', String author = ''}) =>
    ScanItem(kind: kind, key: '$kind|$name', name: name, files: const [])
      ..title = title
      ..author = author;

void main() {
  group('groupAudiobooks', () {
    test('a folder of chapters is one audiobook', () {
      final units = groupAudiobooks([
        'Frank Herbert/Dune/01.mp3',
        'Frank Herbert/Dune/02.mp3',
      ]);
      expect(units, hasLength(1));
      expect(units.single.name, 'Dune');
      expect(units.single.folder, 'Frank Herbert');
      expect(units.single.files, hasLength(2));
      expect(units.single.nameOf('Frank Herbert/Dune/01.mp3'), '01.mp3');
    });

    test('disc folders belong to the book above them', () {
      final units = groupAudiobooks([
        'Dune/CD 1/01.mp3',
        'Dune/CD 2/01.mp3',
        'Emma/01.mp3',
      ]);
      expect(units.map((u) => u.name).toSet(), {'Dune', 'Emma'});
      final dune = units.firstWhere((u) => u.name == 'Dune');
      expect(dune.files, hasLength(2));
      expect(dune.nameOf('Dune/CD 2/01.mp3'), 'CD 2/01.mp3');
    });

    test('several m4b files in a folder are separate audiobooks', () {
      final units = groupAudiobooks(['Mix/a.m4b', 'Mix/b.m4b']);
      expect(units, hasLength(2));
      expect(units.every((u) => u.files.length == 1), isTrue);
    });

    test('loose files in the scanned folder are each their own', () {
      final units = groupAudiobooks(['a.m4b', 'b.mp3', 'notes.txt']);
      expect(units.map((u) => u.name), ['a.m4b', 'b.mp3']);
    });
  });

  group('planScan', () {
    final books = [
      _book('1', 'Dune', 'Frank Herbert'),
      _book('2', 'Emma', 'Jane Austen'),
    ];

    test('links a clear match', () {
      final plan = planScan(
        [_item(ScanKind.book, 'x.epub', title: 'Dune', author: 'Frank Herbert')],
        books,
        hasLink: (kind, id) => false,
      );
      expect(plan.single.outcome, ScanOutcome.link);
      expect(plan.single.book!.id, '1');
    });

    test('never replaces an existing link', () {
      final plan = planScan(
        [_item(ScanKind.book, 'x.epub', title: 'Dune', author: 'Frank Herbert')],
        books,
        hasLink: (kind, id) => id == '1',
      );
      expect(plan.single.outcome, ScanOutcome.alreadyLinked);
    });

    test('a second file for the same book is a duplicate', () {
      final plan = planScan(
        [
          _item(ScanKind.book, 'a.epub', title: 'Dune', author: 'Frank Herbert'),
          _item(ScanKind.book, 'b.epub', title: 'Dune', author: 'Frank Herbert'),
        ],
        books,
        hasLink: (kind, id) => false,
      );
      expect(plan[0].outcome, ScanOutcome.link);
      expect(plan[1].outcome, ScanOutcome.duplicate);
    });

    test('an epub and an audiobook of one book both link', () {
      final plan = planScan(
        [
          _item(ScanKind.book, 'a.epub', title: 'Dune', author: 'Frank Herbert'),
          _item(ScanKind.audiobook, 'Dune', title: 'Dune', author: 'Frank Herbert'),
        ],
        books,
        hasLink: (kind, id) => false,
      );
      expect(plan.every((d) => d.outcome == ScanOutcome.link), isTrue);
    });

    test('unknown files go to review', () {
      final plan = planScan(
        [_item(ScanKind.book, 'Something Else.epub', title: 'Something Else')],
        books,
        hasLink: (kind, id) => false,
      );
      expect(plan.single.outcome, ScanOutcome.review);
      expect(plan.single.matches, isEmpty);
    });
  });

  group('looking in folders', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('scan_test'));
    tearDown(() => temp.deleteSync(recursive: true));

    File make(String path) {
      final file = File('${temp.path}/$path')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      return file;
    }

    test('finds epub and pdf files in subfolders and skips settled ones', () async {
      make('Frank Herbert/Dune.epub');
      make('Emma.PDF');
      make('notes.txt');
      final all = await findBookFiles(temp.path, {});
      expect(all.map((i) => i.name).toSet(), {'Dune.epub', 'Emma.PDF'});
      final settled = {all.first.key};
      final rest = await findBookFiles(temp.path, settled);
      expect(rest, hasLength(1));
    });

    test('finds audiobooks as folders', () async {
      make('Dune/01.mp3');
      make('Dune/02.mp3');
      make('Emma.m4b');
      final found = await findAudiobooks(temp.path, {});
      expect(found.map((i) => i.name).toSet(), {'Dune', 'Emma.m4b'});
      final dune = found.firstWhere((i) => i.name == 'Dune');
      expect(dune.files.map((f) => f.name), ['01.mp3', '02.mp3']);
      expect(await findAudiobooks(temp.path, {for (final i in found) i.key}),
          isEmpty);
    });

    test('memory is kept in its file', () async {
      final file = File('${temp.path}/state.json');
      final memory = ScanMemory(file: file)
        ..settled.add('a')
        ..reported.add('b');
      await memory.save();
      final again = await ScanMemory.load(file);
      expect(again.settled, {'a'});
      expect(again.reported, {'b'});
    });
  });

  group('settings', () {
    test('folders and switch are kept', () async {
      SharedPreferences.setMockInitialValues({});
      var settings = await AppSettings.load();
      expect(settings.scanOnOpen, isTrue);
      expect(settings.hasScanFolders, isFalse);
      settings
        ..setBooksFolder('C:\\Books')
        ..setScanOnOpen(false);
      settings = await AppSettings.load();
      expect(settings.booksFolder, 'C:\\Books');
      expect(settings.scanOnOpen, isFalse);
      expect(settings.hasScanFolders, isTrue);
      settings.setBooksFolder(null);
      settings = await AppSettings.load();
      expect(settings.booksFolder, isNull);
    });
  });
}
