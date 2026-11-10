import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/book.dart';
import 'book_store.dart';
import 'cover_store.dart';
import 'sync_covers.dart';

/// Saves books in a SQLite database file on this PC.
class SqliteBookStore implements BookStore, BulkCoverStore {
  SqliteBookStore._(this._db);

  final Database _db;

  static const _createBooksTable = '''
    CREATE TABLE books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      shelf TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      tags TEXT NOT NULL,
      isbn TEXT,
      cover_url TEXT,
      first_publish_year INTEGER,
      pages INTEGER,
      rating INTEGER,
      started_at INTEGER,
      finished_at INTEGER,
      format TEXT,
      favorite INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      deleted_at INTEGER,
      cover_path TEXT,
      series TEXT,
      series_number INTEGER,
      reading_log TEXT,
      previous_readings TEXT,
      updated_at INTEGER,
      collections TEXT,
      quotes TEXT,
      current_page INTEGER,
      aspect_ratings TEXT,
      priority TEXT,
      buy_at TEXT,
      queue_position INTEGER,
      extras TEXT,
      audio TEXT,
      audio_bookmarks TEXT,
      origin TEXT
    )
  ''';

  /// Cover pictures, kept apart from the books (see cover_store.dart).
  static const _createCoversTable = '''
    CREATE TABLE IF NOT EXISTS covers (
      hash TEXT PRIMARY KEY,
      data TEXT NOT NULL
    )
  ''';

  static const _createTombstonesTable = '''
    CREATE TABLE tombstones (
      id TEXT PRIMARY KEY,
      deleted_at INTEGER NOT NULL
    )
  ''';

  /// Opens (or creates) the database file at [path].
  /// Closes the database. Used for a profile opened only for a sync.
  Future<void> close() => _db.close();

  static Future<SqliteBookStore> open(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
      version: 13,
      onCreate: (db, version) async {
        await db.execute(_createBooksTable);
        await db.execute(_createTombstonesTable);
        await db.execute(_createCoversTable);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Version 2 added pages, rating and reading dates.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE books ADD COLUMN pages INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN rating INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN started_at INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN finished_at INTEGER');
        }
        // Version 3 added format, favorites, notes, trash, custom covers,
        // the reading log and earlier readings.
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE books ADD COLUMN format TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('ALTER TABLE books ADD COLUMN notes TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN deleted_at INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN cover_path TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN reading_log TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN previous_readings TEXT',
          );
        }
        // Version 4 added series.
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE books ADD COLUMN series TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN series_number INTEGER',
          );
        }
        // Version 5 added the last-changed time (for sync) and the list of
        // permanently deleted books.
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE books ADD COLUMN updated_at INTEGER');
          await db.execute(
            'UPDATE books SET updated_at = added_at WHERE updated_at IS NULL',
          );
          await db.execute(_createTombstonesTable);
        }
        // Version 6 added your own shelves and saved quotes.
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE books ADD COLUMN collections TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN quotes TEXT');
        }
        // Version 7 added the current page and ratings for parts of a book.
        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE books ADD COLUMN current_page INTEGER',
          );
          await db.execute('ALTER TABLE books ADD COLUMN aspect_ratings TEXT');
        }
        // Version 8 added the wishlist details: priority, where to buy and
        // the place in the Next up order.
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE books ADD COLUMN priority TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN buy_at TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN queue_position INTEGER',
          );
        }
        // Version 9 (Windows only) keeps book fields from a newer phone app.
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE books ADD COLUMN extras TEXT');
        }
        // Version 10 added where you are in the audiobook.
        if (oldVersion < 10) {
          await db.execute('ALTER TABLE books ADD COLUMN audio TEXT');
        }
        // Version 11 keeps audiobook bookmarks with the book, so they sync.
        if (oldVersion < 11) {
          await db.execute(
            'ALTER TABLE books ADD COLUMN audio_bookmarks TEXT',
          );
        }
        // Version 12 keeps where the book came from and its details before
        // you corrected them.
        if (oldVersion < 12) {
          await db.execute('ALTER TABLE books ADD COLUMN origin TEXT');
        }
        if (oldVersion < 13) {
          // Cover pictures move out of the books into their own table, the
          // first time the library is read (see loadAll).
          await db.execute(_createCoversTable);
        }
      },
      ),
    );
    return SqliteBookStore._(db);
  }

  @override
  Future<List<Book>> loadAll() async {
    final rows = await _db.query('books', orderBy: 'added_at DESC');
    return _moveCoversOut(rows.map(Book.fromMap).toList());
  }

  @override
  Future<void> save(Book book) async {
    final kept = await keepCoverApart(book, this);
    await _db.insert(
      'books',
      kept.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveAll(List<Book> books) async {
    final batch = _db.batch();
    for (final book in await keepCoversApart(books, this)) {
      batch.insert(
        'books',
        book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> replaceAll(List<Book> books) async {
    final kept = await keepCoversApart(books, this);
    await _db.transaction((txn) async {
      await txn.delete('books');
      final batch = txn.batch();
      for (final book in kept) {
        // A second copy of a book replaces the first instead of failing the
        // whole restore.
        batch.insert(
          'books',
          book.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> remove(String id) async {
    await _db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Map<String, DateTime>> loadTombstones() async {
    final rows = await _db.query('tombstones');
    return {
      for (final row in rows)
        row['id'] as String: DateTime.fromMillisecondsSinceEpoch(
          row['deleted_at'] as int,
        ),
    };
  }

  @override
  Future<void> saveTombstones(Map<String, DateTime> tombstones) async {
    await _db.transaction((txn) async {
      await txn.delete('tombstones');
      final batch = txn.batch();
      for (final entry in tombstones.entries) {
        batch.insert('tombstones', {
          'id': entry.key,
          'deleted_at': entry.value.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  // ---- cover pictures, kept apart from the books

  /// Moves the pictures still inside [books] (a library saved before 1.45.0)
  /// into the covers table, and saves those books with a reference.
  Future<List<Book>> _moveCoversOut(List<Book> books) async {
    final old = [
      for (final book in books)
        if (isDataCoverUrl(book.coverUrl)) book,
    ];
    if (old.isEmpty) return books;
    final moved = {
      for (final book in await keepCoversApart(old, this)) book.id: book,
    };
    final batch = _db.batch();
    for (final book in moved.values) {
      batch.update(
        'books',
        {'cover_url': book.coverUrl},
        where: 'id = ?',
        whereArgs: [book.id],
      );
    }
    await batch.commit(noResult: true);
    return [for (final book in books) moved[book.id] ?? book];
  }

  /// The short names kept, read once and then kept up to date.
  Set<String>? _hashes;

  @override
  Future<Set<String>> coverHashes() async {
    final known = _hashes ??= {
      for (final row in await _db.rawQuery('SELECT hash FROM covers'))
        row['hash']! as String,
    };
    return {...known};
  }

  @override
  Future<String?> readCover(String hash) async {
    final rows = await _db.query(
      'covers',
      columns: ['data'],
      where: 'hash = ?',
      whereArgs: [hash],
    );
    return rows.isEmpty ? null : rows.first['data'] as String?;
  }

  @override
  Future<void> writeCover(String hash, String dataUrl) async {
    await _db.insert(
      'covers',
      {'hash': hash, 'data': dataUrl},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _hashes?.add(hash);
  }

  @override
  Future<void> writeCovers(Map<String, String> pictures) async {
    // One transaction for all of them: a write per picture would flush the
    // disk every time, which takes minutes for a big library.
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in pictures.entries) {
        batch.insert(
          'covers',
          {'hash': entry.key, 'data': entry.value},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
    _hashes?.addAll(pictures.keys);
  }

  /// Gives the disk back the space of removed data. A library whose
  /// pictures were moved out of the books, or many times replaced, kept all
  /// that space empty inside the file: half of a 195 MB library. The first
  /// time, the file is rewritten once (about a second for a big library on
  /// a PC) and set to give space back from then on; after that only the
  /// empty part is trimmed, which is quick. Never fails: a full disk just
  /// leaves the file as it was. Returns the bytes given back.
  Future<int> compact() async {
    Future<int> number(String pragma) async =>
        (await _db.rawQuery('PRAGMA $pragma')).first.values.first as int? ?? 0;
    try {
      final pageSize = await number('page_size');
      final before = await number('page_count');
      if (await number('auto_vacuum') != 2) {
        await _db.execute('PRAGMA auto_vacuum = INCREMENTAL');
        await _db.execute('VACUUM');
      } else {
        // Each run may stop part way; a few runs give back the rest.
        for (var run = 0; run < 20; run++) {
          final free = await number('freelist_count');
          if (free * pageSize <= 1 << 20) break;
          await _db.rawQuery('PRAGMA incremental_vacuum($free)');
        }
      }
      return (before - await number('page_count')) * pageSize;
    } on DatabaseException {
      return 0;
    }
  }

  @override
  Future<void> removeCoversExcept(Set<String> keep) async {
    final gone = [
      for (final hash in await coverHashes())
        if (!keep.contains(hash)) hash,
    ];
    for (var i = 0; i < gone.length; i += 200) {
      final part = gone.skip(i).take(200).toList();
      await _db.delete(
        'covers',
        where: 'hash IN (${List.filled(part.length, '?').join(', ')})',
        whereArgs: part,
      );
    }
    _hashes?.removeAll(gone);
  }
}
