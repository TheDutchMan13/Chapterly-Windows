import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/sync_merge.dart';
import '../data/sync_protocol.dart';
import '../data/sync_three_way.dart';
import '../data/wish_list.dart';
import '../models/book.dart';
import 'server_client.dart';
import 'server_sync.dart';

// The same file is in the Android app.

/// How many books differ between two versions of the library.
int countLibraryChanges(List<Book> before, List<Book> after) {
  final old = {for (final book in before) book.id: book};
  var changed = 0;
  for (final book in after) {
    final was = old.remove(book.id);
    if (was == null || !was.updatedAt.isAtSameMomentAs(book.updatedAt) ||
        was.deletedAt != book.deletedAt) {
      changed++;
    }
  }
  return changed + old.length;
}

/// Syncs your whole library (books, shelves, ratings, notes, quotes and
/// highlights' text, audiobook bookmarks, the wish list) through your book
/// server, so it works from anywhere Tailscale reaches.
///
/// The server only keeps the latest library and a version number. This
/// device does the merging, the same way as syncing with the phone over
/// Wi-Fi: a change to a field made on one device and a change to another
/// field on another both survive (compared with [base], what the server
/// held at the last sync), and for the rest the newer copy of a book wins.
/// If another device saved meanwhile, it merges again.
class LibrarySync {
  LibrarySync({
    required this.sync,
    required this.repository,
    required this.settings,
    required this.base,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ServerSync sync;
  final BookRepository repository;
  final AppSettings settings;

  /// The server's library at the last sync. Kept apart from the one for
  /// syncing with the phone over Wi-Fi.
  final SyncBase base;
  final DateTime Function() _now;
  bool _busy = false;

  bool get enabled => sync.state.connected && sync.state.librarySync;

  /// Syncs once. Returns how many books changed on this device. Throws a
  /// [ServerFailure] when it can't.
  Future<int> syncNow() async {
    final client = sync.client;
    if (client == null || !sync.state.librarySync || _busy) return 0;
    _busy = true;
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        final changed = await _once(client);
        if (changed != null) return changed;
      }
      throw const ServerFailure(
        'Your other devices kept saving at the same moment. Try again.',
      );
    } finally {
      _busy = false;
    }
  }

  /// Null when another device saved first.
  Future<int?> _once(ServerClient client) async {
    final stored = await client.getLibrary();
    final text = stored.library;
    final server = text == null ? null : decodeSyncPayload(text);

    // This device's library, with books changed on both sides merged field
    // by field.
    var mine = repository.snapshot();
    if (server != null && !base.isEmpty) {
      final resolved = resolveConflicts(
        base: base.books,
        local: mine.books,
        remote: server.books,
        now: _now(),
      );
      if (resolved.isNotEmpty) {
        final byId = {for (final book in resolved) book.id: book};
        mine = (
          books: [for (final book in mine.books) byId[book.id] ?? book],
          tombstones: mine.tombstones,
        );
      }
    }
    final merged = server == null
        ? (books: mine.books, tombstones: mine.tombstones)
        : (() {
            final m = mergeLibraries(
              local: server.books,
              localTombstones: server.tombstones,
              remote: mine.books,
              remoteTombstones: mine.tombstones,
            );
            return (books: m.books, tombstones: m.tombstones);
          })();
    final wishes = mergeWishes(server?.wishes ?? const [], settings.allWishes);

    try {
      await client.putLibrary(
        stored.version,
        encodeSyncPayload(merged.books, merged.tombstones, wishes: wishes),
      );
    } on ServerFailure catch (failure) {
      if (failure.conflict) return null;
      rethrow;
    }

    // Taken here, keeping a change made on this device while syncing; the
    // next sync sends it.
    final now = repository.snapshot();
    final applied = mergeLibraries(
      local: merged.books,
      localTombstones: merged.tombstones,
      remote: now.books,
      remoteTombstones: now.tombstones,
    );
    final changed = countLibraryChanges(now.books, applied.books);
    await repository.applySynced(applied.books, applied.tombstones);
    settings.mergeWishesFrom(wishes);
    await base.save(merged.books);
    await sync.state.recordLibrarySync(_now());
    return changed;
  }
}
