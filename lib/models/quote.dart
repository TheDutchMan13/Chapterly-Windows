/// A passage saved from a book, with the page it was on (if known).
class Quote {
  const Quote({required this.text, required this.addedAt, this.page, this.note});

  final String text;
  final int? page;
  final DateTime addedAt;

  /// Your words about it: the note on the highlight it came from. Kept with
  /// the book, so it syncs.
  final String? note;

  Quote withNote(String? note) => Quote(
        text: text,
        addedAt: addedAt,
        page: page,
        note: note == null || note.trim().isEmpty ? null : note.trim(),
      );

  Map<String, Object?> toJson() => {
        'text': text,
        'page': page,
        'addedAt': addedAt.toIso8601String(),
        if (note != null) 'note': note,
      };

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        text: json['text'] as String,
        page: json['page'] as int?,
        addedAt: DateTime.tryParse((json['addedAt'] as String?) ?? '') ??
            DateTime.now(),
        note: json['note'] is String && (json['note'] as String).trim().isNotEmpty
            ? json['note'] as String
            : null,
      );
}

List<Quote> quotesFromJson(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map<String, dynamic>) Quote.fromJson(item),
      ]
    : const [];
