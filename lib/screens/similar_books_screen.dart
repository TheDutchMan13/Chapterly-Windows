import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'book_detail_screen.dart';

/// A plain list of the books that match [test], for example every book by one
/// author or with one tag.
class SimilarBooksScreen extends StatelessWidget {
  const SimilarBooksScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
    required this.title,
    required this.test,
    this.compare,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;
  final String title;
  final bool Function(Book book) test;

  /// Orders the list. Without it, the newest books come first.
  final int Function(Book a, Book b)? compare;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final books = [
          for (final book in repository.books)
            if (test(book)) book,
        ];
        final order = compare;
        if (order != null) books.sort(order);
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: books.isEmpty
              ? const Center(child: Text('No books found.'))
              : ListView.builder(
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final book = books[index];
                    return ListTile(
                      leading: BookCover(
                        coverUrl: book.coverUrl,
                      ),
                      title: Text(book.title),
                      subtitle: Text(
                        [
                          if (book.author.isNotEmpty) book.author,
                          book.shelf.label,
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BookDetailScreen(
                            repository: repository,
                            settings: settings,
                            fileIo: fileIo,
                            bookId: book.id,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
