import 'dart:async';

import '../models/book.dart';
import 'app_settings.dart';
import 'book_repository.dart';
import 'google_books_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// In the background, asks Google Books for what a book is missing (cover,
/// pages, ISBN, first published year, and tags when it has none) and fills
/// it in. Nothing a book already has is changed. It is off until you switch
/// on "Use Google Books" in Settings, because it sends each title and author
/// to Google.
///
/// It asks about each book once, a few at a time. Without a key Google
/// allows only a few requests a day: when they run out it stops and carries
/// on tomorrow.
class GoogleBooksFill {
  GoogleBooksFill._(this._repository, this._settings, this._client);

  final BookRepository _repository;
  final AppSettings _settings;
  final GoogleBooksClient _client;
  Timer? _timer;
  bool _running = false;

  /// How many books are asked about in one go.
  static const batch = 20;

  static GoogleBooksFill start(
    BookRepository repository,
    AppSettings settings, {
    GoogleBooksClient? client,
  }) {
    final watcher = GoogleBooksFill._(
      repository,
      settings,
      client ?? GoogleBooksClient(apiKey: () => settings.googleBooksKey),
    );
    repository.addListener(watcher._changed);
    settings.addListener(watcher._changed);
    watcher._changed();
    return watcher;
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  bool get _paused => _settings.googleBooksPausedOn == _today();

  void _changed() {
    if (_running || !_settings.useGoogleBooks || _paused) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 15), () => unawaited(run()));
  }

  static bool _missingSomething(Book b) =>
      (b.coverUrl ?? '').isEmpty ||
      b.pages == null ||
      (b.isbn ?? '').isEmpty ||
      b.firstPublishYear == null ||
      b.tags.isEmpty;

  /// Books to ask about: something missing, and not asked before.
  List<Book> pending() => [
        for (final book in _repository.books)
          if (book.title.trim().isNotEmpty &&
              _missingSomething(book) &&
              !_settings.googleBooksAsked.contains(book.id))
            book,
      ];

  /// Asks about up to [batch] books. Returns how many got something.
  Future<int> run() async {
    if (_running || !_settings.useGoogleBooks || _paused) return 0;
    _running = true;
    var filled = 0;
    try {
      final asked = <String>[];
      for (final book in pending().take(batch)) {
        if (!_settings.useGoogleBooks) break;
        final GoogleBook? found;
        try {
          found = await _client.find(book);
        } on GoogleQuotaReached {
          // Today's requests are used up: carry on tomorrow.
          _settings.setGoogleBooksPausedOn(_today());
          break;
        }
        asked.add(book.id);
        if (found == null) continue;
        var changed = await _repository.fillBlanks(
          book.id,
          isbn: found.isbn,
          year: found.year,
          coverUrl: found.coverUrl,
          tags: found.categories,
        );
        final pages = found.pages;
        if (book.pages == null && pages != null) {
          await _repository.setPages(book.id, pages);
          changed = true;
        }
        if (changed) filled++;
      }
      _settings.addGoogleBooksAsked(asked);
    } finally {
      _running = false;
      if (_settings.useGoogleBooks && !_paused && pending().isNotEmpty) {
        _timer?.cancel();
        _timer = Timer(const Duration(minutes: 1), () => unawaited(run()));
      }
    }
    return filled;
  }
}
