enum BookFormat { paperback, hardcover, ebook, audiobook }

extension BookFormatLabel on BookFormat {
  String get label => switch (this) {
        BookFormat.paperback => 'Paperback',
        BookFormat.hardcover => 'Hardcover',
        BookFormat.ebook => 'E-book',
        BookFormat.audiobook => 'Audiobook',
      };
}

/// Understands our own labels and common names from other apps, such as
/// Goodreads' "Kindle Edition". Returns null if the text is not a format.
BookFormat? parseBookFormat(String? text) {
  final value = text?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return null;
  if (value.contains('audio')) return BookFormat.audiobook;
  if (value.contains('hardcover') || value.contains('hardback')) {
    return BookFormat.hardcover;
  }
  if (value.contains('ebook') ||
      value.contains('e-book') ||
      value.contains('kindle') ||
      value.contains('epub') ||
      value.contains('digital')) {
    return BookFormat.ebook;
  }
  if (value.contains('paperback') ||
      value.contains('softcover') ||
      value.contains('mass market')) {
    return BookFormat.paperback;
  }
  return null;
}
