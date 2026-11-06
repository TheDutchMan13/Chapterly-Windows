import 'dart:io';

import 'package:chapterly/data/linked_files.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/linked_file_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book() => Book(
      id: '1',
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
    );

void main() {
  test('links are saved, reloaded and removed', () async {
    final dir = await Directory.systemTemp.createTemp('linked');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/sub/linked_files.json');
    final links = await LinkedFiles.load(file);
    expect(links.pathFor('1'), isNull);
    await links.link('1', r'D:\Books\Dune.mobi');
    await links.link('2', r'E:\Audio\Wool');

    final again = await LinkedFiles.load(file);
    expect(again.pathFor('1'), r'D:\Books\Dune.mobi');
    expect(again.count, 2);
    await again.unlink('1');
    expect((await LinkedFiles.load(file)).pathFor('1'), isNull);
    expect((await LinkedFiles.load(file)).pathFor('2'), r'E:\Audio\Wool');
  });

  test('a damaged file gives no links and names are cut from paths', () async {
    final dir = await Directory.systemTemp.createTemp('linked');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/linked_files.json')
      ..writeAsStringSync('not json');
    expect((await LinkedFiles.load(file)).count, 0);
    expect(linkedName(r'D:\Books\Dune.mobi'), 'Dune.mobi');
    expect(linkedName(r'E:\Audio\Wool\'), 'Wool');
    expect(linkedName('/home/me/a.epub'), 'a.epub');
  });

  testWidgets('link a file, open it, and see when it is missing',
      (tester) async {
    final dir = await Directory.systemTemp.createTemp('linked');
    addTearDown(() => dir.delete(recursive: true));
    final real = File('${dir.path}/Dune.mobi')..writeAsStringSync('x');
    final links = LinkedFiles.inMemory();
    final opened = <String>[];
    var picked = real.path;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LinkedFileCard(
            book: _book(),
            links: links,
            pickFile: () async => picked,
            pickFolder: () async => null,
            open: (path) async {
              opened.add(path);
              return true;
            },
            showInExplorer: (_) async {},
          ),
        ),
      ),
    ));
    expect(find.text('Link a file'), findsOneWidget);
    expect(find.text('Open'), findsNothing);

    await tester.tap(find.text('Link a file'));
    await tester.pumpAndSettle();
    expect(links.pathFor('1'), real.path);
    expect(find.text('Dune.mobi'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, [real.path]);

    real.deleteSync();
    picked = '';
    links.link('1', real.path);
    await tester.pumpAndSettle();
    expect(find.textContaining('Not found'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('the card is hidden when links are not set up', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LinkedFileCard(book: _book())),
    ));
    expect(find.text('On your drive'), findsNothing);
  });
}
