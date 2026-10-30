/// What changed in each version, newest first. Add a new entry for each release.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;
  final String date;
  final List<String> changes;
}

const changelog = [
  ChangelogEntry(
    version: '1.0.0',
    date: '2026-10-30',
    changes: [
      'First Windows version of Chapterly, with the same features as the '
          'phone app 1.9.0 (except the barcode scanner)',
      'Sync with your phone over your home Wi-Fi: Settings > Sync with your '
          'phone, then the sync button at the top of the library',
      'Look up a book by typing its ISBN',
      'Backups, CSV and share cards are saved with the Windows Save dialog',
      'Automatic backups go to Documents\\Chapterly',
    ],
  ),
];
