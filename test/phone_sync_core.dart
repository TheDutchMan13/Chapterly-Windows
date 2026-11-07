// The same file as lib/data/phone_sync_core.dart in the Android app.

import 'package:chapterly/models/book.dart';
import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';

/// The most cover pictures a PC may leave on this phone before a sync uses
/// them, in characters (about 150 MB).
const _maxReceivedCovers = 150 * 1000 * 1000;

/// What the phone does when the PC syncs: merges the PC's library with its
/// own and keeps the cover pictures the PC sends. Apart from the server that
/// calls it, so the PC app's tests can run the same code.
class PhoneSyncCore implements SyncEndpoint {
  PhoneSyncCore({required this.repository, required this.settings});

  final BookRepository repository;
  final AppSettings settings;

  /// Cover pictures the PC sent ahead of a sync. They go into the books when
  /// the sync is done.
  final CoverPool _received = CoverPool();

  /// The covers of the books on this phone.
  CoverPool _own() {
    final pool = CoverPool();
    for (final book in repository.snapshot().books) {
      if (isDataCoverUrl(book.coverUrl)) pool.add(book.coverUrl!);
    }
    return pool;
  }

  @override
  Future<List<String>> missing(List<String> hashes) async {
    final own = _own();
    return [
      for (final hash in hashes)
        if (!own.has(hash) && !_received.has(hash)) hash,
    ];
  }

  @override
  Future<void> put(String hash, String dataUrl) async {
    if (_received.size + dataUrl.length > _maxReceivedCovers) {
      throw const FormatException('Too many covers waiting on this phone.');
    }
    _received.put(hash, dataUrl);
  }

  @override
  Future<String?> get(String hash) async => _own()[hash] ?? _received[hash];

  @override
  Future<String> handleSync(String body) async {
    try {
      final remote = decodeSyncPayload(body);
      final local = repository.snapshot();
      // The merge works on cover references. The pictures are this phone's
      // own and the ones the PC sent ahead; a message that still has them
      // inside a book (an old library on a server) is read the same way.
      final pool = CoverPool()..addAll(_received.pictures);
      final localBooks = withCoverRefs(local.books, pool);
      final remoteBooks = withCoverRefs(remote.books, pool);
      final lacking = missingCovers(remoteBooks, pool);
      if (lacking.isNotEmpty) throw MissingCovers(lacking);
      final merged = mergeLibraries(
        local: localBooks,
        localTombstones: local.tombstones,
        remote: remoteBooks,
        remoteTombstones: remote.tombstones,
      );
      final books = withCoverPictures(merged.books, pool);
      final changed = _countChanges(local.books, books);
      await repository.applySynced(books, merged.tombstones);
      _received.clear();
      // The wish list: the newer copy of each wish wins.
      settings.mergeWishesFrom(remote.wishes);
      settings.recordSync(at: DateTime.now(), changed: changed);
      return encodeSyncPayload(
        merged.books,
        merged.tombstones,
        wishes: settings.allWishes,
      );
    } on MissingCovers {
      rethrow;
    } on FormatException catch (error) {
      settings.recordSyncError(error.message);
      rethrow;
    } catch (_) {
      settings.recordSyncError('The sync could not be finished.');
      rethrow;
    }
  }

  /// How many books on this phone were added, changed or removed.
  int _countChanges(List<Book> before, List<Book> after) {
    final old = {for (final book in before) book.id: book};
    final kept = <String>{};
    var changed = 0;
    for (final book in after) {
      kept.add(book.id);
      final previous = old[book.id];
      if (previous == null || previous.updatedAt != book.updatedAt) changed++;
    }
    for (final id in old.keys) {
      if (!kept.contains(id)) changed++;
    }
    return changed;
  }
}
