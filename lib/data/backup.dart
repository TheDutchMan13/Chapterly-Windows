import 'dart:convert';

import '../models/book.dart';

const _notABackup = FormatException('This file is not a Chapterly backup.');

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The whole library (trash included) as readable JSON. Version 2 added
/// format, favorites, notes, trash, the reading log and earlier readings.
/// Version 1 files still restore fine.
String encodeBackup(List<Book> books, {DateTime? now}) {
  final data = {
    'app': 'chapterly',
    'version': 2,
    'exportedAt': (now ?? DateTime.now()).toIso8601String(),
    'books': [for (final book in books) book.toJson()],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Reads a backup made by [encodeBackup]. Throws [FormatException] with a
/// message for the user if the text is not a Chapterly backup.
List<Book> decodeBackup(String text) {
  final data = _tryJson(text);
  if (data is! Map<String, dynamic> || data['app'] != 'chapterly') {
    throw _notABackup;
  }
  final books = data['books'];
  if (books is! List) throw _notABackup;
  try {
    return [
      for (final item in books) Book.fromJson(item as Map<String, dynamic>),
    ];
  } on TypeError {
    throw const FormatException('This backup file is damaged.');
  }
}
