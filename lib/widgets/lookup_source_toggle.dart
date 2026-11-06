import 'package:flutter/material.dart';

import '../data/google_books_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// Where a search for a book looks.
enum LookupSource {
  openLibrary('Open Library'),
  googleBooks('Google Books');

  const LookupSource(this.label);

  final String label;
}

/// Chooses between Open Library and Google Books.
class LookupSourceToggle extends StatelessWidget {
  const LookupSourceToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LookupSource value;
  final ValueChanged<LookupSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LookupSource>(
      showSelectedIcon: false,
      segments: [
        for (final source in LookupSource.values)
          ButtonSegment(value: source, label: Text(source.label)),
      ],
      selected: {value},
      onSelectionChanged: (selected) => onChanged(selected.first),
    );
  }
}

/// What to tell the user when a search failed.
String lookupFailureText(LookupSource source, Object? error) {
  if (source == LookupSource.googleBooks) {
    return error is GoogleQuotaReached
        ? 'Google has no more searches for today. Add a free Google Books '
            'key in Settings to search more, or use Open Library.'
        : 'Could not reach Google Books. Check your connection and try again.';
  }
  return 'Could not reach Open Library. Check your connection and try again.';
}
