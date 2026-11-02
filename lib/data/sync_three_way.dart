import 'dart:convert';
import 'dart:io';

import '../models/book.dart';

// Windows app only. The phone keeps the newest copy of each book; before a
// sync the PC merges books changed on both sides field by field, against
// the copy from the last sync, and sends the result as the newest copy. So
// a rating changed on the PC and tags changed on the phone are both kept.
// The phone app and the sync messages stay the same.

/// Every book as it was after the last sync, kept in a small file.
class SyncBase {
  SyncBase({this.file});

  final File? file;
  Map<String, Map<String, Object?>> _books = {};

  Map<String, Map<String, Object?>> get books => _books;

  bool get isEmpty => _books.isEmpty;

  static Future<SyncBase> load(File file) async {
    final base = SyncBase(file: file);
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          for (final entry in data.entries) {
            if (entry.value is Map) {
              base._books[entry.key.toString()] =
                  Map<String, Object?>.from(entry.value as Map);
            }
          }
        }
      }
    } catch (_) {
      // Unreadable: the next sync works as before and saves a new one.
    }
    return base;
  }

  Future<void> save(List<Book> books) async {
    _books = {
      for (final book in books)
        book.id: jsonDecode(jsonEncode(book.toJson())) as Map<String, Object?>,
    };
    final target = file;
    if (target == null) return;
    try {
      await target.parent.create(recursive: true);
      await target.writeAsString(jsonEncode(_books));
    } catch (_) {
      // Not saved: the next sync falls back to the newest copy winning.
    }
  }
}

String _canon(Object? value) => jsonEncode(value);

bool _same(Object? a, Object? b) => _canon(a) == _canon(b);

/// A list changed on both sides: items added on either side are kept, items
/// removed on either side are dropped. Items are compared whole.
List<Object?> mergeLists(List<Object?> base, List<Object?> local, List<Object?> remote) {
  final inBase = {for (final item in base) _canon(item)};
  final inLocal = {for (final item in local) _canon(item)};
  final inRemote = {for (final item in remote) _canon(item)};
  final result = <Object?>[];
  final added = <String>{};
  for (final item in local) {
    final key = _canon(item);
    // Removed on the other side.
    if (inBase.contains(key) && !inRemote.contains(key)) continue;
    added.add(key);
    result.add(item);
  }
  for (final item in remote) {
    final key = _canon(item);
    if (inLocal.contains(key) || inBase.contains(key)) continue;
    if (added.add(key)) result.add(item);
  }
  return result;
}

/// Lists whose items have an identity of their own, so an item changed on
/// one side is matched with its earlier self: the reading log by day,
/// quotes and audiobook bookmarks by when they were added, earlier
/// readings by their dates.
const _itemKeys = {
  'readingLog': ['date'],
  'quotes': ['addedAt'],
  'audioBookmarks': ['addedAt'],
  'previousReadings': ['startedAt', 'finishedAt'],
};

/// Numbers that are added up when an item changed on both sides: pages and
/// minutes added to the same day on the PC and on the phone both count.
const _additive = {
  'readingLog': {'pages', 'minutes'},
};

/// Items by identity; a second item with the same identity gets "#2".
Map<String, Object?> _byKey(String field, List<Object?> items) {
  final fields = _itemKeys[field]!;
  final seen = <String, int>{};
  final result = <String, Object?>{};
  for (final item in items) {
    final id = item is Map
        ? [for (final f in fields) '${item[f]}'].join('|')
        : _canon(item);
    final n = (seen[id] ?? 0) + 1;
    seen[id] = n;
    result[n == 1 ? id : '$id#$n'] = item;
  }
  return result;
}

num _number(Object? map, String field) =>
    map is Map && map[field] is num ? map[field] as num : 0;

/// A list of items with an identity (see [_itemKeys]) changed on both
/// sides: each item is merged with its earlier self. Removed on one side
/// and unchanged on the other: gone. Changed on both: the numbers in
/// [_additive] add up, anything else takes the newer copy's item.
List<Object?> mergeKeyedLists(
  String field,
  List<Object?> base,
  List<Object?> local,
  List<Object?> remote, {
  required bool preferLocal,
}) {
  final b = _byKey(field, base);
  final l = _byKey(field, local);
  final r = _byKey(field, remote);
  final result = <Object?>[];
  for (final key in {...l.keys, ...r.keys}) {
    final before = b[key];
    final mine = l[key];
    final theirs = r[key];
    if (mine == null || theirs == null) {
      final present = mine ?? theirs;
      // Removed on one side and unchanged on the other: removed.
      if (b.containsKey(key) && _same(present, before)) continue;
      result.add(present);
      continue;
    }
    if (_same(mine, theirs) || _same(theirs, before)) {
      result.add(mine);
    } else if (_same(mine, before)) {
      result.add(theirs);
    } else {
      final sums = _additive[field];
      if (sums != null && mine is Map && theirs is Map) {
        final merged = Map<String, Object?>.from(preferLocal ? mine : theirs);
        for (final f in sums) {
          merged[f] = _number(mine, f) + _number(theirs, f) - _number(before, f);
        }
        result.add(merged);
      } else {
        result.add(preferLocal ? mine : theirs);
      }
    }
  }
  if (field == 'readingLog') {
    result.sort((x, y) => '${(x as Map?)?['date']}'.compareTo('${(y as Map?)?['date']}'));
  }
  return result;
}

/// Maps whose keys are merged one by one (stars per aspect); other maps,
/// such as the audiobook place, are taken whole from one side.
const _keyByKey = {'aspectRatings'};

Object? _mergeValue(
  String key,
  Object? base,
  Object? local,
  Object? remote, {
  required bool preferLocal,
}) {
  if (_same(local, remote)) return local;
  if (_same(local, base)) return remote;
  if (_same(remote, base)) return local;
  // Changed on both sides.
  if ((local is List || local == null) &&
      (remote is List || remote == null) &&
      (base is List || base == null) &&
      (local is List || remote is List)) {
    if (_itemKeys.containsKey(key)) {
      return mergeKeyedLists(
        key,
        (base as List?) ?? const [],
        (local as List?) ?? const [],
        (remote as List?) ?? const [],
        preferLocal: preferLocal,
      );
    }
    return mergeLists(
      (base as List?) ?? const [],
      (local as List?) ?? const [],
      (remote as List?) ?? const [],
    );
  }
  if (_keyByKey.contains(key) && local is Map && remote is Map) {
    final b = base is Map ? base : const {};
    return {
      for (final k in {...local.keys, ...remote.keys})
        k: ?_mergeValue('$key.$k', b[k], local[k], remote[k],
            preferLocal: preferLocal),
    };
  }
  return preferLocal ? local : remote;
}

/// [local] and [remote] merged field by field against [base] (the copy
/// from the last sync). A field changed on one side takes that side's value;
/// changed on both, lists are combined and anything else takes the newer
/// copy's value.
Map<String, Object?> mergeBookJson(
  Map<String, Object?> base,
  Map<String, Object?> local,
  Map<String, Object?> remote, {
  required bool preferLocal,
}) {
  final keys = {...local.keys, ...remote.keys}..remove('updatedAt');
  return {
    for (final key in keys)
      key: _mergeValue(key, base[key], local[key], remote[key],
          preferLocal: preferLocal),
  };
}

Map<String, Object?> _json(Book book) =>
    jsonDecode(jsonEncode(book.toJson())) as Map<String, Object?>;

/// Books that the newest-copy rule would get wrong, merged properly and
/// stamped [now] so they become the newest copy on both sides: books
/// changed on both the PC ([local]) and the phone ([remote]) since [base],
/// and books changed on one side whose copy is not the newer one (a clock
/// that is off). Books without a [base] copy are left to the usual rule.
/// The stamp is [now], or a second after both copies when a clock is ahead,
/// so the merged book is always the newest.
///
/// [phoneKeepsBookmarks] is false for a phone app older than 1.15.0, which
/// drops audiobook bookmarks: they are then left out of the comparison and
/// each book keeps this PC's bookmarks.
List<Book> resolveConflicts({
  required Map<String, Map<String, Object?>> base,
  required List<Book> local,
  required List<Book> remote,
  required DateTime now,
  bool phoneKeepsBookmarks = true,
}) {
  final remoteById = {for (final book in remote) book.id: book};
  final resolved = <Book>[];
  for (final mine in local) {
    final theirs = remoteById[mine.id];
    final before = base[mine.id];
    if (theirs == null || before == null) continue;
    final l = _json(mine)..remove('updatedAt');
    final r = _json(theirs)..remove('updatedAt');
    final b = Map.of(before)..remove('updatedAt');
    if (!phoneKeepsBookmarks) {
      for (final copy in [l, r, b]) {
        copy.remove('audioBookmarks');
      }
    }
    if (_same(l, r)) continue;
    final localNewer = !theirs.updatedAt.isAfter(mine.updatedAt);
    final merged = mergeBookJson(b, l, r, preferLocal: localNewer);
    // A field one copy leaves out when empty (such as audioBookmarks)
    // merged to nothing is left out too, so the copies compare equal.
    merged.removeWhere(
      (key, value) =>
          value == null && !(l.containsKey(key) && r.containsKey(key)),
    );
    // What the newest-copy rule would give anyway: nothing to do.
    if (_same(merged, localNewer ? l : r)) continue;
    if (!phoneKeepsBookmarks && mine.audioBookmarks.isNotEmpty) {
      merged['audioBookmarks'] = [
        for (final mark in mine.audioBookmarks) mark.toJson(),
      ];
    }
    var stamp = now;
    for (final other in [mine.updatedAt, theirs.updatedAt]) {
      if (!other.isBefore(stamp)) stamp = other.add(const Duration(seconds: 1));
    }
    merged['updatedAt'] = stamp.toIso8601String();
    resolved.add(Book.fromJson(merged));
  }
  return resolved;
}

/// [merged] books with this PC's audiobook bookmarks put back, for a sync
/// with a phone app older than 1.15.0, which drops them.
List<Book> keepPcBookmarks(List<Book> merged, List<Book> pc) {
  final pcById = {for (final book in pc) book.id: book};
  return [
    for (final book in merged)
      switch (pcById[book.id]) {
        final mine? when mine.audioBookmarks.isNotEmpty =>
          book.copyWith(audioBookmarks: mine.audioBookmarks),
        _ => book,
      },
  ];
}
