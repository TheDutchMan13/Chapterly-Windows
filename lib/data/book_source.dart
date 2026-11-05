import '../audio/listening.dart';
import '../ebook/ebook_reading.dart';
import '../models/book.dart';
import '../server/book_server.dart';
import '../server/server_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// The book's id on your book server, when it is linked to a book there.
String? serverIdFor(String bookId) {
  final sync = BookServer.sync;
  if (sync == null || !sync.state.connected) return null;
  for (final link in sync.state.links) {
    if (link.bookId == bookId) return link.serverId;
  }
  return null;
}

/// The name of the file (or audiobook folder) linked to the book on this
/// device, or null when none is.
String? linkedFileName(String bookId) {
  final ebook = EbookReading.library?.linkFor(bookId);
  if (ebook != null && ebook.name.trim().isNotEmpty) return ebook.name;
  final tracks = Listening.controller?.library.linkFor(bookId)?.tracks;
  if (tracks == null || tracks.isEmpty) return null;
  if (tracks.length == 1) return tracks.first.name;
  final folder = folderOf(tracks.first.location);
  return folder ?? '${tracks.first.name} and ${tracks.length - 1} more files';
}

/// The folder a file is in, from a Windows or Linux path. Null for anything
/// else (an Android content:// address, say).
String? folderOf(String location) {
  if (location.contains('://')) return null;
  final parts = location.split(RegExp(r'[\\/]'));
  if (parts.length < 2) return null;
  final folder = parts[parts.length - 2].trim();
  return folder.isEmpty || folder.endsWith(':') ? null : folder;
}

/// The book's file name on your book server, asked of the server. Null when
/// it is not linked, the server is away, or the server is older than 1.5.
Future<String?> serverFileName(String bookId) async {
  final serverId = serverIdFor(bookId);
  final client = BookServer.sync?.client;
  if (serverId == null || client == null) return null;
  try {
    return (await client.book(serverId)).originalName;
  } on ServerFailure {
    return null;
  } catch (_) {
    return null;
  }
}

/// The best original name known without asking the server: the one kept
/// with the book, or the linked file's name.
String? knownOriginalName(Book book) =>
    book.origin?.name ?? linkedFileName(book.id);

/// Fixes the book's title, author and series on your book server too, when
/// it is linked to one. Returns a problem to show, or null.
Future<String?> correctOnServer(Book book) async {
  final serverId = serverIdFor(book.id);
  final client = BookServer.sync?.client;
  if (serverId == null || client == null) return null;
  try {
    final series = book.series;
    await client.correctBook(
      serverId,
      title: book.title,
      author: book.author,
      series: series,
      seriesIndex: series == null ? null : book.seriesNumber?.toDouble(),
    );
    return null;
  } on ServerFailure catch (failure) {
    return failure.unreachable
        ? 'Saved here. The book server could not be reached, so the name '
            'there is unchanged.'
        : 'Saved here. The book server did not take the change: '
            '${failure.message}';
  } catch (_) {
    return 'Saved here. The book server did not take the change.';
  }
}
