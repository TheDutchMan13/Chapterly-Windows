import 'dart:async';

import '../models/book.dart';
import 'app_settings.dart';
import 'book_repository.dart';
import 'wikidata_client.dart';

// Windows app only.

/// In the background, asks Wikidata for the series of books that still have
/// none (after the title check in auto_series.dart). It is off until you
/// switch on "Ask Wikidata for series" in Settings, because it sends each
/// title and author to wikidata.org. It goes slowly on purpose, a few books
/// at a time, and asks about each book only once.
class WikidataSeries {
  WikidataSeries._(this._repository, this._settings, this._client);

  final BookRepository _repository;
  final AppSettings _settings;
  final WikidataClient _client;
  Timer? _timer;
  bool _running = false;

  /// How many books are asked about in one go.
  static const batch = 15;

  static WikidataSeries start(
    BookRepository repository,
    AppSettings settings, {
    WikidataClient? client,
  }) {
    final watcher =
        WikidataSeries._(repository, settings, client ?? WikidataClient());
    repository.addListener(watcher._changed);
    settings.addListener(watcher._changed);
    watcher._changed();
    return watcher;
  }

  void _changed() {
    if (_running || !_settings.wikidataSeries || _client.tooBusy) return;
    _timer?.cancel();
    // After the title check has had its turn.
    _timer = Timer(const Duration(seconds: 8), () => unawaited(run()));
  }

  /// The books to ask about now: no series, not asked before, and not one
  /// whose series you cleared.
  List<Book> pending() => [
        for (final book in _repository.books)
          if ((book.series ?? '').trim().isEmpty &&
              book.title.trim().isNotEmpty &&
              !_settings.wikidataSeriesAsked.contains(book.id) &&
              !_settings.autoSeriesApplied.contains(book.id))
            book,
      ];

  /// Asks about up to [batch] books and fills in what Wikidata knows.
  /// Returns how many books got a series.
  Future<int> run() async {
    if (_running || !_settings.wikidataSeries || _client.tooBusy) return 0;
    _running = true;
    try {
      final todo = pending().take(batch).toList();
      if (todo.isEmpty) return 0;
      final choices = <String, (String, int?)>{};
      final asked = <String>[];
      for (final book in todo) {
        if (!_settings.wikidataSeries || _client.tooBusy) break;
        final found =
            await _client.seriesFor(title: book.title, author: book.author);
        // A busy answer is not "no series": ask again another time.
        if (_client.tooBusy) break;
        asked.add(book.id);
        if (found != null) choices[book.id] = (found.name, found.number);
      }
      _settings.addWikidataSeriesAsked(asked);
      if (choices.isNotEmpty) {
        await _repository.setSeriesFor(choices);
        _settings.addAutoSeriesApplied(choices.keys);
      }
      return choices.length;
    } finally {
      _running = false;
      // More to ask about: carry on after a pause.
      if (!_client.tooBusy && _settings.wikidataSeries && pending().isNotEmpty) {
        _timer?.cancel();
        _timer = Timer(const Duration(minutes: 1), () => unawaited(run()));
      }
    }
  }
}
