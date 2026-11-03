import 'dart:io';

import 'package:flutter/foundation.dart';

import '../audio/audio_files.dart';
import '../audio/audio_library.dart';
import '../data/book_repository.dart';
import '../data/file_match.dart';
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

/// Brings books from the server into your library: downloads the file,
/// finds the book you already have (or adds it to For later), links the
/// two and takes your saved place.
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
  bool canOpen(ServerBook book) => book.isAudiobook
      ? audio != null && audioDir != null
      : ebooks != null && booksDir != null && ebookFormatOf(book.fileName) != null;

  /// The book in your library that has [book]'s file on this device.
  String? localBookFor(ServerBook book) {
    final id = state.bookIdFor(book.id);
    if (id == null || repository.byId(id)?.deletedAt != null) return null;
    if (repository.byId(id) == null) return null;
    return _hasFile(id, book) ? id : null;
  }

  bool _hasFile(String bookId, ServerBook book) => book.isAudiobook
      ? audio?.linkFor(bookId) != null
      : ebooks?.linkFor(bookId) != null;

  /// The book in your library this is: the one linked before, or one with
  /// the same title and author that isn't linked to another server book.
  String? _sameBook(ServerBook book) {
    final linked = state.bookIdFor(book.id);
    if (linked != null && repository.byId(linked)?.deletedAt == null &&
        repository.byId(linked) != null) {
      return linked;
    }
    final matches = findMatchingBooks(
      repository.books,
      title: book.title,
      author: book.author,
      limit: 3,
    );
    for (final match in matches) {
      if (match.score < 95) break;
      final other = state.linkFor(match.book.id);
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
    final dir = book.isAudiobook ? audioDir! : booksDir!;
    final safe = book.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'server-$safe-${_now().millisecondsSinceEpoch}.${book.format}',
    );
    try {
      final bytes = await client.download(
        book.id,
        file,
        onProgress: (received, total) {
          _active[book.id] = total == null || total == 0 ? null : received / total;
          notifyListeners();
        },
      );
      // Added only once the file is here, so a failed download leaves no
      // empty book behind.
      bookId ??= await _addBook(book);
      if (book.isAudiobook) {
        final location = audioLocationFor(file.path);
        final files = audioFiles;
        AudioLink? link;
        if (files != null) {
          try {
            link = await buildAudioLink(
              files,
              [PickedFile(location: location, name: book.fileName)],
            );
          } catch (_) {
            // Chapters unread; the file still plays.
          }
        }
        await audio!.setLink(
          bookId,
          link ??
              AudioLink(tracks: [
                AudioTrack(
                  location: location,
                  name: book.fileName,
                  lengthMs: book.durationMs,
                ),
              ]),
        );
      } else {
        final old = ebooks!.linkFor(bookId);
        await ebooks!.setLink(
          bookId,
          EbookLink(
            path: file.path,
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
      await _deleteQuietly(file);
      return DownloadResult(problem: failure.message);
    } on FileSystemException {
      await _deleteQuietly(file);
      return const DownloadResult(
        problem: 'The book could not be saved. Is there room on this device?',
      );
    } finally {
      _active.remove(book.id);
      notifyListeners();
    }
  }

  Future<String> _addBook(ServerBook book) async {
    await repository.add(
      title: book.title,
      author: book.author,
      shelf: Shelf.forLater,
      format: book.isAudiobook ? BookFormat.audiobook : BookFormat.ebook,
    );
    final id = repository.books.first.id;
    if (book.series != null) {
      await repository.setSeries(id, book.series, book.seriesIndex?.round());
    }
    return id;
  }

  /// Links the two and takes your saved place and bookmarks.
  Future<void> _link(String bookId, ServerBook book) async {
    final before = state.linkFor(bookId);
    if (before == null || before.serverId != book.id) {
      await state.setLink(
        bookId,
        ServerLink(
          serverId: book.id,
          kind: book.kind,
          durationMs: book.durationMs,
        ),
      );
    }
    final progress = book.progress;
    if (progress != null) await sync.applyRemote(bookId, progress);
    if (book.isAudiobook) {
      try {
        await sync.syncBookmarks(bookId);
      } on ServerFailure {
        // Next sync.
      }
    }
  }

  /// Deletes downloaded audiobooks no book uses any more (after you removed
  /// a book's audio). Never while a download is running.
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
    await for (final entry in dir.list()) {
      if (entry is! File || _active.isNotEmpty) continue;
      if (!used.contains(audioLocationFor(entry.path))) {
        await _deleteQuietly(entry);
      }
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Left behind; cleaned up later.
    }
  }
}
