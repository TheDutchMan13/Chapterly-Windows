import '../models/book.dart';
import 'tag_suggest.dart';

// Windows app only.

/// A tag offered for a book. Sure matches start ticked; new tag names start
/// unticked.
class TagProposal {
  TagProposal({
    required this.tag,
    required this.isNew,
    required this.checked,
    this.reason = '',
  });

  final String tag;

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

/// Open Library's subjects for a book.
typedef SubjectLookup = Future<List<String>> Function(Book book);

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

/// Finds tags for one book from its Open Library subjects, matched to your
/// tags and to the tags on your other books by the same author or series.
Future<TagPlan> planBookTags(
  Book book,
  List<Book> library, {
  required SubjectLookup subjects,
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
        isNew: s.isNew,
        checked: !s.isNew && s.score >= _sureScore,
        reason: s.reason,
      ),
  ];
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

/// Finds tags for [books], one after another. Stops early when [stopped]
/// says so.
Future<List<TagPlan>> planTags(
  List<Book> books,
  List<Book> library, {
  required SubjectLookup subjects,
  void Function(int done, int total, Book? book)? onProgress,
  bool Function()? stopped,
}) async {
  final plans = <TagPlan>[];
  for (var i = 0; i < books.length; i++) {
    if (stopped?.call() ?? false) break;
    onProgress?.call(i, books.length, books[i]);
    plans.add(await planBookTags(books[i], library, subjects: subjects));
  }
  onProgress?.call(plans.length, books.length, null);
  return plans;
}

// ---- How well it works on books you have already tagged

/// How well the tags found agree with your own tags.
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
  TagTestReport({required this.openLibrary});

  final MethodScore openLibrary;
}

/// Up to [count] of your tagged books, spread over the library.
List<Book> pickTestBooks(List<Book> library, {int count = 150}) {
  final tagged = [
    for (final book in library)
      if (book.deletedAt == null && book.tags.isNotEmpty) book,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  if (tagged.length <= count) return tagged;
  final step = tagged.length / count;
  return [for (var i = 0; i < count; i++) tagged[(i * step).floor()]];
}

/// Hides the tags of some tagged books, finds tags for them from Open
/// Library, and compares the result with the tags you gave them. Only the
/// tags it would add on its own count.
Future<TagTestReport> runTagTest(
  List<Book> library, {
  required SubjectLookup subjects,
  int count = 150,
  void Function(int done, int total)? onProgress,
  bool Function()? stopped,
}) async {
  final sample = pickTestBooks(library, count: count);
  final score = MethodScore();
  final cache = <String, List<String>>{};
  Future<List<String>> lookup(Book book) async =>
      cache[book.id] ??= await subjects(book);
  for (var i = 0; i < sample.length; i++) {
    if (stopped?.call() ?? false) break;
    final book = sample[i];
    final hidden = book.copyWith(tags: const []);
    final others = [for (final b in library) b.id == book.id ? hidden : b];
    final truth = {for (final t in book.tags) t.trim().toLowerCase()};
    final plan = await planBookTags(hidden, others, subjects: lookup);
    score.add(truth, {for (final t in plan.checkedTags) t.toLowerCase()});
    onProgress?.call(i + 1, sample.length);
  }
  return TagTestReport(openLibrary: score);
}
