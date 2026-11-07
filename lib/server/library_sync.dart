import 'dart:convert';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/cover_store.dart';
import '../data/sync_covers.dart';
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
    final SyncPayload? server;
    try {
      server = text == null ? null : clampFutureDates(decodeSyncPayload(text));
    } on FormatException catch (error) {
      if (error.message.contains('newer')) {
        throw const ServerFailure(
          'Your library on the server was saved by a newer Chapterly. Update '
          'this app to keep syncing it.',
        );
      }
      throw ServerFailure(
        'Your library on the server could not be read: ${error.message}',
      );
    }

    // Books are merged with cover references, never the pictures: those are
    // in [pool] (this device's own) and are fetched only when a book needs
    // one this device lacks. A library saved before covers became
    // references is read the same way.
    final pool = CoverPool();
    final serverBooks =
        server == null ? const <Book>[] : withCoverRefs(server.books, pool);

    // This device's library, with books changed on both sides merged field
    // by field.
    final start = repository.snapshot();
    final startBooks = withCoverRefs(start.books, pool);
    var mine = (books: startBooks, tombstones: start.tombstones);
    if (server != null && !base.isEmpty) {
      final resolved = resolveConflicts(
        base: base.books,
        local: mine.books,
        remote: serverBooks,
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
    var merged = (books: mine.books, tombstones: mine.tombstones);
    if (server != null) {
      final m = mergeLibraries(
        local: serverBooks,
        localTombstones: server.tombstones,
        remote: mine.books,
        remoteTombstones: mine.tombstones,
      );
      merged = (books: m.books, tombstones: m.tombstones);
    }
    final wishes = mergeWishes(server?.wishes ?? const [], settings.allWishes);

    // The server keeps the pictures too: it gets the ones it lacks first, so
    // a library it holds never names a cover it does not have.
    final lacking = await client.missingCovers(coverHashesOf(merged.books));
    await forEachLimited(lacking, (hash) async {
      final picture = pool[hash] ?? await repository.readCover(hash);
      if (picture != null) await client.putCover(hash, picture);
    });

    try {
      await client.putLibrary(
        stored.version,
        encodeSyncPayload(merged.books, merged.tombstones, wishes: wishes),
      );
    } on ServerFailure catch (failure) {
      if (failure.conflict) return null;
      rethrow;
    }

    // The pictures this device does not have yet come from the server,
    // fetched before the library is looked at again: from that snapshot
    // until the library is saved nothing waits, so a change made here
    // meanwhile can't be overwritten.
    final own = await repository.coverHashes();
    final fetch = [
      for (final hash in missingCovers(merged.books, pool))
        if (!own.contains(hash)) hash,
    ];
    await forEachLimited(fetch, (hash) async {
      final picture = await client.getCover(hash);
      if (picture == null) return;
      try {
        pool.put(hash, picture);
      } on FormatException {
        // A damaged picture: the book is left without a cover.
      }
    });

    // Taken here, keeping a change made on this device while syncing; the
    // next sync sends it. A book changed here meanwhile that the merge
    // changed too is merged field by field (the copy from before the sync
    // is what both started from), so neither change is lost.
    // The pictures that came in are kept apart from the books (see
    // cover_store.dart); the books keep references.
    final kept = await keepPoolCovers(merged.books, pool, repository);
    final now = repository.snapshot();
    final nowBooks = withCoverRefs(now.books, pool);
    final before = {for (final book in start.books) book.id: book};
    final touched = [
      for (final book in nowBooks)
        if (before[book.id] case final was?
            when !was.updatedAt.isAtSameMomentAs(book.updatedAt))
          book,
    ];
    var applyBooks = nowBooks;
    if (touched.isNotEmpty) {
      final resolved = resolveConflicts(
        base: {
          for (final book in startBooks)
            book.id: jsonDecode(jsonEncode(book.toJson())) as Map<String, Object?>,
        },
        local: touched,
        remote: merged.books,
        now: _now(),
      );
      if (resolved.isNotEmpty) {
        final byId = {for (final book in resolved) book.id: book};
        applyBooks = [for (final book in nowBooks) byId[book.id] ?? book];
      }
    }
    final applied = mergeLibraries(
      local: merged.books,
      localTombstones: merged.tombstones,
      remote: applyBooks,
      remoteTombstones: now.tombstones,
    );
    // A picture still missing (a book whose picture was lost) is left
    // without a cover rather than holding up the sync.
    final books = withoutLostCovers(applied.books, {
      ...kept,
      ...coverHashesOf(nowBooks),
    });
    final changed = countLibraryChanges(now.books, books);
    await repository.applySynced(books, applied.tombstones);
    settings.mergeWishesFrom(wishes);
    await base.save(merged.books);
    await sync.state.recordLibrarySync(_now());
    return changed;
  }
}
