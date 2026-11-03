import 'library_sync.dart';
import 'server_downloads.dart';
import 'server_client.dart';
import 'server_sync.dart';

/// The book server's parts for the whole app, set up in main.dart. Null in
/// tests and until set up, and the Book server screen then stays hidden.
class BookServer {
  BookServer._();

  static ServerSync? sync;
  static ServerDownloads? downloads;
  static LibrarySync? library;

  /// Syncs everything: your library, your places and bookmarks, then the
  /// books sent here. Returns what to tell you, or null.
  static Future<String?> syncAll() async {
    final sync = BookServer.sync;
    if (sync == null || !sync.state.connected) return null;
    var changed = 0;
    String? problem;
    try {
      changed = await library?.syncNow() ?? 0;
    } on ServerFailure catch (failure) {
      // Places still sync; a server that's away says so there.
      if (!failure.unreachable) problem = failure.message;
    } catch (_) {
      problem = 'Your library could not be synced this time.';
    }
    var moved = 0;
    var came = const <String>[];
    try {
      moved = await sync.syncNow();
      came = await downloads?.receiveSent() ?? const <String>[];
    } catch (_) {
      // Shown by the next sync.
    }
    final text = [
      if (changed > 0)
        '$changed ${changed == 1 ? 'book' : 'books'} changed on your other devices',
      if (came.length == 1) '"${came.single}" was sent here from another device',
      if (came.length > 1) '${came.length} books were sent here from another device',
      if (moved > 0)
        'Carrying on in $moved ${moved == 1 ? 'book' : 'books'} from where '
            'you were on another device',
      ?problem,
    ].join('. ');
    return text.isEmpty ? null : text;
  }
}
