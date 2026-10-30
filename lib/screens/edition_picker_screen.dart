import 'package:flutter/material.dart';

import '../data/open_library_client.dart';
import '../widgets/book_cover.dart';

/// Lists the editions of a book from Open Library, so you can add the exact
/// printing you own (with its ISBN, page count and cover). Pops with the
/// book carrying the chosen edition's details.
class EditionPickerScreen extends StatefulWidget {
  const EditionPickerScreen({
    super.key,
    required this.client,
    required this.book,
  });

  final OpenLibraryClient client;
  final OpenLibraryBook book;

  @override
  State<EditionPickerScreen> createState() => _EditionPickerScreenState();
}

class _EditionPickerScreenState extends State<EditionPickerScreen> {
  late final Future<List<OpenLibraryEdition>> _editions =
      widget.client.editions(widget.book.workKey ?? '');
  bool _onlyWithCovers = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editions of ${widget.book.title}')),
      body: FutureBuilder<List<OpenLibraryEdition>>(
        future: _editions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not reach Open Library. '
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final all = snapshot.data ?? const <OpenLibraryEdition>[];
          final shown = [
            for (final edition in all)
              if (!_onlyWithCovers || edition.coverUrl != null) edition,
          ];
          return Column(
            children: [
              SwitchListTile(
                title: const Text('Only editions with covers'),
                value: _onlyWithCovers,
                onChanged: (value) => setState(() => _onlyWithCovers = value),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('No editions found.'))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final edition = shown[index];
                          final subtitle = edition.subtitle;
                          return ListTile(
                            leading: BookCover(coverUrl: edition.coverUrl),
                            title: Text(edition.title),
                            subtitle: subtitle.isEmpty ? null : Text(subtitle),
                            onTap: () => Navigator.of(context)
                                .pop(widget.book.withEdition(edition)),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
