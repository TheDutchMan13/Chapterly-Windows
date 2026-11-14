import '../ebook/ebook_library.dart';

// Like pdf_hiding.dart in the Android app (which has no linked files); keep
// the two alike.

/// Ids of books whose only file is a PDF: the ones "Hide PDF books" leaves
/// out. A book with an EPUB, an audiobook or any other linked file stays.
/// [linked] is the files linked where they already are on this PC.
Set<String> pdfOnlyBookIds({
  required Map<String, EbookLink> ebooks,
  Map<String, String> linked = const {},
  required bool Function(String bookId) hasAudio,
}) {
  bool isPdf(String path) => path.toLowerCase().endsWith('.pdf');
  final ids = <String>{
    for (final entry in ebooks.entries)
      if (entry.value.format == EbookFormat.pdf) entry.key,
    for (final entry in linked.entries)
      if (isPdf(entry.value)) entry.key,
  };
  return {
    for (final id in ids)
      if (!hasAudio(id) &&
          ebooks[id]?.format != EbookFormat.epub &&
          (linked[id] == null || isPdf(linked[id]!)))
        id,
  };
}
