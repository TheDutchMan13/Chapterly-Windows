import 'dart:convert';

import '../models/book.dart';
import 'wish_list.dart';

/// The version of the sync messages. The phone and the PC must agree on it.
/// Version 2: books carry a cover reference instead of the picture (see
/// sync_covers.dart). An app on version 1 asks for the other to be updated.
const syncProtocolVersion = 2;

/// What this app's book data can carry, sent with every sync message. An
/// older app sends none of these, and ignores this list when it reads it.
/// "audioBookmarks": the book's audiobook bookmarks are kept and sent back.
/// "wishes": the wish list is sent in `wishes` and merged.
const syncFeatures = ['audioBookmarks', 'wishes'];

/// The port the phone listens on for sync. Shown in Settings.
const defaultSyncPort = 8765;

class SyncPayload {
  const SyncPayload({
    required this.books,
    required this.tombstones,
    this.features = const {},
    this.wishes = const [],
  });

  final List<Book> books;
  final Map<String, DateTime> tombstones;

  /// What the other app's book data can carry (see [syncFeatures]).
  final Set<String> features;

  /// The other device's wish list, deleted wishes included. Empty from an
  /// app that has no wish list.
  final List<Wish> wishes;
}

const _notSync = FormatException('Not a Chapterly sync message.');

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The library and the list of permanently deleted books, as JSON.
String encodeSyncPayload(
  List<Book> books,
  Map<String, DateTime> tombstones, {
  List<String> features = syncFeatures,
  List<Wish> wishes = const [],
}) =>
    jsonEncode({
      'app': 'chapterly',
      'protocol': syncProtocolVersion,
      'features': features,
      'wishes': [for (final wish in wishes) wish.toJson()],
      'books': [for (final book in books) book.toJson()],
      'tombstones': {
        for (final entry in tombstones.entries)
          entry.key: entry.value.toIso8601String(),
      },
    });

/// Reads a message made by [encodeSyncPayload]. Throws [FormatException] with
/// a message for the user if it is not a valid Chapterly sync message.
SyncPayload decodeSyncPayload(String text) {
  final data = _tryJson(text);
  if (data is! Map<String, dynamic> || data['app'] != 'chapterly') {
    throw _notSync;
  }
  final protocol = data['protocol'];
  if (protocol is! int) throw _notSync;
  if (protocol > syncProtocolVersion) {
    throw const FormatException(
      'This sync needs a newer version of Chapterly.',
    );
  }
  final books = data['books'];
  final tombstones = data['tombstones'];
  if (books is! List || tombstones is! Map) throw _notSync;
  final features = data['features'];
  try {
    return SyncPayload(
      books: [
        for (final item in books) Book.fromJson(item as Map<String, dynamic>),
      ],
      tombstones: {
        for (final entry in tombstones.entries)
          entry.key as String: DateTime.parse(entry.value as String),
      },
      features: {
        if (features is List)
          for (final feature in features) feature.toString(),
      },
      wishes: wishesFromJson(data['wishes']),
    );
  } on TypeError {
    throw const FormatException('This sync message is damaged.');
  }
}

/// [payload] with book changes and deletions dated more than a day ahead
/// dated now instead. A device with its clock far ahead would otherwise win
/// every merge until that date comes.
SyncPayload clampFutureDates(SyncPayload payload, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final limit = at.add(const Duration(days: 1));
  return SyncPayload(
    books: [
      for (final book in payload.books)
        if (book.updatedAt.isAfter(limit))
          book.copyWith(updatedAt: at)
        else
          book,
    ],
    tombstones: {
      for (final entry in payload.tombstones.entries)
        entry.key: entry.value.isAfter(limit) ? at : entry.value,
    },
    features: payload.features,
    wishes: payload.wishes,
  );
}
