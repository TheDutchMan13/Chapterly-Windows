import 'dart:math' as math;

import '../audio/audio_library.dart';
import '../ebook/ebook_library.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import 'date_format.dart';

// Windows app only.

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

int _daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// How much a day counts compared with today: half as much every
/// [halfLife] days back.
double _weight(int age, int halfLife) => math.pow(0.5, age / halfLife).toDouble();

/// The amount per day, with recent days counting more than older ones (half
/// as much every [halfLife] days), from [first] to [today] and at most the
/// last [window] days. Days with nothing count as 0, so a break slows the
/// pace down. Today only counts once something was done today.
double recentRate(
  Map<DateTime, double> perDay,
  DateTime first,
  DateTime today, {
  int halfLife = 10,
  int window = 60,
}) {
  final end = _day(today);
  final last = (perDay[end] ?? 0) > 0 ? end : end.subtract(const Duration(days: 1));
  var start = _day(first);
  final earliest = last.subtract(Duration(days: window - 1));
  if (start.isBefore(earliest)) start = earliest;
  if (start.isAfter(last)) start = last;
  var total = 0.0;
  var weights = 0.0;
  for (var day = start;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final w = _weight(_daysBetween(day, last), halfLife);
    total += w * (perDay[day] ?? 0);
    weights += w;
  }
  return weights <= 0 ? 0 : total / weights;
}

/// What a forecast is worked out from.
enum ForecastBasis { pages, listening, reader }

/// When a book you are reading should be finished, at your recent pace.
class FinishForecast {
  const FinishForecast({
    required this.basis,
    required this.daysLeft,
    required this.date,
    required this.perDay,
  });

  final ForecastBasis basis;
  final int daysLeft;
  final DateTime date;

  /// The recent pace: pages, minutes of audio, or percent of the book a day.
  final double perDay;

  String get paceText => switch (basis) {
        ForecastBasis.pages => '${_number(perDay)} pages a day lately',
        ForecastBasis.listening => '${formatMinutes(perDay.round())} '
            'of audio a day lately',
        ForecastBasis.reader => '${_number(perDay * 100)}% of the book a day '
            'lately',
      };

  /// For example "About 12 days left · finish around 2026-11-12 (18 pages
  /// a day lately)".
  String describe() {
    if (daysLeft <= 0) return 'Almost done: you should finish today';
    final days = daysLeft == 1 ? '1 day' : '$daysLeft days';
    return 'About $days left · finish around ${formatDate(date)} '
        '($paceText)';
  }
}

String _number(double value) =>
    value >= 10 ? value.round().toString() : value.toStringAsFixed(1);

class _Candidate {
  _Candidate(this.basis, this.left, this.rate, this.lastActive);

  final ForecastBasis basis;
  final double left;
  final double rate;
  final DateTime lastActive;
}

/// When [book] should be finished, from whichever way you have been reading
/// it most recently: pages in the reading log (or the current page),
/// listening time against what is left of the audiobook, or the reader's
/// progress in the book file. Null when it is not on In progress or there
/// is nothing to go on yet.
FinishForecast? forecastFinish(
  Book book, {
  AudioLink? audio,
  double speed = 1,
  EbookLink? ebook,
  DateTime? now,
}) {
  if (book.shelf != Shelf.inProgress) return null;
  final today = _day(now ?? DateTime.now());
  final candidates = <_Candidate>[];

  // Pages.
  final total = book.pages;
  final done = book.progressPage;
  if (total != null && total > 0 && done != null) {
    final pages = <DateTime, double>{};
    for (final entry in book.readingLog) {
      if (entry.pages <= 0) continue;
      final day = _day(entry.date);
      pages[day] = (pages[day] ?? 0) + entry.pages;
    }
    final started = book.startedAt == null ? null : _day(book.startedAt!);
    final logStart = pages.isEmpty
        ? null
        : pages.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    final first = [?started, ?logStart]
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    if (first != null) {
      double rate;
      DateTime lastActive;
      if (pages.isNotEmpty) {
        rate = recentRate(pages, first, today);
        lastActive = pages.keys.reduce((a, b) => a.isAfter(b) ? a : b);
      } else {
        // Only the current page: the average since the start.
        rate = done / (_daysBetween(first, today) + 1);
        lastActive = _day(book.updatedAt);
      }
      candidates.add(
        _Candidate(ForecastBasis.pages, math.max(0, total - done).toDouble(),
            rate, lastActive),
      );
    }
  }

  // Listening.
  final progress = book.audio;
  final length = audio?.lengthMs ?? progress?.lengthMs;
  if (progress != null && length != null && length > 0) {
    final minutes = <DateTime, double>{};
    for (final entry in book.readingLog) {
      if (entry.minutes <= 0) continue;
      final day = _day(entry.date);
      minutes[day] = (minutes[day] ?? 0) + entry.minutes;
    }
    if (minutes.isNotEmpty) {
      final first = minutes.keys.reduce((a, b) => a.isBefore(b) ? a : b);
      final left =
          math.max(0, length - progress.positionMs) / 60000 / (speed <= 0 ? 1 : speed);
      candidates.add(_Candidate(
        ForecastBasis.listening,
        left,
        recentRate(minutes, first, today),
        minutes.keys.reduce((a, b) => a.isAfter(b) ? a : b),
      ));
    }
  }

  // The reader.
  final position = ebook?.position;
  final days = ebook?.days ?? const <EbookDay>[];
  if (position != null && days.isNotEmpty) {
    final sorted = [...days]..sort((a, b) => a.day.compareTo(b.day));
    final gains = <DateTime, double>{};
    var best = 0.0;
    for (final day in sorted) {
      if (day.progress > best) {
        final key = _day(day.day);
        gains[key] = (gains[key] ?? 0) + day.progress - best;
        best = day.progress;
      }
    }
    if (gains.isNotEmpty) {
      candidates.add(_Candidate(
        ForecastBasis.reader,
        math.max(0, 1 - position.progress),
        recentRate(gains, _day(sorted.first.day), today),
        gains.keys.reduce((a, b) => a.isAfter(b) ? a : b),
      ));
    }
  }

  final usable = [
    for (final c in candidates)
      if (c.rate > 0 || c.left <= 0) c,
  ];
  if (usable.isEmpty) return null;
  // The way you read it most recently wins.
  usable.sort((a, b) => b.lastActive.compareTo(a.lastActive));
  final pick = usable.first;
  final daysLeft = pick.left <= 0 ? 0 : (pick.left / pick.rate).ceil();
  return FinishForecast(
    basis: pick.basis,
    daysLeft: daysLeft,
    date: DateTime(today.year, today.month, today.day + daysLeft),
    perDay: pick.rate,
  );
}

/// Where this year's goal is heading at your pace.
class GoalForecast {
  const GoalForecast({
    required this.goal,
    required this.finished,
    required this.projected,
    required this.daysLeft,
    this.reachedOn,
  });

  final int goal;
  final int finished;

  /// Books you should have finished by the end of the year.
  final int projected;
  final int daysLeft;

  /// When you should reach the goal, if before the year ends.
  final DateTime? reachedOn;

  /// For example "On track for about 34 by Dec 31 (goal reached around
  /// 2026-11-20)" or "Heading for about 22 by Dec 31: one book every 6 days
  /// gets you to 30".
  String describe() {
    if (finished >= goal) return 'Goal reached! Heading for about $projected';
    final reached = reachedOn;
    if (projected >= goal && reached != null) {
      return 'On track for about $projected by Dec 31 '
          '(goal reached around ${formatDate(reached)})';
    }
    final left = goal - finished;
    final every = daysLeft <= 0 ? 0 : daysLeft / left;
    final pace = every >= 1.5
        ? 'one book every ${every.floor()} days'
        : '${_number(left / math.max(1, daysLeft) * 7)} books a week';
    return 'Heading for about $projected by Dec 31: $pace gets you to $goal';
  }
}

/// How this year's goal of [goal] books is going: books finished so far
/// this year and in the last 90 days give a pace (the last 90 days count
/// as much as the whole year), and books you are reading that should be
/// finished by Dec 31 ([finishDates]) count too. Null for other years and
/// in the first two weeks of the year.
GoalForecast? forecastGoal(
  List<Book> books, {
  required int goal,
  required int year,
  Iterable<DateTime> finishDates = const [],
  DateTime? now,
}) {
  final today = _day(now ?? DateTime.now());
  if (today.year != year || goal <= 0) return null;
  final start = DateTime(year);
  final end = DateTime(year, 12, 31);
  final elapsed = _daysBetween(start, today) + 1;
  if (elapsed < 14) return null;
  final daysLeft = _daysBetween(today, end);
  var finished = 0;
  var recent = 0;
  final recentStart = today.subtract(const Duration(days: 89));
  for (final book in books) {
    if (book.deletedAt != null) continue;
    for (final reading in book.finishedReadings) {
      final date = reading.finishedAt;
      if (date == null || date.year != year) continue;
      finished++;
      if (!_day(date).isBefore(recentStart)) recent++;
    }
  }
  final recentDays = math.min(90, elapsed);
  final rate = 0.5 * finished / elapsed + 0.5 * recent / recentDays;
  final soon = finishDates.where((d) => !_day(d).isAfter(end)).length;
  final expected = math.max(rate * daysLeft, soon.toDouble());
  final projected = finished + expected.round();
  DateTime? reachedOn;
  if (finished < goal && rate > 0) {
    final days = ((goal - finished) / rate).ceil();
    final date = DateTime(today.year, today.month, today.day + days);
    if (!date.isAfter(end)) reachedOn = date;
  }
  return GoalForecast(
    goal: goal,
    finished: finished,
    projected: projected,
    daysLeft: daysLeft,
    reachedOn: reachedOn,
  );
}
