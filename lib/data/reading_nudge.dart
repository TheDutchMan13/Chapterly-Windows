import '../models/book.dart';
import '../models/shelf.dart';
import 'forecast.dart';

// The same file is in the Android app.

/// What the home-screen widget shows.
class WidgetContent {
  const WidgetContent({
    required this.title,
    required this.detail,
    this.author = '',
    this.bookId,
    this.audio = false,
    this.playing = false,
  });

  final String title;
  final String author;

  /// "42% · 3 h 10 min left", "Page 120 of 400"...
  final String detail;
  final String? bookId;

  /// Has an audiobook place, so the widget shows play/pause.
  final bool audio;
  final bool playing;
}

String _left(int ms) {
  final minutes = ms ~/ 60000;
  final hours = minutes ~/ 60;
  return hours == 0 ? '$minutes min left' : '$hours h ${minutes % 60} min left';
}

/// The book for the widget: the audiobook in the player, or else the book
/// on In progress you touched last.
WidgetContent widgetContent(
  List<Book> books, {
  String? playerBookId,
  bool playing = false,
}) {
  Book? book;
  if (playerBookId != null) {
    for (final b in books) {
      if (b.id == playerBookId && b.deletedAt == null) book = b;
    }
  }
  book ??= () {
    final reading = [
      for (final b in books)
        if (b.deletedAt == null && b.shelf == Shelf.inProgress) b,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return reading.isEmpty ? null : reading.first;
  }();
  if (book == null) {
    return const WidgetContent(
      title: 'Nothing in progress',
      detail: 'Open Chapterly to pick a book',
    );
  }
  final audio = book.audio;
  final String detail;
  if (audio != null) {
    final fraction = audio.fraction;
    final length = audio.lengthMs;
    detail = [
      if (fraction != null) '${(fraction * 100).round()}%',
      if (length != null && length > audio.positionMs) _left(length - audio.positionMs),
    ].join(' · ');
  } else if (book.currentPage != null && book.pages != null && book.pages! > 0) {
    detail = 'Page ${book.currentPage} of ${book.pages}';
  } else {
    detail = 'Reading';
  }
  return WidgetContent(
    title: book.title,
    author: book.author,
    detail: detail.isEmpty ? 'Listening' : detail,
    bookId: book.id,
    audio: audio != null,
    playing: playing && book.id == playerBookId,
  );
}

/// The daily reminder, when you are behind this year's goal of [goal]
/// books; null when you're on track (or it's too early in the year to
/// tell), so there's nothing to say.
String? reminderText(
  List<Book> books, {
  required int? goal,
  Iterable<DateTime> finishDates = const [],
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  if (goal == null || goal <= 0) return null;
  final outlook = forecastGoal(
    books,
    goal: goal,
    year: today.year,
    finishDates: finishDates,
    now: today,
  );
  if (outlook == null || outlook.finished >= goal || outlook.projected >= goal) {
    return null;
  }
  return "You've read ${outlook.finished} of $goal books this year, heading "
      'for about ${outlook.projected}. A little reading today helps.';
}
