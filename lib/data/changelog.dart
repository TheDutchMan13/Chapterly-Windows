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
    version: '1.10.0',
    date: '2026-11-01',
    changes: [
      "This year's reading goal at the top of the Library, with how far "
          'ahead or behind you are (hide it with the x, or in Settings)',
      'Saved filters: save the filter chips and search under a name and '
          'bring them back with one click (Saved filters, at the start of '
          'the chips)',
      'Tags (Library menu): see every tag with its number of books, rename '
          'or merge tags, and delete a tag from all books',
      'Series (Library menu): every series with the books you have, what '
          'you have finished, the missing numbers (add one to For later with '
          'a click) and what to read next',
      'Audiobook bookmarks: Bookmark in the player saves the place you are '
          'at, with a note if you like; Bookmarks lists them to jump back, '
          'edit or delete',
      'Export a book\'s notes, quotes, highlights and audiobook bookmarks as '
          'Markdown or PDF (Export, on the Notes tab)',
      'Refresh details from Open Library for the books you select: blank '
          'ISBNs, years, covers and pages are filled in',
      "Media keys and Windows' media controls: your keyboard's play/pause "
          'and skip keys and headphone buttons control the audiobook, and the '
          'pop-up by the volume shows the book, chapter and cover',
      'Mini player: a small window that stays on top with play/pause, '
          'skip and the chapter (in the player and the now-playing bar)',
      'Keep running in the tray (Settings, Appearance): closing the window '
          'keeps Chapterly and your audiobook going; click the tray icon to '
          'bring it back',
      'Install updates from inside Chapterly: Update downloads the new '
          'version, closes Chapterly, installs it and opens it again',
      'Finish forecast: a book you are reading shows when you should finish '
          'it at your recent pace, from pages, listening time or the reader '
          '(recent days count more), and the yearly goal says where you are '
          'heading by Dec 31',
      'Search forgives typos ("Brandn Sanderson"), finds words in any '
          'order and names without accents ("Bronte")',
      'Possible duplicates: Duplicates also finds books that are nearly the '
          'same (a typo, a subtitle on one, "Deluxe Edition"), to merge or '
          'mark as not the same',
      'Better matching of book and audiobook files to your books: typos, '
          'words such as "Unabridged" and a different word order no longer '
          'get in the way',
      'What should I read next? picks the best match for your taste, and '
          'says why ("Because you liked Mistborn"); the next book of a '
          'series you are reading comes first. Surprise me still picks at '
          'random',
      'Similar books in your library (on a book page, under Find more)',
      'Your taste (Statistics): the tags, authors, formats, lengths and '
          'decades you rate higher or lower than usual',
      'Suggested tags (Suggest, next to Tags on a book page): from Open '
          'Library and the tags on other books by the same author',
      'Find series in titles (Series page): sets the series and number from '
          'titles such as "The Final Empire (Mistborn, #1)"',
      'A book with both an audiobook and a book file shows where you are '
          'in each, and carries on in one from where you are in the other',
      'Rewind a little after a pause (Settings, on by default): playing an '
          'audiobook again goes back 2 to 30 seconds, more after a longer '
          'pause',
      'Predicted rating: a book you have not rated shows the stars you would '
          'probably give it, from the rated books most like it',
      'Reading time: how long a book takes you at your own speed (from your '
          'reading log and the reader), or an audiobook at your playback '
          'speed, and how much is left',
      'Time I have (What should I read next?): only books you could read in '
          '1, 3, 6 or 12 hours, and books you are reading that you could '
          'finish in that time',
      'Stalled books: books on In progress you have not touched for much '
          'longer than usual get a note on the Library, to keep reading, put '
          'back on For later or mark Unfinished',
      'Library health (Library menu): invalid ISBNs (and ISBN-10s to change '
          'to ISBN-13 in one click), missing finish dates, dates the wrong way '
          'round, missing pages, authors and covers, duplicates and stalled '
          'books',
      'Check covers (Library health): finds different books with the same '
          'cover picture, and covers that are tiny, blank or the wrong shape',
      'Search notes and quotes (Library menu): searches your notes, quotes, '
          'highlights and audiobook bookmark notes, best match first, typos '
          'forgiven',
      'Quote of the day at the top of the Library: one of your quotes or '
          'highlights, the one you have not seen for longest first (turn it '
          'off in Settings)',
      'Smarter sync: when a book was changed on both the PC and the phone, '
          'each change is kept (for example a rating on the PC and tags on '
          'the phone) instead of only the newest copy. Nothing changes on '
          'the phone app',
    ],
  ),
  ChangelogEntry(
    version: '1.9.0',
    date: '2026-10-31',
    changes: [
      'Works with a Calibre library: when a book sits in a Calibre folder, '
          'its metadata.opf is used to find the right book, and a blank '
          'cover, series, tags, ISBN or year is filled in from Calibre '
          '(nothing you wrote is changed)',
      'Import from Calibre library (Settings) adds the Calibre books you '
          'do not have yet, with covers, series, tags and their files',
      'An Import button under Add file in the side menu: from a Calibre '
          'library, scan your folders now, or from a CSV file',
      'A progress window with a bar and the book being worked on while a '
          'scan or Calibre import runs',
      'Drag the line between the book list and the open book to make '
          'either side wider (double-click it to reset)',
      'Restart button on the audiobook card: starts the book again from '
          'the beginning (after you confirm)',
      'Settings is tidier: grouped into Appearance, Adding books and your '
          'library, Folders and importing, Backup and sync, Privacy, and '
          'About and updates. Click a group to open it',
    ],
  ),
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
