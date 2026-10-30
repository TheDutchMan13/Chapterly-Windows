import 'app_settings.dart';
import 'book_repository.dart';

/// Every shelf name of your own: the ones saved in Settings (so empty shelves
/// stay) and any that books are on (for example after a sync or restore).
List<String> allCollectionNames(
  AppSettings settings,
  BookRepository repository,
) {
  final seen = <String>{};
  final names = <String>[];
  for (final name in [
    ...settings.collections,
    ...repository.collectionNamesInUse,
  ]) {
    if (seen.add(name.toLowerCase())) names.add(name);
  }
  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
}
