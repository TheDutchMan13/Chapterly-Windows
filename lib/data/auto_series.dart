import 'dart:async';

import 'app_settings.dart';
import 'book_repository.dart';
import 'series_detect.dart';

// The same file is in the Android app; keep the two copies alike.

/// Sets the series of books by itself: when a book without a series has one
/// in its title ("Mistborn, Book 2: The Well of Ascension", "(The Expanse,
/// #3)"), the series and number are filled in. It looks again whenever the
/// library changes, so a book added later can complete a pair.
///
/// A series you already set is never changed. A book whose series was set
/// here and that you then cleared is left alone from then on. The "Name 3:
/// Subtitle" pattern only counts when two books share the name, as in the
/// Series screen's "Find series in titles".
class AutoSeries {
  AutoSeries._(this._repository, this._settings);

  final BookRepository _repository;
  final AppSettings _settings;
  Timer? _timer;
  bool _running = false;

  /// Starts watching the library. The first look is a moment after start.
  static AutoSeries start(BookRepository repository, AppSettings settings) {
    final watcher = AutoSeries._(repository, settings);
    repository.addListener(watcher._changed);
    watcher._changed();
    return watcher;
  }

  void _changed() {
    if (_running || !_settings.autoSeries) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () => unawaited(run()));
  }

  /// Fills in the series now. Returns how many books got one.
  Future<int> run() async {
    if (_running || !_settings.autoSeries) return 0;
    _running = true;
    try {
      final guesses = pickAutoSeries(
        detectSeries(_repository.books),
        alreadySet: _settings.autoSeriesApplied,
      );
      if (guesses.isEmpty) return 0;
      await _repository.setSeriesFor({
        for (final guess in guesses) guess.book.id: (guess.series, guess.number),
      });
      _settings.addAutoSeriesApplied([for (final g in guesses) g.book.id]);
      return guesses.length;
    } finally {
      _running = false;
    }
  }
}

/// The guesses to apply: books still without a series that were not given
/// one here before (so a series you cleared stays cleared).
List<SeriesGuess> pickAutoSeries(
  List<SeriesGuess> guesses, {
  required Set<String> alreadySet,
}) =>
    [
      for (final guess in guesses)
        if (!alreadySet.contains(guess.book.id) &&
            (guess.book.series ?? '').trim().isEmpty)
          guess,
    ];
