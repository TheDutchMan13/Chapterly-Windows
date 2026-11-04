import 'dart:convert';

import 'package:chapterly/data/auto_tag.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/claude_client.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Book _book(String id, String title, String author, [List<String> tags = const []]) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      tags: tags,
    );

SubjectLookup _subjects(Map<String, List<String>> byTitle) =>
    (book) async => byTitle[book.title] ?? const [];

void main() {
  group('planBookTags', () {
    test('a sure Open Library match is ticked and Claude is not asked',
        () async {
      final library = [
        _book('1', 'Dune', 'Frank Herbert', ['Space opera']),
        _book('2', 'Hyperion', 'Dan Simmons'),
      ];
      var asked = 0;
      final plan = await planBookTags(
        library[1],
        library,
        subjects: _subjects({'Hyperion': ['Space opera']}),
        claude: (b, s, t) async {
          asked++;
          return ['Anything'];
        },
      );
      expect(asked, 0);
      expect(plan.checkedTags, ['Space opera']);
      expect(plan.proposals.single.source, TagSource.openLibrary);
    });

    test('Claude fills in when Open Library has no sure tag', () async {
      final library = [
        _book('1', 'Dune', 'Frank Herbert', ['Sci-Fi']),
        _book('2', 'Firefly Tales', 'Someone'),
      ];
      List<String>? sentSubjects;
      List<String>? sentTags;
      final plan = await planBookTags(
        library[1],
        library,
        subjects: _subjects({'Firefly Tales': ['Space westerns']}),
        claude: (b, s, t) async {
          sentSubjects = s;
          sentTags = t;
          return ['sci-fi', 'Space Westerns', 'Cowboys in space'];
        },
      );
      // Claude is grounded on the Open Library subjects and your tags.
      expect(sentSubjects, ['Space westerns']);
      expect(sentTags, ['Sci-Fi']);
      // Your tag, in your spelling, is ticked; new names are not.
      final byTag = {for (final p in plan.proposals) p.tag: p};
      expect(byTag['Sci-Fi']!.checked, isTrue);
      expect(byTag['Sci-Fi']!.source, TagSource.claude);
      expect(byTag['Sci-Fi']!.isNew, isFalse);
      expect(byTag['Cowboys in space']!.checked, isFalse);
      expect(byTag['Cowboys in space']!.isNew, isTrue);
      // Claude's "Space Westerns" is the Open Library one, not a second chip.
      expect(
        plan.proposals.where((p) => p.tag.toLowerCase() == 'space westerns'),
        hasLength(1),
      );
      expect(plan.checkedTags, ['Sci-Fi']);
    });

    test('an unreadable answer costs only that book its Claude tags', () async {
      final library = [
        _book('1', 'A', 'X'),
        _book('2', 'B', 'Y'),
        _book('3', 'C', 'Z'),
      ];
      final asked = <String>[];
      final run = await planTags(
        library,
        library,
        subjects: _subjects({}),
        claude: (b, s, t) async {
          asked.add(b.title);
          if (b.title == 'A') {
            throw const ClaudeUnreadable('no text');
          }
          return ['Dragons'];
        },
      );
      expect(asked, ['A', 'B', 'C']);
      expect(run.claudeProblem, isNull);
      expect(run.plans[0].note, 'Claude\'s answer could not be read');
      expect(run.plans[1].proposals.map((p) => p.tag), contains('Dragons'));
    });

    test('a book nobody knows gets nothing, with the reason', () async {
      final library = [
        _book('1', 'Dune', 'Frank Herbert', ['Sci-Fi']),
        _book('2', 'My Diary', 'Me'),
      ];
      final plan = await planBookTags(
        library[1],
        library,
        subjects: _subjects({}),
        claude: (b, s, t) async => parseTagReply('{"known": false, "tags": []}'),
      );
      expect(plan.proposals, isEmpty);
      expect(plan.note, 'Claude does not know this book');
    });

    test('without Claude the reason says what Open Library had', () async {
      final library = [_book('1', 'My Diary', 'Me')];
      final plan = await planBookTags(
        library[0],
        library,
        subjects: _subjects({}),
      );
      expect(plan.note, 'Open Library has nothing on this book');
    });
  });

  group('planTags', () {
    test('when Claude fails the rest go on with Open Library only', () async {
      final library = [
        _book('1', 'Dune', 'Frank Herbert', ['Sci-Fi']),
        _book('2', 'A', 'X'),
        _book('3', 'B', 'Y'),
      ];
      var asked = 0;
      final run = await planTags(
        [library[1], library[2]],
        library,
        subjects: _subjects({}),
        claude: (b, s, t) async {
          asked++;
          throw const ClaudeFailure('Claude did not accept the API key.');
        },
      );
      expect(asked, 1);
      expect(run.plans, hasLength(2));
      expect(run.claudeProblem, 'Claude did not accept the API key.');
      expect(run.claudeCalls, 1);
    });

    test('stops when asked and says how far it got', () async {
      final library = [
        _book('1', 'A', 'X'),
        _book('2', 'B', 'Y'),
        _book('3', 'C', 'Z'),
      ];
      final seen = <int>[];
      var stop = false;
      final run = await planTags(
        library,
        library,
        subjects: (book) async {
          if (book.title == 'B') stop = true;
          return const [];
        },
        stopped: () => stop,
        onProgress: (done, total, book) => seen.add(done),
      );
      expect(run.plans.map((p) => p.book.title), ['A', 'B']);
      expect(seen.last, 2);
    });
  });

  group('parseTagReply', () {
    test('reads tags, also inside a code block', () {
      expect(parseTagReply('{"known": true, "tags": ["Fantasy", "Dragons"]}'),
          ['Fantasy', 'Dragons']);
      expect(
        parseTagReply('```json\n{"known": true, "tags": ["Fantasy"]}\n```'),
        ['Fantasy'],
      );
    });

    test('nothing when unknown or unreadable', () {
      expect(parseTagReply('{"known": false, "tags": ["Guess"]}'), isEmpty);
      expect(parseTagReply('I am not sure.'), isEmpty);
      expect(parseTagReply('{"tags": "Fantasy"}'), isEmpty);
    });

    test('no repeats, no blanks, at most five', () {
      final tags = parseTagReply(
        '{"known": true, "tags": ["A", "a", " ", "B", "C", "D", "E", "F"]}',
      );
      expect(tags, ['A', 'B', 'C', 'D', 'E']);
    });
  });

  test('the prompt has the book, the subjects and your tags', () {
    final prompt = tagPrompt(
      _book('1', 'Dune', 'Frank Herbert'),
      ['Space opera'],
      ['Sci-Fi', 'Classics'],
    );
    expect(prompt, contains('"Dune" by Frank Herbert'));
    expect(prompt, contains('Open Library subjects: Space opera'));
    expect(prompt, contains("The reader's tags: Sci-Fi, Classics"));
    expect(prompt, contains('known false'));
  });

  test('tagNames lists your tags, the most used first', () {
    final names = tagNames([
      _book('1', 'A', 'X', ['Fantasy', 'Classics']),
      _book('2', 'B', 'X', ['fantasy']),
    ]);
    expect(names, ['Fantasy', 'Classics']);
  });

  group('runTagTest', () {
    final library = [
      _book('1', 'Dune', 'Frank Herbert', ['Space opera']),
      _book('2', 'Emma', 'Jane Austen', ['Romance']),
      _book('3', 'Other', 'Zed', ['Space opera', 'Romance']),
    ];
    final subjects = _subjects({
      'Dune': ['Space opera'],
      'Other': ['Romance'],
    });

    test('scores Open Library against your own tags', () async {
      final report = await runTagTest(library, subjects: subjects);
      final score = report.openLibrary;
      expect(score.books, 3);
      expect(score.yourTags, 4);
      expect(score.found, 2);
      expect(score.suggested, 2);
      expect(score.right, 2);
      expect(score.booksHit, 2);
      expect(score.booksEmpty, 1);
      expect(report.withClaude, isNull);
    });

    test('Claude is only asked about the books Open Library missed',
        () async {
      final asked = <String>[];
      final report = await runTagTest(
        library,
        subjects: subjects,
        claude: (b, s, t) async {
          asked.add(b.title);
          return ['Romance'];
        },
      );
      expect(asked, ['Emma']);
      expect(report.claudeCalls, 1);
      expect(report.withClaude!.found, 3);
      expect(report.withClaude!.booksEmpty, 0);
      // Open Library alone is unchanged.
      expect(report.openLibrary.found, 2);
    });

    test('picks a spread of at most the asked number of books', () {
      final many = [
        for (var i = 0; i < 120; i++) _book('$i', 'Book $i', 'A', ['T']),
        _book('x', 'Untagged', 'A'),
      ];
      final picked = pickTestBooks(many, count: 50);
      expect(picked, hasLength(50));
      expect(picked.every((b) => b.tags.isNotEmpty), isTrue);
    });
  });

  test('addTagsToBooks adds each book its own tags, without repeats',
      () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.replaceAll([
      _book('1', 'A', 'X', ['Fantasy']),
      _book('2', 'B', 'Y'),
    ]);
    await repository.addTagsToBooks({
      '1': ['fantasy', 'Dragons'],
      '2': ['Classics', ' '],
    });
    expect(repository.byId('1')!.tags, ['Fantasy', 'Dragons']);
    expect(repository.byId('2')!.tags, ['Classics']);
  });

  group('ClaudeClient', () {
    test('sends the key, the API version and no temperature', () async {
      late http.Request sent;
      final client = ClaudeClient(
        apiKey: 'test-key',
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': '{"known": true, "tags": ["Fantasy"]}'},
              ],
            }),
            200,
          );
        }),
      );
      final answer = await client.ask(system: 'Be brief.', prompt: 'Hello');
      expect(answer, contains('Fantasy'));
      expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(sent.headers['authorization'], 'Bearer test-key');
      expect(sent.headers['anthropic-version'], claudeApiVersion);
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], defaultClaudeModel);
      expect(body['system'], 'Be brief.');
      expect(body.containsKey('temperature'), isFalse);
    });

    test('a wrong key gives a clear message', () async {
      final client = ClaudeClient(
        apiKey: 'bad',
        client: MockClient((_) async => http.Response(
              '{"type":"error","error":{"type":"authentication_error",'
              '"message":"invalid x-api-key"}}',
              401,
            )),
      );
      await expectLater(
        client.ask(system: '', prompt: 'x'),
        throwsA(isA<ClaudeFailure>().having(
          (f) => f.message,
          'message',
          contains('did not accept the API key'),
        )),
      );
    });

    test('an answer with no text is unreadable, not a failure', () async {
      final client = ClaudeClient(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'content': [
                  {'type': 'thinking', 'thinking': '...'},
                ],
                'stop_reason': 'max_tokens',
              }),
              200,
            )),
      );
      await expectLater(
        client.ask(system: '', prompt: 'x'),
        throwsA(isA<ClaudeUnreadable>()),
      );
    });

    test('the tag picker reads Claude\'s JSON', () async {
      final picker = claudeTagPicker(ClaudeClient(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'content': [
                  {'type': 'text', 'text': '{"known": true, "tags": ["Dragons"]}'},
                ],
              }),
              200,
            )),
      ));
      expect(
        await picker(_book('1', 'A', 'X'), const [], const ['Dragons']),
        ['Dragons'],
      );
    });
  });
}
