import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/book.dart';
import 'book_store.dart';

/// Saves books in a SQLite database file on this PC.
class SqliteBookStore implements BookStore {
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
      audio_bookmarks TEXT
    )
  ''';

  static const _createTombstonesTable = '''
    CREATE TABLE tombstones (
      id TEXT PRIMARY KEY,
      deleted_at INTEGER NOT NULL
    )
  ''';

  /// Opens (or creates) the database file at [path].
  static Future<SqliteBookStore> open(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
      version: 11,
      onCreate: (db, version) async {
        await db.execute(_createBooksTable);
        await db.execute(_createTombstonesTable);
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
      },
      ),
    );
    return SqliteBookStore._(db);
  }

  @override
  Future<List<Book>> loadAll() async {
    final rows = await _db.query('books', orderBy: 'added_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  @override
  Future<void> save(Book book) async {
    await _db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveAll(List<Book> books) async {
    final batch = _db.batch();
    for (final book in books) {
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
    await _db.transaction((txn) async {
      await txn.delete('books');
      final batch = txn.batch();
      for (final book in books) {
        batch.insert('books', book.toMap());
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
}
