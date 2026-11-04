import 'dart:io';

import 'package:flutter/foundation.dart';

import '../audio/audio_files.dart';
import '../audio/audio_library.dart';
import '../data/book_repository.dart';
import '../data/file_match.dart';
import '../ebook/ebook_files.dart';
import '../ebook/ebook_library.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'server_client.dart';
import 'server_platform.dart';
import 'server_state.dart';
import 'server_sync.dart';

// The same file is in the Android app.

/// What happened when you asked for a book.
class DownloadResult {
  const DownloadResult({this.bookId, this.problem, this.matchedExisting = false});

  /// The book in your library that now has the file.
  final String? bookId;

  /// Why it didn't work, in words to show.
  final String? problem;

  /// The book was already in your library with a file of its own, so
  /// nothing was downloaded; the two are linked so your place syncs.
  final bool matchedExisting;
}

/// A book file from the server on this device, for the Downloads screen.
class DownloadedBook {
  const DownloadedBook({
    required this.bookId,
    required this.title,
    required this.kind,
    required this.bytes,
  });

  final String bookId;
  final String title;

  /// "ebook" or "audiobook".
  final String kind;

  /// The space its files take on this device.
  final int bytes;

  bool get isAudiobook => kind == 'audiobook';
}

/// Brings books from the server into your library: downloads the file,
/// finds the book you already have (or adds it to For later), links the
/// two and takes your saved place.
/// The formats a book from the server may have. Its file is named by its
/// format, so anything else is refused.
const serverFormats = {'epub', 'pdf', 'm4b', 'm4a', 'mp3'};

/// Whether [path] is inside the folder [dir] (not the folder itself).
bool isInside(String dir, String path) {
  final sep = Platform.pathSeparator;
  final root = dir.endsWith(sep) ? dir : '$dir$sep';
  final parts = path.split(RegExp(r'[\\/]'));
  return path.startsWith(root) && !parts.contains('..') && !parts.contains('.');
}

/// A track's file name: numbered, so they play in the server's order, with
/// nothing that Windows forbids or that could leave the folder.
String safeTrackName(int index, String name) {
  var clean = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  if (clean.length > 150) clean = clean.substring(0, 150);
  if (clean.isEmpty || clean.replaceAll('.', '').isEmpty) clean = 'track';
  return '${(index + 1).toString().padLeft(3, '0')} $clean';
}

class ServerDownloads extends ChangeNotifier {
  ServerDownloads({
    required this.sync,
    required this.repository,
    this.ebooks,
    this.booksDir,
    this.audio,
    this.audioFiles,
    this.audioDir,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ServerSync sync;
  final BookRepository repository;
  final EbookLibrary? ebooks;
  final Directory? booksDir;
  final AudioLibrary? audio;
  final AudioFiles? audioFiles;

  /// Where downloaded audiobooks are kept.
  final Directory? audioDir;
  final DateTime Function() _now;

  final _active = <String, double?>{};

  ServerState get state => sync.state;

  bool isDownloading(String serverId) => _active.containsKey(serverId);

  /// How far a download is, from 0 to 1, or null when not known.
  double? progressOf(String serverId) => _active[serverId];

  /// Whether this device can open a book of this kind.
  bool canOpen(ServerBook book) =>
      serverFormats.contains(book.format) &&
      (book.isAudiobook
          ? audio != null && audioDir != null
          : ebooks != null &&
              booksDir != null &&
              ebookFormatOf(book.fileName) != null);

  /// The book in your library that has [book]'s file on this device.
  String? localBookFor(ServerBook book) {
    final id = state.bookIdFor(book.id);
    if (id == null || !_inLibrary(id)) return null;
    return _hasFile(id, book) ? id : null;
  }

  bool _inLibrary(String bookId) {
    final book = repository.byId(bookId);
    return book != null && book.deletedAt == null;
  }

  bool _hasFile(String bookId, ServerBook book) => book.isAudiobook
      ? audio?.linkFor(bookId) != null
      : ebooks?.linkFor(bookId) != null;

  /// The book in your library this is: the one linked before, or one with
  /// the same title and author whose ebook (or audiobook, for an
  /// audiobook) isn't linked to another server book.
  String? _sameBook(ServerBook book) {
    final linked = state.bookIdFor(book.id);
    if (linked != null && _inLibrary(linked)) return linked;
    final matches = findMatchingBooks(
      repository.books,
      title: book.title,
      author: book.author,
      limit: 3,
    );
    for (final match in matches) {
      if (match.score < 95) break;
      final other = state.linkFor(match.book.id, book.kind);
      if (other == null || other.serverId == book.id) return match.book.id;
    }
    return null;
  }

  Future<DownloadResult> download(ServerBook book) async {
    final client = sync.client;
    if (client == null) {
      return const DownloadResult(problem: 'Connect to your book server first.');
    }
    if (!canOpen(book)) {
      return DownloadResult(
        problem: book.isAudiobook
            ? 'This device cannot play audiobooks.'
            : 'Chapterly opens EPUB and PDF files; this is ${book.format.toUpperCase()}.',
      );
    }
    if (isDownloading(book.id)) return const DownloadResult();

    var bookId = _sameBook(book);
    if (bookId != null && _hasFile(bookId, book)) {
      await _link(bookId, book);
      return DownloadResult(bookId: bookId, matchedExisting: true);
    }

    _active[book.id] = null;
    notifyListeners();
    String? created;
    final dir = book.isAudiobook ? audioDir! : booksDir!;
    final safe = book.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final sep = Platform.pathSeparator;
    final base = '${dir.path}${sep}server-$safe-${_now().millisecondsSinceEpoch}';
    // An audiobook of several files goes in a folder of its own.
    final FileSystemEntity target =
        book.isMultiTrack ? Directory(base) : File('$base.${book.format}');
    // Only ever inside the books folder, whatever the server sends.
    if (!isInside(dir.path, target.path)) {
      _active.remove(book.id);
      notifyListeners();
      return const DownloadResult(
        problem: 'The server sent a name that is not safe.',
      );
    }
    void progress(double? value) {
      _active[book.id] = value;
      notifyListeners();
    }

    try {
      final picked = <PickedFile>[];
      final lengths = <int?>[];
      var bytes = 0;
      if (target is Directory) {
        final tracks = await client.tracks(book.id);
        if (tracks.isEmpty) {
          throw const ServerFailure('This audiobook has no files on the server.');
        }
        final total = tracks.fold<int>(0, (sum, t) => sum + t.size);
        var done = 0;
        for (final track in tracks) {
          // Numbered, so they play in the server's order.
          final name = safeTrackName(track.index, track.name);
          final file = File('${target.path}$sep$name');
          final got = await client.downloadTrack(
            book.id,
            track.index,
            file,
            onProgress: (received, _) =>
                progress(total == 0 ? null : (done + received) / total),
          );
          done += got;
          bytes += got;
          picked.add(PickedFile(location: audioLocationFor(file.path), name: name));
          lengths.add(track.durationMs);
        }
      } else {
        final file = target as File;
        bytes = await client.download(
          book.id,
          file,
          onProgress: (received, total) =>
              progress(total == null || total == 0 ? null : received / total),
        );
        picked.add(PickedFile(location: audioLocationFor(file.path), name: book.fileName));
        lengths.add(book.durationMs);
      }
      // Added only once the files are here, so a failed download leaves no
      // empty book behind.
      if (bookId == null) {
        bookId = await _addBook(book);
        created = bookId;
      }
      if (book.isAudiobook) {
        final files = audioFiles;
        AudioLink? link;
        if (files != null) {
          try {
            link = await buildAudioLink(files, picked);
          } catch (_) {
            // Lengths and chapters unread; the files still play.
          }
        }
        await audio!.setLink(
          bookId,
          link ??
              AudioLink(tracks: [
                for (var i = 0; i < picked.length; i++)
                  AudioTrack(
                    location: picked[i].location,
                    name: picked[i].name,
                    lengthMs: lengths[i],
                  ),
              ]),
        );
      } else {
        final old = ebooks!.linkFor(bookId);
        await ebooks!.setLink(
          bookId,
          EbookLink(
            path: target.path,
            name: book.fileName,
            bytes: bytes,
            format: ebookFormatOf(book.fileName)!,
            addedAt: _now(),
            prefs: old?.prefs,
            days: old?.days ?? const [],
          ),
        );
      }
      await _link(bookId, book);
      return DownloadResult(bookId: bookId);
    } on ServerFailure catch (failure) {
      await _undo(target, created, book);
      return DownloadResult(problem: failure.message);
    } on FileSystemException {
      await _undo(target, created, book);
      return const DownloadResult(
        problem: 'The book could not be saved. Is there room on this device?',
      );
    } catch (_) {
      await _undo(target, created, book);
      return const DownloadResult(problem: 'The book could not be added.');
    } finally {
      _active.remove(book.id);
      notifyListeners();
    }
  }

  /// Leaves nothing behind after a download that didn't work out.
  Future<void> _undo(FileSystemEntity target, String? created, ServerBook book) async {
    await _deleteQuietly(target);
    if (created == null) return;
    try {
      if (book.isAudiobook) {
        await audio?.remove(created);
      } else {
        await ebooks?.remove(created);
      }
      await state.unlink(book.id);
      await repository.deleteForever(created);
    } catch (_) {
      // As much as could be undone.
    }
  }

  Future<String> _addBook(ServerBook book) async {
    final id = await repository.add(
      title: book.title,
      author: book.author,
      shelf: Shelf.forLater,
      format: book.isAudiobook ? BookFormat.audiobook : BookFormat.ebook,
    );
    if (book.series != null) {
      await repository.setSeries(id, book.series, book.seriesIndex?.round());
    }
    return id;
  }

  /// Links the two and takes your saved place and bookmarks.
  Future<void> _link(String bookId, ServerBook book) async {
    final before = state.linkOf(book.id);
    if (before == null || before.bookId != bookId) {
      await state.setLink(ServerLink(
        serverId: book.id,
        bookId: bookId,
        kind: book.kind,
        durationMs: book.durationMs,
      ));
    }
    final link = state.linkOf(book.id)!;
    final progress = book.progress;
    if (progress != null) await sync.applyRemote(link, progress);
    if (book.isAudiobook) {
      try {
        await sync.syncBookmarks(link);
      } on ServerFailure {
        // Next sync.
      }
    }
  }

  // ---- Sending to your other devices ----

  /// Puts [book] on your other devices. Returns a problem, or null.
  Future<String?> sendToOthers(ServerBook book) async {
    final client = sync.client;
    if (client == null) return 'Connect to your book server first.';
    try {
      await client.sendBook(book.id, state.device);
      return null;
    } on ServerFailure catch (failure) {
      return failure.message;
    }
  }

  /// Downloads the books your other devices sent here. Returns the titles
  /// of the ones that came. A book that couldn't come waits for next time.
  Future<List<String>> receiveSent() async {
    final client = sync.client;
    if (client == null) return const [];
    final List<ServerBook> waiting;
    try {
      waiting = await client.waitingSends(state.device);
    } on ServerFailure {
      return const [];
    }
    final came = <String>[];
    for (final book in waiting) {
      try {
        if (localBookFor(book) != null || !canOpen(book)) {
          await client.doneSend(book.id, state.device);
          continue;
        }
        final result = await download(book);
        if (result.problem == null && result.bookId != null) {
          await client.doneSend(book.id, state.device);
          came.add(book.title);
        }
      } on ServerFailure catch (failure) {
        if (failure.unreachable) break;
      }
    }
    return came;
  }

  // ---- What's on this device ----

  /// Books with a file from the server on this device, biggest first.
  Future<List<DownloadedBook>> downloaded() async {
    final found = <DownloadedBook>[];
    for (final link in state.links) {
      final book = repository.byId(link.bookId);
      if (book == null || book.deletedAt != null) continue;
      final paths = <String>[
        if (link.isAudiobook)
          for (final track in audio?.linkFor(link.bookId)?.tracks ?? const <AudioTrack>[])
            _pathOf(track.location)
        else if (ebooks?.linkFor(link.bookId) case final file?)
          file.path,
      ];
      var bytes = 0;
      for (final path in paths) {
        try {
          bytes += await File(path).length();
        } catch (_) {
          // Gone.
        }
      }
      if (paths.isEmpty) continue;
      found.add(DownloadedBook(
        bookId: link.bookId,
        title: book.title,
        kind: link.kind,
        bytes: bytes,
      ));
    }
    found.sort((a, b) => b.bytes.compareTo(a.bytes));
    return found;
  }

  static String _pathOf(String location) =>
      location.startsWith('file:') ? Uri.parse(location).toFilePath() : location;

  /// Deletes a book's file from this device. The book stays in your
  /// library, and can be downloaded again.
  Future<void> removeFile(DownloadedBook item) async {
    if (item.isAudiobook) {
      await audio?.remove(item.bookId);
      await cleanUp();
    } else if (ebooks != null) {
      await removeBookFile(ebooks!, item.bookId);
    }
    notifyListeners();
  }

  /// Deletes downloaded audiobooks no book uses any more (after you removed
  /// a book's audio), and folders left empty. Never while a download runs.
  Future<void> cleanUp() async {
    final dir = audioDir;
    final library = audio;
    if (dir == null || library == null || _active.isNotEmpty) return;
    if (!await dir.exists()) return;
    final used = <String>{
      for (final book in repository.allBooks)
        for (final track in library.linkFor(book.id)?.tracks ?? const <AudioTrack>[])
          track.location,
    };
    final folders = <Directory>[];
    await for (final entry in dir.list(recursive: true)) {
      if (_active.isNotEmpty) return;
      if (entry is Directory) {
        folders.add(entry);
      } else if (entry is File && !used.contains(audioLocationFor(entry.path))) {
        await _deleteQuietly(entry);
      }
    }
    // Deepest first, so a folder emptied by the line above goes too.
    folders.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final folder in folders) {
      try {
        if (await folder.list().isEmpty) await folder.delete();
      } catch (_) {
        // Left behind.
      }
    }
  }

  static Future<void> _deleteQuietly(FileSystemEntity entry) async {
    try {
      if (await entry.exists()) await entry.delete(recursive: true);
    } catch (_) {
      // Left behind; cleaned up later.
    }
  }
}
