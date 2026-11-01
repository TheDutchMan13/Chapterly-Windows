import 'dart:io';
import 'dart:typed_data';

import '../audio/audio_library.dart';
import '../audio/media_controls.dart';
import '../ebook/ebook_library.dart';
import '../ebook/epub_book.dart';
import '../models/audio_progress.dart';
import '../models/book.dart';

// Windows app only.

/// Where you are in a book's audiobook and in its book file, from 0 to 1.
class FormatPositions {
  const FormatPositions({required this.audio, required this.reader});

  final double audio;
  final double reader;

  /// How far apart, from 0 to 1.
  double get gap => (audio - reader).abs();

  /// Worth offering to line them up: more than 2% apart.
  bool get apart => gap > 0.02;

  bool get audioAhead => audio > reader;
}

/// Both places, or null unless the book has an audiobook with a known
/// length and a book file with a saved place on this PC.
FormatPositions? formatPositions(
  Book book, {
  AudioLink? audio,
  EbookLink? ebook,
}) {
  final progress = book.audio;
  final position = ebook?.position;
  if (progress == null || audio == null || position == null) return null;
  final length = audio.lengthMs ?? progress.lengthMs;
  if (length == null || length <= 0) return null;
  final fraction = (progress.positionMs / length).clamp(0.0, 1.0);
  return FormatPositions(audio: fraction, reader: position.progress);
}

/// The audiobook place for [fraction] of the way through the book.
AudioProgress audioProgressAt(AudioLink link, double fraction) {
  final length = link.lengthMs ?? 0;
  final place = placeInBook(link, (fraction.clamp(0.0, 1.0) * length).round());
  return link.progressAt(place.track, place.trackMs);
}

/// The book file's place for [fraction] of the way through: the page of a
/// PDF (when its page count is known), or the chapter and place in it of an
/// EPUB, counting chapters by their length as the reader does. [epubBytes]
/// is for tests; normally the file is read. Null when it cannot be worked
/// out.
Future<EbookPosition?> readerPositionAt(
  EbookLink link,
  double fraction, {
  Uint8List? epubBytes,
}) async {
  final value = fraction.clamp(0.0, 1.0);
  if (link.format == EbookFormat.pdf) {
    final pages = link.pageCount;
    if (pages == null || pages <= 0) return null;
    final page = 1 + (value * (pages - 1)).round();
    return EbookPosition(locator: '$page', progress: value);
  }
  try {
    final bytes = epubBytes ?? await File(link.path).readAsBytes();
    final book = EpubBook.open(bytes);
    final lengths = [
      for (var i = 0; i < book.chapters.length; i++) book.chapterText(i).length,
    ];
    if (lengths.isEmpty) return null;
    final spot = spotForProgress(lengths, value);
    return EbookPosition(
      locator: spot.locator,
      progress: bookProgress(lengths, spot),
    );
  } catch (_) {
    return null;
  }
}
