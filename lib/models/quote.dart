/// A passage saved from a book, with the page it was on (if known).
class Quote {
  const Quote({required this.text, required this.addedAt, this.page});

  final String text;
  final int? page;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
        'text': text,
        'page': page,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        text: json['text'] as String,
        page: json['page'] as int?,
        addedAt: DateTime.tryParse((json['addedAt'] as String?) ?? '') ??
            DateTime.now(),
      );
}

List<Quote> quotesFromJson(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map<String, dynamic>) Quote.fromJson(item),
      ]
    : const [];
