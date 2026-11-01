import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ebook/ebook_library.dart';
import '../models/quote.dart';

// Windows app only.

/// One audiobook bookmark, ready to print: where it is and its note.
class ExportedMark {
  const ExportedMark({required this.place, this.note = ''});

  /// Such as "1:02:15 · Chapter 4".
  final String place;
  final String note;
}

/// Everything you wrote about one book: your notes, quotes, highlights from
/// the reader and audiobook bookmarks.
class BookNotesExport {
  const BookNotesExport({
    required this.title,
    required this.author,
    this.notes,
    this.quotes = const [],
    this.highlights = const [],
    this.marks = const [],
  });

  final String title;
  final String author;
  final String? notes;
  final List<Quote> quotes;
  final List<EbookHighlight> highlights;
  final List<ExportedMark> marks;

  bool get isEmpty =>
      (notes ?? '').trim().isEmpty &&
      quotes.isEmpty &&
      highlights.isEmpty &&
      marks.isEmpty;

  /// A file name such as "Dune - notes".
  String get fileStem {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
    return '${clean.isEmpty ? 'Book' : clean} - notes';
  }
}

/// The notes as Markdown, for Obsidian, a notes app or a text editor.
String notesMarkdown(BookNotesExport e) {
  final out = StringBuffer()..writeln('# ${e.title}');
  if (e.author.trim().isNotEmpty) out.writeln('*${e.author.trim()}*');
  final notes = e.notes?.trim() ?? '';
  if (notes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Notes')
      ..writeln()
      ..writeln(notes);
  }
  if (e.quotes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Quotes');
    for (final quote in e.quotes) {
      out
        ..writeln()
        ..writeln(_blockquote(quote.text));
      if (quote.page != null) out.writeln('— page ${quote.page}');
    }
  }
  if (e.highlights.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Highlights');
    for (final highlight in e.highlights) {
      out
        ..writeln()
        ..writeln(_blockquote(highlight.text));
      final note = highlight.note?.trim() ?? '';
      if (note.isNotEmpty) {
        out
          ..writeln()
          ..writeln(note);
      }
    }
  }
  if (e.marks.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Audiobook bookmarks')
      ..writeln();
    for (final mark in e.marks) {
      final note = mark.note.trim();
      out.writeln('- **${mark.place}**${note.isEmpty ? '' : ': $note'}');
    }
  }
  return out.toString();
}

String _blockquote(String text) => [
      for (final line in text.trim().split('\n')) '> ${line.trimRight()}',
    ].join('\n');

/// The notes as a printable PDF. [fonts] are Windows' own fonts so any
/// language prints; without them the PDF's built-in font is used.
Future<Uint8List> notesPdf(
  BookNotesExport e, {
  ({pw.Font regular, pw.Font bold})? fonts,
}) {
  final document = pw.Document(
    theme: fonts == null
        ? null
        : pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    title: '${e.title} notes',
    creator: 'Chapterly',
  );
  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
      );
  pw.Widget passage(String text, {String? below}) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(left: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey500, width: 2),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              text.trim(),
              style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
            ),
            if (below != null && below.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(
                  below.trim(),
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
          ],
        ),
      );
  final notes = e.notes?.trim() ?? '';
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
          e.title,
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        if (e.author.trim().isNotEmpty) pw.Text(e.author.trim()),
        if (notes.isNotEmpty) ...[heading('Notes'), pw.Text(notes)],
        if (e.quotes.isNotEmpty) ...[
          heading('Quotes'),
          for (final quote in e.quotes)
            passage(
              quote.text,
              below: quote.page == null ? null : 'Page ${quote.page}',
            ),
        ],
        if (e.highlights.isNotEmpty) ...[
          heading('Highlights'),
          for (final highlight in e.highlights)
            passage(highlight.text, below: highlight.note),
        ],
        if (e.marks.isNotEmpty) ...[
          heading('Audiobook bookmarks'),
          for (final mark in e.marks)
            pw.Bullet(
              text: mark.note.trim().isEmpty
                  ? mark.place
                  : '${mark.place}: ${mark.note.trim()}',
            ),
        ],
      ],
    ),
  );
  return document.save();
}
