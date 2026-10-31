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
    version: '1.8.0',
    date: '2026-10-31',
    changes: [
      'Choose a books folder and an audiobooks folder in Settings, and '
          'Chapterly links the EPUB, PDF and audiobook files in them to the '
          'matching books in your library',
      'Scan now, or let it scan a few seconds after Chapterly opens (you can '
          'switch that off)',
      'Only clear matches are linked, a file is never put over one that is '
          'already linked, and no book is added without asking',
      'Files it is not sure about wait in a list where you link, choose '
          'another book, add as a new book, or skip',
    ],
  ),
  ChangelogEntry(
    version: '1.7.0',
    date: '2026-10-31',
    changes: [
      'Add file, at the top of the side menu (Ctrl+O): open an EPUB, PDF or '
          'audiobook and Chapterly finds its book in your library from the '
          'title and author in the file or its name',
      'Pick another book if it guessed wrong, or add the file as a new book '
          'with one click',
      'Or drag an EPUB, PDF, audiobook file or audiobook folder onto the '
          'window',
    ],
  ),
  ChangelogEntry(
    version: '1.6.0',
    date: '2026-10-31',
    changes: [
      'Show an EPUB a page at a time (mouse wheel, arrows or Page Down), or '
          'scrolling',
      'Highlights in four colours, with your own notes, kept even across '
          'bold or italic text',
      'Read aloud with the Windows voice (Ctrl+R), at the speed you like',
      'Footnotes open over the page; click a picture to zoom; look up a word '
          'in the dictionary',
      'PDFs: search and the PDF\'s own contents',
      'Text and theme just for one book, if you like',
      'Opening a book moves it to In progress, and the end offers to mark '
          'it finished',
      'Statistics: time in the reader, reading speed and the longest streak',
    ],
  ),
  ChangelogEntry(
    version: '1.5.0',
    date: '2026-10-31',
    changes: [
      'Reader: add the EPUB or PDF file of a book and read it in Chapterly '
          '(Book file, on the Reading tab of the book page)',
      'EPUB books scroll one chapter at a time, at a comfortable width',
      'Text size, typeface, line spacing, margins, and paper, white, dark or '
          'black pages',
      'Chapters, search (Ctrl+F), bookmarks (Ctrl+B), and Page Down, Space '
          'or the arrow keys to move through the book',
      'Select a passage and right-click to highlight it and save it to the '
          'book\'s quotes',
      'The reader keeps the current page up to date and adds reading time to '
          'the reading log',
      'Chapterly keeps its own copy of the file on this PC; it is not synced '
          'or backed up',
    ],
  ),
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
