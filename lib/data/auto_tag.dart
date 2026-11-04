import 'dart:convert';

import '../models/book.dart';
import 'claude_client.dart';
import 'tag_suggest.dart';

// Windows app only.

/// Where a proposed tag came from.
enum TagSource { openLibrary, claude }

/// A tag offered for a book. [checked] is whether it will be added; the
/// sure ones start checked, new tag names start unchecked.
class TagProposal {
  TagProposal({
    required this.tag,
    required this.source,
    required this.isNew,
    required this.checked,
    this.reason = '',
  });

  final String tag;
  final TagSource source;

  /// Not one of your tags yet.
  final bool isNew;
  bool checked;
  final String reason;
}

/// What was found for one book.
class TagPlan {
  TagPlan({required this.book, required this.proposals, this.note});

  final Book book;
  final List<TagProposal> proposals;

  /// Why nothing was found, when [proposals] is empty.
  final String? note;

  List<String> get checkedTags => [
        for (final p in proposals)
          if (p.checked) p.tag,
      ];
}

/// The tags found for a list of books, and what went wrong with Claude, if
/// anything (the rest then went on without it).
class TagRun {
  const TagRun({required this.plans, this.claudeProblem, this.claudeCalls = 0});

  final List<TagPlan> plans;
  final String? claudeProblem;
  final int claudeCalls;
}

/// Open Library's subjects for a book.
typedef SubjectLookup = Future<List<String>> Function(Book book);

/// Asks Claude (or a stand-in in tests) for tags. Empty when it does not
/// know the book well enough.
typedef TagPicker = Future<List<String>> Function(
  Book book,
  List<String> subjects,
  List<String> yourTags,
);

/// At most this many tags per book.
const maxTagsPerBook = 5;

/// An Open Library match this good is added without asking.
const _sureScore = 0.8;

/// Your tags, the most used first, in your spelling.
List<String> tagNames(List<Book> library) {
  final counts = <String, int>{};
  final spelling = <String, String>{};
  for (final book in library) {
    if (book.deletedAt != null) continue;
    for (final tag in book.tags) {
      final key = tag.trim().toLowerCase();
      if (key.isEmpty) continue;
      spelling.putIfAbsent(key, () => tag.trim());
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return [for (final key in keys) spelling[key]!];
}

/// Finds tags for one book: Open Library first; Claude ([claude]) only when
/// Open Library gave no sure tag.
Future<TagPlan> planBookTags(
  Book book,
  List<Book> library, {
  required SubjectLookup subjects,
  TagPicker? claude,
  List<String>? yourTags,
}) async {
  List<String> found;
  try {
    found = await subjects(book);
  } catch (_) {
    found = const [];
  }
  final proposals = [
    for (final s in suggestTags(
      book,
      library,
      subjects: found,
      limit: maxTagsPerBook,
      newTags: 2,
    ))
      TagProposal(
        tag: s.tag,
        source: TagSource.openLibrary,
        isNew: s.isNew,
        checked: !s.isNew && s.score >= _sureScore,
        reason: s.reason,
      ),
  ];
  if (proposals.any((p) => p.checked) || claude == null) {
    return TagPlan(
      book: book,
      proposals: proposals,
      note: proposals.isEmpty
          ? (found.isEmpty
              ? 'Open Library has nothing on this book'
              : 'None of the Open Library subjects fit your tags')
          : null,
    );
  }

  final names = yourTags ?? tagNames(library);
  final known = {for (final name in names) name.toLowerCase(): name};
  // A failure with the key or the account (ClaudeFailure) goes up to the
  // caller, which stops asking Claude. An unreadable answer only costs this
  // book its Claude tags.
  List<String> picked;
  try {
    picked = await claude(book, found, names);
  } on ClaudeUnreadable {
    return TagPlan(
      book: book,
      proposals: proposals,
      note: 'Claude\'s answer could not be read',
    );
  }
  final have = {for (final p in proposals) p.tag.toLowerCase()};
  for (final raw in picked.take(maxTagsPerBook)) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty || have.contains(key)) {
      // Claude agrees with an Open Library tag: now it is sure.
      for (final p in proposals) {
        if (p.tag.toLowerCase() == key && !p.isNew) p.checked = true;
      }
      continue;
    }
    have.add(key);
    final yours = known[key];
    proposals.add(TagProposal(
      tag: yours ?? raw.trim(),
      source: TagSource.claude,
      isNew: yours == null,
      checked: yours != null,
      reason: yours == null ? 'New tag, from Claude' : 'Claude',
    ));
  }
  return TagPlan(
    book: book,
    proposals: proposals,
    note: proposals.isEmpty ? 'Claude does not know this book' : null,
  );
}

/// Finds tags for [books], one after another. When Claude fails (a wrong
/// key, no credit) the rest go on with Open Library only.
Future<TagRun> planTags(
  List<Book> books,
  List<Book> library, {
  required SubjectLookup subjects,
  TagPicker? claude,
  void Function(int done, int total, Book? book)? onProgress,
  bool Function()? stopped,
}) async {
  final names = tagNames(library);
  final plans = <TagPlan>[];
  var picker = claude;
  String? problem;
  var calls = 0;
  for (var i = 0; i < books.length; i++) {
    if (stopped?.call() ?? false) break;
    final book = books[i];
    onProgress?.call(i, books.length, book);
    TagPicker? counted;
    final current = picker;
    if (current != null) {
      counted = (b, s, t) {
        calls++;
        return current(b, s, t);
      };
    }
    try {
      plans.add(await planBookTags(
        book,
        library,
        subjects: subjects,
        claude: counted,
        yourTags: names,
      ));
    } on ClaudeFailure catch (failure) {
      problem = failure.message;
      picker = null;
      plans.add(await planBookTags(book, library, subjects: subjects));
    }
  }
  onProgress?.call(plans.length, books.length, null);
  return TagRun(plans: plans, claudeProblem: problem, claudeCalls: calls);
}

// ---- Claude's part

const _system = 'You tag books in a personal reading library. '
    'You reply with JSON only.';

/// The question for Claude about one book.
String tagPrompt(Book book, List<String> subjects, List<String> yourTags) {
  final tags = yourTags.take(200).join(', ');
  return [
    'Book: "${book.title}"${book.author.isEmpty ? '' : ' by ${book.author}'}',
    if (book.series != null && book.series!.isNotEmpty) 'Series: ${book.series}',
    'Open Library subjects: ${subjects.isEmpty ? 'none' : subjects.join('; ')}',
    "The reader's tags: ${tags.isEmpty ? 'none yet' : tags}",
    '',
    'Pick up to $maxTagsPerBook tags for this book. Use the reader\'s tags, '
        'spelled exactly as above, whenever one fits. Only suggest a new tag '
        'when none of theirs fits; keep it to one to three words, in the same '
        'style as theirs.',
    'If you do not know this book and the subjects do not say enough about '
        'it, do not guess: reply with known false and no tags.',
    'Reply with JSON only, like {"known": true, "tags": ["Fantasy"]}.',
  ].join('\n');
}

/// The tags in Claude's answer. Empty when it said it does not know the
/// book, or the answer cannot be read.
List<String> parseTagReply(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return const [];
  Object? data;
  try {
    data = jsonDecode(text.substring(start, end + 1));
  } on FormatException {
    return const [];
  }
  if (data is! Map || data['known'] == false) return const [];
  final tags = data['tags'];
  if (tags is! List) return const [];
  final seen = <String>{};
  return [
    for (final tag in tags)
      if (tag is String &&
          tag.trim().isNotEmpty &&
          tag.trim().length <= 40 &&
          seen.add(tag.trim().toLowerCase()))
        tag.trim(),
  ].take(maxTagsPerBook).toList();
}

/// A [TagPicker] that asks Claude through [client].
TagPicker claudeTagPicker(ClaudeClient client) =>
    (book, subjects, yourTags) async => parseTagReply(
          await client.ask(
            system: _system,
            prompt: tagPrompt(book, subjects, yourTags),
            maxTokens: 600,
          ),
        );

// ---- How well it works on books you have already tagged

/// How one way of finding tags did against your own tags.
class MethodScore {
  int books = 0;

  /// Your tags on the test books.
  int yourTags = 0;

  /// Of those, how many it found.
  int found = 0;

  /// Tags it would have added.
  int suggested = 0;

  /// Of those, how many were yours.
  int right = 0;

  /// Books where it found at least one of your tags.
  int booksHit = 0;

  /// Books where it found nothing at all.
  int booksEmpty = 0;

  double get foundShare => yourTags == 0 ? 0 : found / yourTags;
  double get rightShare => suggested == 0 ? 0 : right / suggested;

  void add(Set<String> truth, Set<String> picked) {
    books++;
    yourTags += truth.length;
    suggested += picked.length;
    final hits = picked.intersection(truth).length;
    found += hits;
    right += hits;
    if (hits > 0) booksHit++;
    if (picked.isEmpty) booksEmpty++;
  }
}

class TagTestReport {
  TagTestReport({
    required this.openLibrary,
    this.withClaude,
    this.claudeCalls = 0,
    this.claudeProblem,
  });

  final MethodScore openLibrary;

  /// Null when Claude was not used.
  final MethodScore? withClaude;
  final int claudeCalls;
  final String? claudeProblem;
}

/// Up to [count] of your tagged books, spread over the library.
List<Book> pickTestBooks(List<Book> library, {int count = 50}) {
  final tagged = [
    for (final book in library)
      if (book.deletedAt == null && book.tags.isNotEmpty) book,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  if (tagged.length <= count) return tagged;
  final step = tagged.length / count;
  return [for (var i = 0; i < count; i++) tagged[(i * step).floor()]];
}

/// Hides the tags of some tagged books, finds tags for them with Open
/// Library alone and with Open Library and then Claude, and compares the
/// result with the tags you gave them. Only the tags it would add without
/// asking count.
Future<TagTestReport> runTagTest(
  List<Book> library, {
  required SubjectLookup subjects,
  TagPicker? claude,
  int count = 50,
  void Function(int done, int total)? onProgress,
  bool Function()? stopped,
}) async {
  final sample = pickTestBooks(library, count: count);
  final openLibrary = MethodScore();
  final withClaude = claude == null ? null : MethodScore();
  final cache = <String, List<String>>{};
  Future<List<String>> lookup(Book book) async =>
      cache[book.id] ??= await subjects(book);
  var picker = claude;
  var calls = 0;
  String? problem;
  for (var i = 0; i < sample.length; i++) {
    if (stopped?.call() ?? false) break;
    final book = sample[i];
    final hidden = book.copyWith(tags: const []);
    final others = [for (final b in library) b.id == book.id ? hidden : b];
    final truth = {for (final t in book.tags) t.trim().toLowerCase()};
    final names = tagNames(others);

    final alone = await planBookTags(hidden, others, subjects: lookup);
    final picked = {for (final t in alone.checkedTags) t.toLowerCase()};
    openLibrary.add(truth, picked);

    if (withClaude != null) {
      var both = picked;
      final current = picker;
      if (both.isEmpty && current != null) {
        try {
          final plan = await planBookTags(
            hidden,
            others,
            subjects: lookup,
            claude: (b, s, t) {
              calls++;
              return current(b, s, t);
            },
            yourTags: names,
          );
          both = {for (final t in plan.checkedTags) t.toLowerCase()};
        } on ClaudeFailure catch (failure) {
          problem = failure.message;
          picker = null;
        }
      }
      withClaude.add(truth, both);
    }
    onProgress?.call(i + 1, sample.length);
  }
  return TagTestReport(
    openLibrary: openLibrary,
    withClaude: withClaude,
    claudeCalls: calls,
    claudeProblem: problem,
  );
}
