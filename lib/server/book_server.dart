import 'server_downloads.dart';
import 'server_sync.dart';

/// The book server's parts for the whole app, set up in main.dart. Null in
/// tests and until set up, and the Book server screen then stays hidden.
class BookServer {
  BookServer._();

  static ServerSync? sync;
  static ServerDownloads? downloads;
}
