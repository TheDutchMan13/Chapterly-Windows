import 'dart:math' as math;

import '../audio/audio_bookmarks.dart';
import '../ebook/ebook_library.dart';
import '../models/book.dart';
import 'fuzzy.dart';

// Windows app only.

/// Where a piece of text comes from.
enum NoteSource {
  notes('Notes'),
  quote('Quote'),
  highlight('Highlight'),
  highlightNote('Note on a highlight'),
  audioBookmark('Audiobook bookmark');

  const NoteSource(this.label);

  final String label;
}

/// One piece of your own text: a book's notes, a quote, a highlight or a
/// bookmark note.
class NoteDocument {
  const NoteDocument({
    required this.book,
    required this.source,
    required this.text,
  });

  final Book book;
  final NoteSource source;
  final String text;
}

/// A match, with its score.
class NoteHit {
  const NoteHit(this.document, this.score, this.terms);

  final NoteDocument document;
  final double score;

  /// The words that matched (folded), for marking them in the text.
  final Set<String> terms;
}

String _stem(String word) {
  if (word.length > 5 && word.endsWith('ing')) return word.substring(0, word.length - 3);
  if (word.length > 4 && word.endsWith('ed')) return word.substring(0, word.length - 2);
  if (word.length > 4 && word.endsWith('es')) return word.substring(0, word.length - 2);
  if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

const _stopWords = {
  'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'at', 'is', 'it',
  'that', 'this', 'was', 'for', 'with', 'as', 'be', 'by', 'but', 'not',
};

List<String> _terms(String text) => [
      for (final word in foldedWords(text))
        if (!_stopWords.contains(word)) _stem(word),
    ];

/// Every note, quote, highlight and bookmark note in the library.
List<NoteDocument> collectNotes(
  List<Book> books, {
  Map<String, EbookLink> ebooks = const {},
  AudioBookmarks? bookmarks,
}) {
  final docs = <NoteDocument>[];
  for (final book in books) {
    if (book.deletedAt != null) continue;
    final notes = book.notes?.trim() ?? '';
    if (notes.isNotEmpty) {
      docs.add(NoteDocument(book: book, source: NoteSource.notes, text: notes));
    }
    for (final quote in book.quotes) {
      docs.add(NoteDocument(book: book, source: NoteSource.quote, text: quote.text));
    }
    final link = ebooks[book.id];
    for (final highlight in link?.highlights ?? const <EbookHighlight>[]) {
      final alreadyQuote = book.quotes.any((q) => q.text.trim() == highlight.text.trim());
      if (!alreadyQuote) {
        docs.add(NoteDocument(
          book: book,
          source: NoteSource.highlight,
          text: highlight.text,
        ));
      }
      final note = highlight.note?.trim() ?? '';
      if (note.isNotEmpty) {
        docs.add(NoteDocument(book: book, source: NoteSource.highlightNote, text: note));
      }
    }
    for (final mark in bookmarks?.forBook(book.id) ?? const <AudioBookmark>[]) {
      if (mark.note.trim().isNotEmpty) {
        docs.add(NoteDocument(
          book: book,
          source: NoteSource.audioBookmark,
          text: mark.note.trim(),
        ));
      }
    }
  }
  return docs;
}

/// Searches [documents] with BM25, the scoring search engines use: a word
/// counts more when it is rare across your notes and when it fills more of
/// a short text. A search word found nowhere looks for the words it is
/// near (a typo), at half weight. Best first, at most [limit].
List<NoteHit> searchNotes(
  List<NoteDocument> documents,
  String query, {
  int limit = 50,
  double k1 = 1.2,
  double b = 0.75,
}) {
  final queryTerms = _terms(query).toSet();
  if (queryTerms.isEmpty || documents.isEmpty) return const [];
  final docTerms = [for (final d in documents) _terms(d.text)];
  final lengths = [for (final t in docTerms) t.length];
  final average = lengths.fold<int>(0, (s, n) => s + n) / documents.length;
  final frequency = <String, int>{};
  for (final terms in docTerms) {
    for (final term in terms.toSet()) {
      frequency[term] = (frequency[term] ?? 0) + 1;
    }
  }
  // Each search word, and the words it stands for with their weight.
  final expanded = <String, Map<String, double>>{};
  for (final term in queryTerms) {
    if (frequency.containsKey(term)) {
      expanded[term] = {term: 1};
    } else {
      expanded[term] = {
        for (final word in frequency.keys)
          if (isNearWord(term, word)) word: 0.5,
      };
    }
  }
  final n = documents.length;
  double idf(String term) {
    final df = frequency[term] ?? 0;
    return math.log(1 + (n - df + 0.5) / (df + 0.5));
  }

  final hits = <NoteHit>[];
  for (var i = 0; i < documents.length; i++) {
    final counts = <String, int>{};
    for (final term in docTerms[i]) {
      counts[term] = (counts[term] ?? 0) + 1;
    }
    var score = 0.0;
    final matched = <String>{};
    for (final alternatives in expanded.values) {
      for (final entry in alternatives.entries) {
        final tf = counts[entry.key];
        if (tf == null) continue;
        final norm = tf * (k1 + 1) /
            (tf + k1 * (1 - b + b * lengths[i] / (average <= 0 ? 1 : average)));
        score += entry.value * idf(entry.key) * norm;
        matched.add(entry.key);
      }
    }
    if (score > 0) hits.add(NoteHit(documents[i], score, matched));
  }
  hits.sort((x, y) => y.score.compareTo(x.score));
  return hits.take(limit).toList();
}

/// Whether a word of the text is one of the matched [terms].
bool isMatchedWord(String word, Set<String> terms) {
  final folded = foldText(word);
  if (folded.isEmpty) return false;
  return terms.contains(_stem(folded));
}
