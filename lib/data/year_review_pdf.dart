import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/book.dart';
import 'date_format.dart';
import 'year_review.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// One finished reading in the year, for the list in the PDF.
class FinishedRead {
  const FinishedRead({
    required this.title,
    required this.author,
    required this.finishedAt,
    this.rating,
    this.pages,
  });

  final String title;
  final String author;
  final DateTime finishedAt;
  final int? rating;
  final int? pages;
}

/// Every book finished in [year] (a book read twice shows twice), in the
/// order they were finished. Books in the trash are left out.
List<FinishedRead> finishedIn(List<Book> books, int year) {
  final reads = <FinishedRead>[];
  for (final book in books) {
    if (book.deletedAt != null) continue;
    for (final reading in book.finishedReadings) {
      final at = reading.finishedAt;
      if (at == null || at.year != year) continue;
      reads.add(FinishedRead(
        title: book.title,
        author: book.author,
        finishedAt: at,
        rating: reading.rating,
        pages: book.pages,
      ));
    }
  }
  reads.sort((a, b) => a.finishedAt.compareTo(b.finishedAt));
  return reads;
}

/// Windows' own Segoe UI, so titles in any language print correctly. Null
/// when the font files are not there (the PDF then uses Helvetica).
Future<({pw.Font regular, pw.Font bold})?> loadWindowsFonts() async {
  try {
    final folder = '${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Fonts';
    final regular = await File('$folder\\segoeui.ttf').readAsBytes();
    final bold = await File('$folder\\segoeuib.ttf').readAsBytes();
    return (
      regular: pw.Font.ttf(ByteData.sublistView(regular)),
      bold: pw.Font.ttf(ByteData.sublistView(bold)),
    );
  } catch (_) {
    return null;
  }
}

/// A printable year in review: the numbers from the year-in-review card and
/// a list of every book finished that year. Letter size.
Future<Uint8List> buildYearReviewPdf(
  List<Book> books,
  int year, {
  ({pw.Font regular, pw.Font bold})? fonts,
}) async {
  final review = computeYearReview(books, year);
  final stats = review.stats;
  final reads = finishedIn(books, year);
  final theme = fonts == null
      ? pw.ThemeData.base()
      : pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
  final document = pw.Document(
    theme: theme,
    title: 'My $year in books',
    creator: 'Chapterly',
  );

  pw.Widget number(String value, String label) => pw.Expanded(
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      );

  final author = stats.topAuthors.isEmpty ? null : stats.topAuthors.first;
  final tag = stats.topTags.isEmpty ? null : stats.topTags.first;
  final month = review.busiestMonth;
  final average = stats.averageRating;
  final facts = <String>[
    if (author != null) 'Most read author: ${author.key} (${author.value})',
    if (tag != null) 'Favorite tag: ${tag.key} (${tag.value})',
    if (month != null)
      'Busiest month: ${_monthNames[month - 1]} (${stats.byMonth[month - 1]})',
    if (average != null) 'Average rating: ${average.toStringAsFixed(1)} of 5',
    if (review.longestStreak > 1)
      'Longest streak: ${review.longestStreak} days',
  ];

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(48),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Chapterly', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
      build: (context) => [
        pw.Text(
          'My $year in books',
          style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 20),
        pw.Row(
          children: [
            number(
              '${stats.finishedCount}',
              stats.finishedCount == 1 ? 'book' : 'books',
            ),
            number('${stats.pagesRead}', 'pages'),
            if (stats.loggedMinutes > 0)
              number(formatMinutes(stats.loggedMinutes), 'reading time')
            else
              number('${review.longestStreak}', 'day streak'),
          ],
        ),
        pw.SizedBox(height: 20),
        if (review.topRated.isNotEmpty) ...[
          pw.Text(
            'Top rated',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          for (final book in review.topRated)
            pw.Bullet(
              text: book.author.isEmpty
                  ? book.title
                  : '${book.title} by ${book.author}',
            ),
          pw.SizedBox(height: 12),
        ],
        for (final fact in facts)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(fact),
          ),
        pw.SizedBox(height: 20),
        pw.Text(
          reads.isEmpty
              ? 'No finished books in $year yet.'
              : 'Every book finished in $year',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        if (reads.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Finished', 'Title', 'Author', 'Rating', 'Pages'],
            data: [
              for (final read in reads)
                [
                  formatDate(read.finishedAt),
                  read.title,
                  read.author,
                  read.rating == null ? '' : '${read.rating}/5',
                  read.pages?.toString() ?? '',
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            columnWidths: {
              0: const pw.FixedColumnWidth(70),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FixedColumnWidth(45),
              4: const pw.FixedColumnWidth(45),
            },
            border: null,
            headerDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 1)),
            ),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ],
    ),
  );
  return document.save();
}
