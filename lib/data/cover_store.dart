// The same file is in both apps (lib/data/cover_store.dart).

import 'dart:isolate';
import 'dart:typed_data';

import '../models/book.dart';
import 'sync_covers.dart';

/// Cover pictures kept apart from the books, by short name (see
/// [coverHash]). A book holds only a reference to its picture
/// (`cover:<hash>`, as in a sync), so the library in memory stays small and
/// a sync never has to hash the pictures again.
abstract interface class CoverStore {
  /// The picture (a data: address) with this short name, or null.
  Future<String?> readCover(String hash);

  /// Keeps [dataUrl] under [hash] (see [coverHash]).
  Future<void> writeCover(String hash, String dataUrl);

  /// The short names of every picture kept.
  Future<Set<String>> coverHashes();

  /// Removes the pictures no book refers to any more.
  Future<void> removeCoversExcept(Set<String> keep);
}

/// Whether [url] is a picture of the book's own: inside it, or kept apart.
bool isOwnCover(String? url) =>
    isDataCoverUrl(url) || hashOfCoverRef(url) != null;

/// The picture bytes of a data: address, or null.
Uint8List? dataUrlBytes(String url) {
  if (!isDataCoverUrl(url)) return null;
  try {
    return UriData.parse(url).contentAsBytes();
  } on FormatException {
    return null;
  }
}

/// [books] with each picture inside a book moved to [store] and replaced by
/// its reference. Many pictures are hashed on a background thread.
Future<List<Book>> keepCoversApart(List<Book> books, CoverStore store) async {
  final urls = <String>[
    for (final book in books)
      if (isDataCoverUrl(book.coverUrl)) book.coverUrl!,
  ];
  if (urls.isEmpty) return books;
  final unique = urls.toSet().toList();
  final hashes = unique.length > 8
      ? await Isolate.run(() => [for (final url in unique) coverHash(url)])
      : [for (final url in unique) coverHash(url)];
  final byUrl = <String, String>{};
  final have = await store.coverHashes();
  for (var i = 0; i < unique.length; i++) {
    byUrl[unique[i]] = hashes[i];
    if (have.add(hashes[i])) await store.writeCover(hashes[i], unique[i]);
  }
  return [
    for (final book in books)
      if (byUrl[book.coverUrl] case final hash?)
        book.copyWith(coverUrl: () => coverRef(hash))
      else
        book,
  ];
}

/// [book] with its picture, if it holds one, moved to [store].
Future<Book> keepCoverApart(Book book, CoverStore store) async =>
    (await keepCoversApart([book], store)).single;

/// [books] with each reference swapped back for its picture from [store],
/// for a backup or an export that must hold the pictures. A picture that is
/// gone leaves the book without a cover.
Future<List<Book>> withStoredPictures(
  List<Book> books,
  CoverStore store,
) async {
  final out = <Book>[];
  for (final book in books) {
    final hash = hashOfCoverRef(book.coverUrl);
    if (hash == null) {
      out.add(book);
      continue;
    }
    final picture = await store.readCover(hash);
    out.add(book.copyWith(coverUrl: () => picture));
  }
  return out;
}

/// After a sync: keeps in [store] the pictures from [pool] that [books]
/// refer to and [store] lacks. Returns the short names [store] now holds.
Future<Set<String>> keepPoolCovers(
  Iterable<Book> books,
  CoverPool pool,
  CoverStore store,
) async {
  final have = await store.coverHashes();
  for (final hash in coverHashesOf(books)) {
    if (have.contains(hash)) continue;
    final picture = pool[hash];
    if (picture == null) continue;
    await store.writeCover(hash, picture);
    have.add(hash);
  }
  return have;
}

/// [books] with a reference to a picture that is not in [kept] dropped, so
/// a book whose picture was lost has no cover rather than a broken one.
List<Book> withoutLostCovers(List<Book> books, Set<String> kept) => [
      for (final book in books)
        if (hashOfCoverRef(book.coverUrl) case final hash?
            when !kept.contains(hash))
          book.copyWith(coverUrl: () => null)
        else
          book,
    ];

/// A store kept in memory, for tests and for a library that is not saved.
class MemoryCoverStore implements CoverStore {
  final Map<String, String> _pictures = {};

  @override
  Future<String?> readCover(String hash) async => _pictures[hash];

  @override
  Future<void> writeCover(String hash, String dataUrl) async {
    _pictures[hash] = dataUrl;
  }

  @override
  Future<Set<String>> coverHashes() async => _pictures.keys.toSet();

  @override
  Future<void> removeCoversExcept(Set<String> keep) async {
    _pictures.removeWhere((hash, _) => !keep.contains(hash));
  }
}

/// Cover pictures for the screen. The library on the screen sets [source];
/// a picture is read from it when a cover is shown, and the last few are
/// kept. A short name is the same picture everywhere, so one cache serves
/// every profile.
class CoverImages {
  CoverImages._();

  /// Reads a picture by its short name: the open library's.
  static Future<String?> Function(String hash)? source;

  static const _max = 200;
  static final _bytes = <String, Uint8List>{};
  static final _loading = <String, Future<Uint8List?>>{};

  /// The picture's bytes if they were read lately.
  static Uint8List? cached(String hash) {
    final bytes = _bytes.remove(hash);
    if (bytes != null) _bytes[hash] = bytes;
    return bytes;
  }

  /// Reads the picture's bytes, once however often it is asked for.
  static Future<Uint8List?> load(String hash) {
    final known = cached(hash);
    if (known != null) return Future.value(known);
    return _loading[hash] ??= () async {
      try {
        final url = await source?.call(hash);
        final bytes = url == null ? null : dataUrlBytes(url);
        if (bytes != null) {
          if (_bytes.length >= _max) _bytes.remove(_bytes.keys.first);
          _bytes[hash] = bytes;
        }
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _loading.remove(hash);
      }
    }();
  }

  /// Forgets every picture read, for a library that was replaced.
  static void clear() => _bytes.clear();
}

/// The bytes of a book's own picture: inside it, or kept apart. Null for a
/// web address or no cover.
Future<Uint8List?> ownCoverBytes(String? url) async {
  if (url == null) return null;
  if (isDataCoverUrl(url)) return dataUrlBytes(url);
  final hash = hashOfCoverRef(url);
  return hash == null ? null : CoverImages.load(hash);
}

/// [ownCoverBytes] as a data: address.
Future<String?> ownCoverDataUrl(String? url) async {
  if (url == null) return null;
  if (isDataCoverUrl(url)) return url;
  final hash = hashOfCoverRef(url);
  if (hash == null) return null;
  try {
    return await CoverImages.source?.call(hash);
  } catch (_) {
    return null;
  }
}
