import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/book.dart';

// The same file is in the Android app.

/// A cover picture kept inside a book is a data: address of tens of kilobytes.
/// Sent with every book, a library of a thousand books is far too big to
/// sync. So a sync message carries a short reference instead, and the
/// pictures travel on their own, only to a device that does not have them.
const coverRefPrefix = 'cover:';

const _hashLength = 32;

final _hexHash = RegExp(r'^[0-9a-f]{32}$');

/// Whether [url] is a cover picture kept inside a book.
bool isDataCoverUrl(String? url) => url != null && url.startsWith('data:image/');

/// The pictures a data: address holds are hashed once each: a sync hashes
/// every cover in the library.
final _hashes = <String, String>{};
const _maxHashes = 20000;

/// A short name for a cover picture: the start of the SHA-256 of its data:
/// address. The same picture always has the same name, on any device.
String coverHash(String dataUrl) {
  final known = _hashes[dataUrl];
  if (known != null) return known;
  if (_hashes.length >= _maxHashes) _hashes.clear();
  return _hashes[dataUrl] =
      sha256.convert(utf8.encode(dataUrl)).toString().substring(0, _hashLength);
}

/// Whether [text] is a cover's short name.
bool isCoverHash(String text) => _hexHash.hasMatch(text);

/// The reference that stands for a cover in a sync message.
String coverRef(String hash) => '$coverRefPrefix$hash';

/// The short name in a cover reference, or null if [url] is not one.
String? hashOfCoverRef(String? url) {
  if (url == null || !url.startsWith(coverRefPrefix)) return null;
  final hash = url.substring(coverRefPrefix.length);
  return isCoverHash(hash) ? hash : null;
}

/// Thrown when a sync message names covers this device does not have.
class MissingCovers implements Exception {
  const MissingCovers(this.hashes);

  final List<String> hashes;

  @override
  String toString() => 'Missing ${hashes.length} covers.';
}

/// The cover pictures one device holds while it syncs, by short name.
class CoverPool {
  final Map<String, String> _byHash = {};

  int get length => _byHash.length;

  Iterable<String> get hashes => _byHash.keys;

  /// Every picture held.
  Iterable<String> get pictures => _byHash.values;

  /// The total size of the pictures, in characters.
  int get size => _byHash.values.fold(0, (sum, p) => sum + p.length);

  bool has(String hash) => _byHash.containsKey(hash);

  String? operator [](String hash) => _byHash[hash];

  /// Keeps a picture that is already in a book. Returns its short name.
  String add(String dataUrl) {
    final hash = coverHash(dataUrl);
    _byHash[hash] = dataUrl;
    return hash;
  }

  /// Keeps a picture another device sent under [hash]. Throws a
  /// [FormatException] when it is not a picture or has another name, so a
  /// damaged or wrong one never replaces a cover.
  void put(String hash, String dataUrl) {
    if (!isCoverHash(hash) || !isDataCoverUrl(dataUrl)) {
      throw const FormatException('Not a cover.');
    }
    if (coverHash(dataUrl) != hash) {
      throw const FormatException('The cover does not match its name.');
    }
    _byHash[hash] = dataUrl;
  }

  /// Keeps pictures that are already in books.
  void addAll(Iterable<String> dataUrls) {
    for (final url in dataUrls) {
      add(url);
    }
  }

  void clear() => _byHash.clear();
}

/// The books with each cover picture swapped for a reference, keeping the
/// pictures in [pool]. A book without a picture of its own (no cover, or a
/// web address) is left as it is.
List<Book> withCoverRefs(List<Book> books, CoverPool pool) => [
      for (final book in books)
        if (isDataCoverUrl(book.coverUrl))
          book.copyWith(coverUrl: () => coverRef(pool.add(book.coverUrl!)))
        else
          book,
    ];

/// The short names of the covers [books] refer to that [pool] does not have.
List<String> missingCovers(Iterable<Book> books, CoverPool pool) {
  final missing = <String>{};
  for (final book in books) {
    final hash = hashOfCoverRef(book.coverUrl);
    if (hash != null && !pool.has(hash)) missing.add(hash);
  }
  return missing.toList()..sort();
}

/// The short names of every cover [books] refer to.
List<String> coverHashesOf(Iterable<Book> books) {
  final all = <String>{};
  for (final book in books) {
    final hash = hashOfCoverRef(book.coverUrl);
    if (hash != null) all.add(hash);
  }
  return all.toList()..sort();
}

/// The books with each reference swapped back for its picture. Throws
/// [MissingCovers] when [pool] lacks one, so a reference is never saved as a
/// cover.
List<Book> withCoverPictures(List<Book> books, CoverPool pool) {
  final missing = missingCovers(books, pool);
  if (missing.isNotEmpty) throw MissingCovers(missing);
  return [
    for (final book in books)
      if (hashOfCoverRef(book.coverUrl) case final hash?)
        book.copyWith(coverUrl: () => pool[hash])
      else
        book,
  ];
}

/// A book as saved JSON with its cover picture swapped for a reference. For
/// the copy of the last sync kept in a file, which an older app saved with
/// the pictures in it.
Map<String, Object?> jsonWithCoverRef(Map<String, Object?> book) {
  final url = book['coverUrl'];
  if (url is String && isDataCoverUrl(url)) {
    return {...book, 'coverUrl': coverRef(coverHash(url))};
  }
  return book;
}

/// Runs [action] on each of [items], a few at a time.
Future<void> forEachLimited<T>(
  Iterable<T> items,
  Future<void> Function(T item) action, {
  int at = 4,
}) async {
  final queue = items.toList();
  var next = 0;
  Future<void> worker() async {
    while (next < queue.length) {
      final item = queue[next++];
      await action(item);
    }
  }

  await Future.wait([for (var i = 0; i < at; i++) worker()]);
}
