import 'dart:io';
import 'dart:typed_data';

import '../audio/audio_tags.dart';
import '../audio/listening.dart';
import '../ebook/ebook_library.dart';
import '../ebook/ebook_reading.dart';
import '../ebook/epub_info.dart';
import '../models/book.dart';
import '../server/book_server.dart';
import 'book_source.dart';
import 'cover_image.dart';
import 'isbn_update.dart';

// The same file is in the Android app; keep the two copies alike.

/// What a book's own file (or your book server) can fill in that the book
/// does not have yet.
class FileDetailsFix {
  const FileDetailsFix({
    required this.book,
    required this.source,
    this.series,
    this.seriesNumber,
    this.isbn,
    this.coverUrl,
  });

  final Book book;

  /// Where it was read: "the EPUB file", "the audio file", "your book
  /// server".
  final String source;
  final String? series;
  final int? seriesNumber;
  final String? isbn;

  /// A data: cover made from the picture in the file.
  final String? coverUrl;

  bool get isEmpty => series == null && isbn == null && coverUrl == null;

  /// What it fills in, in a few words.
  String get summary => [
        if (series != null)
          seriesNumber == null ? 'Series $series' : 'Series $series #$seriesNumber',
        if (isbn != null) 'ISBN $isbn',
        if (coverUrl != null) 'cover',
      ].join(' · ');
}

/// The series number in a tag such as "3", "Book 3" or "3.0". Null when
/// there is no whole number.
int? seriesPartNumber(String text) {
  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
  final value = match == null ? null : double.tryParse(match[0]!);
  if (value == null || value <= 0 || value != value.roundToDouble()) {
    return null;
  }
  return value.round();
}

/// Reads [book]'s linked ebook or audiobook file, and asks your book server
/// when the book is linked to one, for a series, ISBN and cover the book does
/// not have. Null when there is nothing to fill in. Never throws.
Future<FileDetailsFix?> fileDetailsFor(Book book) async {
  final needSeries = (book.series ?? '').trim().isEmpty;
  final needIsbn = (book.isbn ?? '').trim().isEmpty;
  final needCover = (book.coverUrl ?? '').trim().isEmpty;
  if (!needSeries && !needIsbn && !needCover) return null;
  String? series;
  int? number;
  String? isbn;
  Uint8List? cover;
  final sources = <String>[];

  // The EPUB on this device.
  final ebook = EbookReading.library?.linkFor(book.id);
  if (ebook != null && ebook.format == EbookFormat.epub) {
    try {
      final file = File(ebook.path);
      if (await file.exists() && await file.length() < 300 * 1024 * 1024) {
        final details = epubDetails(await file.readAsBytes());
        if (details != null && !details.isEmpty) {
          series = details.series;
          number = details.seriesNumber;
          isbn = details.isbn;
          cover = details.cover;
          sources.add('the EPUB file');
        }
      }
    } catch (_) {
      // Unreadable: try the others.
    }
  }

  // The audiobook on this device.
  final tracks = Listening.controller?.library.linkFor(book.id)?.tracks;
  final files = Listening.files;
  if (tracks != null && tracks.isNotEmpty && files != null) {
    try {
      final source = files.open(tracks.first.location);
      try {
        final tags = await readAudioTags(source);
        var used = false;
        if (series == null && tags.series.isNotEmpty) {
          series = tags.series;
          number = seriesPartNumber(tags.seriesPart);
          used = true;
        }
        if (cover == null && tags.cover != null) {
          cover = tags.cover;
          used = true;
        }
        if (used) sources.add('the audio file');
      } finally {
        await source.close();
      }
    } catch (_) {
      // Unreadable: try the server.
    }
  }

  // Your book server, which read the file when it found it.
  final serverId = serverIdFor(book.id);
  final client = BookServer.sync?.client;
  if (serverId != null &&
      client != null &&
      ((needSeries && series == null) || (needCover && cover == null))) {
    try {
      final found = await client.book(serverId);
      var used = false;
      if (series == null && (found.series ?? '').trim().isNotEmpty) {
        series = found.series!.trim();
        final index = found.seriesIndex;
        number = index != null && index > 0 && index == index.roundToDouble()
            ? index.round()
            : null;
        used = true;
      }
      if (cover == null && found.hasCover) {
        cover = await client.bookCover(serverId);
        if (cover != null) used = true;
      }
      if (used) sources.add('your book server');
    } catch (_) {
      // The server is away.
    }
  }

  final fix = FileDetailsFix(
    book: book,
    source: sources.join(' and '),
    series: needSeries ? series : null,
    seriesNumber: needSeries && series != null ? number : null,
    isbn: needIsbn ? isbn13Of(isbn) : null,
    coverUrl: needCover && cover != null ? await makeDataCover(cover) : null,
  );
  return fix.isEmpty ? null : fix;
}
