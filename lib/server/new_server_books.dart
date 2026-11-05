import 'server_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// What a look at the newest books on your book server found.
class NewServerBooks {
  const NewServerBooks(this.books, this.newest);

  /// Books added on the server since you last looked, newest first, that
  /// are not in your library from the server yet.
  final List<ServerBook> books;

  /// When the newest of all the books looked at was added, or null when
  /// none says.
  final DateTime? newest;
}

/// Picks the books in [recent] (newest first, from the server) added after
/// [seenAt]. On the first look ([seenAt] null) nothing is new: everything
/// already there counts as seen. Books [isLinked] says you already have
/// from the server are left out.
NewServerBooks pickNewServerBooks(
  List<ServerBook> recent, {
  required DateTime? seenAt,
  required bool Function(String serverId) isLinked,
}) {
  DateTime? newest;
  for (final book in recent) {
    final added = book.addedAt;
    if (added != null && (newest == null || added.isAfter(newest))) {
      newest = added;
    }
  }
  if (seenAt == null) return NewServerBooks(const [], newest);
  return NewServerBooks(
    [
      for (final book in recent)
        if (book.addedAt case final added?)
          if (added.isAfter(seenAt) && !isLinked(book.id)) book,
    ],
    newest,
  );
}
