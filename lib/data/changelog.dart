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
    version: '1.4.0',
    date: '2026-10-30',
    changes: [
      'A side menu for Library, Statistics, Next up, Read next and Settings '
          '(Ctrl+1 to Ctrl+5)',
      'How syncing with your phone is going, at the bottom of the side '
          'menu: click it to sync',
      'The book page is split into Overview, Reading and Notes, with the '
          'cover, shelf and progress always at the top',
      'The table view shows the open book beside it in a wide window',
      'A fuller player: a big cover, larger buttons, the chapter and how '
          'much of the book is left, and the chapter list beside it in a wide '
          'window',
      'Choose the cover size for the grid view (View, then Cover size, or '
          'Ctrl+= and Ctrl+-)',
    ],
  ),
  ChangelogEntry(
    version: '1.3.0',
    date: '2026-10-30',
    changes: [
      'Audiobooks: add the audio for a book (one file, or a folder of files) '
          'and listen to it in Chapterly',
      'Chapters from .m4b files, or one chapter per file in a folder',
      'Skip 30 seconds, speed from 0.5x to 3x, and a sleep timer (or stop at '
          'the end of the chapter)',
      'Where you are in an audiobook syncs between the phone and the PC',
      'Time spent listening is added to the reading log and statistics',
      'Offers to move a book to Finished when you reach the end',
    ],
  ),
  ChangelogEntry(
    version: '1.2.0',
    date: '2026-10-30',
    changes: [
      'Table view: sortable columns, change a title, author, pages, shelf, '
          'rating or format right in the table, and Shift+click to select '
          'several books',
      'Add several books at once: paste a list of ISBNs or titles and pick '
          'the matches',
      'Sync preview: see what will change on the PC and on the phone before '
          'it happens',
      'Syncs every few minutes while Chapterly is open, and shows when it '
          'last synced',
      'Covers from your PC: drop a picture on a book, paste one with Ctrl+V, '
          'or choose a file',
      'Statistics use the whole width of a big window',
      'Save your year in review as a PDF to print, with every book you '
          'finished',
      'Reading timer: a small window that stays on top while you read',
    ],
  ),
  ChangelogEntry(
    version: '1.1.0',
    date: '2026-10-30',
    changes: [
      'Two panes in a wide window: the list on the left, the open book on '
          'the right',
      'Keyboard shortcuts: Ctrl+F search, Ctrl+N add, Ctrl+S sync, Ctrl+, '
          'Settings, Esc to close',
      'Right-click a book to move, favorite, add to a shelf or trash it',
      'Drop a backup, a CSV file or My Clippings.txt on the window to import',
      'Find my phone: looks for your phone on the home network',
      'Sync when Chapterly opens (quietly, only if the phone is there)',
      'Checks GitHub once a day for a newer version (can be switched off)',
      'Remembers the window size and place, and has a proper installer',
      'Chapterly logo as the app icon, and a minimum window size',
    ],
  ),
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
