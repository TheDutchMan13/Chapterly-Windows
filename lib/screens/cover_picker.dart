import 'package:flutter/material.dart';

import '../data/cover_options.dart';
import '../data/open_library_client.dart';
import '../widgets/book_cover.dart';

// The same file is in the Android app; keep the two copies alike.

/// Shows the covers Open Library has for a book, from every printing it
/// lists, and pops with the address of the one you tap.
class CoverPicker extends StatefulWidget {
  const CoverPicker({
    super.key,
    required this.client,
    required this.title,
    required this.author,
    this.isbn,
  });

  final OpenLibraryClient client;
  final String title;
  final String author;
  final String? isbn;

  @override
  State<CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<CoverPicker> {
  late final Future<List<CoverOption>> _options = findCoverOptions(
    widget.client,
    title: widget.title,
    author: widget.author,
    isbn: widget.isbn,
  );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Find a cover'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: FutureBuilder<List<CoverOption>>(
          future: _options,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Could not reach Open Library. '
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final options = snapshot.data ?? const <CoverOption>[];
            if (options.isEmpty) {
              return const Center(
                child: Text(
                  'Open Library has no cover for this book. Check the title '
                  'and author, or choose a picture of your own.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                childAspectRatio: 0.58,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pop(option.url),
                  child: Column(
                    children: [
                      BookCover(coverUrl: option.url, width: 96, height: 144),
                      const SizedBox(height: 4),
                      Text(
                        option.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
