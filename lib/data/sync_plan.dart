import '../models/book.dart';
import '../models/shelf.dart';
import 'sync_merge.dart';

/// What happens to one book in a sync.
enum ChangeKind { added, changed, trashed, restored, deleted }

extension ChangeKindLabel on ChangeKind {
  String get label => switch (this) {
        ChangeKind.added => 'Added',
        ChangeKind.changed => 'Changed',
        ChangeKind.trashed => 'Moved to the trash',
        ChangeKind.restored => 'Back from the trash',
        ChangeKind.deleted => 'Deleted for good',
      };

  /// Whether this change takes a book away.
  bool get removes => this == ChangeKind.trashed || this == ChangeKind.deleted;
}

/// One book that a sync will change on one device.
class BookChange {
  const BookChange({
    required this.id,
    required this.title,
    required this.author,
    required this.kind,
    this.details = const [],
  });

  final String id;
  final String title;
  final String author;
  final ChangeKind kind;

  /// What changed, such as "Moved to Finished" or "Rating 3 → 5".
  final List<String> details;
}

/// What a sync will do on this PC and on the phone, worked out before
/// anything is changed.
class SyncPlan {
  const SyncPlan({required this.onPc, required this.onPhone});

  final List<BookChange> onPc;
  final List<BookChange> onPhone;

  bool get isEmpty => onPc.isEmpty && onPhone.isEmpty;

  /// How many books the sync takes away (trash or deleted for good), on
  /// either device.
  int get removals => [...onPc, ...onPhone].where((c) => c.kind.removes).length;

  /// The same plan gives the same text. Used to remember a plan the user
  /// chose to skip.
  String get signature => [
        for (final c in onPc) 'pc:${c.id}:${c.kind.name}',
        for (final c in onPhone) 'phone:${c.id}:${c.kind.name}',
      ].join('|');
}

String _stars(int? rating) => rating == null ? 'none' : '$rating';

String _day(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

bool _sameList(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A short list of what is different between two copies of a book.
List<String> describeChanges(Book before, Book after) {
  final details = <String>[];
  if (before.title != after.title) details.add('Title: ${after.title}');
  if (before.author != after.author) details.add('Author: ${after.author}');
  if (before.shelf != after.shelf) {
    details.add('Moved to ${after.shelf.label}');
  }
  if (before.rating != after.rating) {
    details.add(
      after.rating == null
          ? 'Rating removed'
          : 'Rating ${_stars(before.rating)} → ${after.rating}',
    );
  }
  if (before.currentPage != after.currentPage && after.currentPage != null) {
    details.add('On page ${after.currentPage}');
  }
  if (before.pages != after.pages) {
    details.add(after.pages == null ? 'Pages removed' : '${after.pages} pages');
  }
  if (before.startedAt != after.startedAt && after.startedAt != null) {
    details.add('Started ${_day(after.startedAt!)}');
  }
  if (before.finishedAt != after.finishedAt && after.finishedAt != null) {
    details.add('Finished ${_day(after.finishedAt!)}');
  }
  if (before.favorite != after.favorite) {
    details.add(after.favorite ? 'Added to favorites' : 'Removed from favorites');
  }
  if (before.format != after.format) details.add('Format changed');
  if (!_sameList(before.tags, after.tags)) details.add('Tags changed');
  if (!_sameList(before.collections, after.collections)) {
    details.add('Your shelves changed');
  }
  if (before.notes != after.notes) details.add('Notes changed');
  if (before.coverUrl != after.coverUrl) details.add('New cover');
  if (before.audio != after.audio) details.add('Listening position');
  if (before.quotes.length != after.quotes.length) {
    final diff = after.quotes.length - before.quotes.length;
    details.add(
      diff > 0
          ? '$diff ${diff == 1 ? 'quote' : 'quotes'} added'
          : '${-diff} ${diff == -1 ? 'quote' : 'quotes'} removed',
    );
  }
  if (before.readingLog.length != after.readingLog.length ||
      before.previousReadings.length != after.previousReadings.length) {
    details.add('Reading log changed');
  }
  if (before.series != after.series ||
      before.seriesNumber != after.seriesNumber) {
    details.add('Series changed');
  }
  if (before.priority != after.priority ||
      before.buyAt != after.buyAt ||
      before.queuePosition != after.queuePosition) {
    details.add('Wishlist details changed');
  }
  if (details.isEmpty) details.add('Details changed');
  return details;
}

/// The changes needed to turn [before] into [after], one per book.
List<BookChange> diffLibraries(List<Book> before, List<Book> after) {
  final old = {for (final book in before) book.id: book};
  final changes = <BookChange>[];
  final seen = <String>{};
  for (final book in after) {
    seen.add(book.id);
    final previous = old[book.id];
    if (previous == null) {
      changes.add(BookChange(
        id: book.id,
        title: book.title,
        author: book.author,
        kind: book.deletedAt == null ? ChangeKind.added : ChangeKind.trashed,
      ));
      continue;
    }
    if (previous.updatedAt == book.updatedAt) continue;
    final ChangeKind kind;
    if (previous.deletedAt == null && book.deletedAt != null) {
      kind = ChangeKind.trashed;
    } else if (previous.deletedAt != null && book.deletedAt == null) {
      kind = ChangeKind.restored;
    } else {
      kind = ChangeKind.changed;
    }
    changes.add(BookChange(
      id: book.id,
      title: book.title,
      author: book.author,
      kind: kind,
      details: kind == ChangeKind.changed
          ? describeChanges(previous, book)
          : const [],
    ));
  }
  for (final book in before) {
    if (seen.contains(book.id)) continue;
    changes.add(BookChange(
      id: book.id,
      title: book.title,
      author: book.author,
      kind: ChangeKind.deleted,
    ));
  }
  changes.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    return byKind != 0
        ? byKind
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return changes;
}

/// Works out what a sync would do, the same way [mergeLibraries] does it
/// in a real sync (the phone's copy wins a tie).
SyncPlan planSync({
  required List<Book> phoneBooks,
  required Map<String, DateTime> phoneTombstones,
  required List<Book> pcBooks,
  required Map<String, DateTime> pcTombstones,
}) {
  final merged = mergeLibraries(
    local: phoneBooks,
    localTombstones: phoneTombstones,
    remote: pcBooks,
    remoteTombstones: pcTombstones,
  );
  return SyncPlan(
    onPc: diffLibraries(pcBooks, merged.books),
    onPhone: diffLibraries(phoneBooks, merged.books),
  );
}

/// "Synced 5 min ago" and the like, for the top of the library.
String syncedAgoText(DateTime? at, DateTime now) {
  if (at == null) return 'Not synced yet';
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return 'Synced just now';
  if (gap.inMinutes < 60) return 'Synced ${gap.inMinutes} min ago';
  if (gap.inHours < 24) {
    return 'Synced ${gap.inHours} ${gap.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  final days = gap.inDays;
  if (days == 1) return 'Synced yesterday';
  return 'Synced $days days ago';
}
