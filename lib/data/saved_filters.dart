import 'dart:convert';

import '../models/book_format.dart';

// Windows app only.

/// A set of Library filters saved under a name, such as "Unread fantasy".
/// Applying it sets the filter chips and search; the shelf tabs still choose
/// which shelf is shown.
class SavedFilter {
  const SavedFilter({
    required this.name,
    this.tags = const {},
    this.excludedTags = const {},
    this.matchAllTags = true,
    this.formats = const {},
    this.favoritesOnly = false,
    this.finishYear,
    this.query = '',
  });

  final String name;
  final Set<String> tags;
  final Set<String> excludedTags;
  final bool matchAllTags;
  final Set<BookFormat> formats;
  final bool favoritesOnly;
  final int? finishYear;
  final String query;

  /// A short line saying what it shows, such as "fantasy · E-book · favorites".
  String describe() {
    final parts = <String>[
      if (tags.isNotEmpty) tags.join(matchAllTags ? ' + ' : ' or '),
      for (final tag in excludedTags) 'not $tag',
      for (final format in formats) format.label,
      if (favoritesOnly) 'favorites',
      if (finishYear != null) 'finished $finishYear',
      if (query.trim().isNotEmpty) '"${query.trim()}"',
    ];
    return parts.isEmpty ? 'No filters' : parts.join(' · ');
  }

  SavedFilter copyWith({
    String? name,
    Set<String>? tags,
    Set<String>? excludedTags,
  }) =>
      SavedFilter(
        name: name ?? this.name,
        tags: tags ?? this.tags,
        excludedTags: excludedTags ?? this.excludedTags,
        matchAllTags: matchAllTags,
        formats: formats,
        favoritesOnly: favoritesOnly,
        finishYear: finishYear,
        query: query,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'tags': tags.toList(),
        'excludedTags': excludedTags.toList(),
        'matchAllTags': matchAllTags,
        'formats': [for (final f in formats) f.name],
        'favoritesOnly': favoritesOnly,
        'finishYear': finishYear,
        'query': query,
      };

  static SavedFilter? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    if (name is! String || name.trim().isEmpty) return null;
    Set<String> strings(Object? list) =>
        list is List ? {...list.whereType<String>()} : <String>{};
    final formatNames = strings(value['formats']);
    final year = value['finishYear'];
    final query = value['query'];
    return SavedFilter(
      name: name.trim(),
      tags: strings(value['tags']),
      excludedTags: strings(value['excludedTags']),
      matchAllTags: value['matchAllTags'] != false,
      formats: {
        for (final format in BookFormat.values)
          if (formatNames.contains(format.name)) format,
      },
      favoritesOnly: value['favoritesOnly'] == true,
      finishYear: year is int ? year : null,
      query: query is String ? query : '',
    );
  }
}

String encodeSavedFilters(List<SavedFilter> filters) =>
    jsonEncode([for (final filter in filters) filter.toJson()]);

List<SavedFilter> decodeSavedFilters(String? text) {
  if (text == null || text.isEmpty) return [];
  try {
    final list = jsonDecode(text);
    if (list is! List) return [];
    return [
      for (final item in list)
        ?SavedFilter.fromJson(item),
    ];
  } on FormatException {
    return [];
  }
}
