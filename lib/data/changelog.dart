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
    version: '1.49.0',
    date: '2026-11-10',
    changes: [
      'Chapterly opens on the shelf that has your books, not on an empty '
          'Finished shelf. It picks the first shelf, in your order, that has '
          'books',
      'Far fewer tags in the way: the Library and Read next show your 12 '
          'most used tags, plus the tags you have picked, and an All tags '
          'button that opens the full list. You can search it and sort it by '
          'most used or A to Z, and it says how many books each tag has. '
          'With 385 tags, Read next used to show a wall of them and push '
          'the book it picked off the screen',
      'Read next opens about four times quicker with a large library '
          '(about 0.4 seconds instead of 1.7 in a test on a PC)',
    ],
  ),
  ChangelogEntry(
    version: '1.48.0',
    date: '2026-11-10',
    changes: [
      'Backups no longer slow the app down: automatic backups and Export '
          'backup are now written one book at a time. With a big library the '
          'app used to freeze for over a second and use about 570 MB more '
          'memory while a backup was made; now it keeps running smoothly and '
          'uses about 35 MB. The backup file is exactly the same as before, '
          'so old and new backups restore in any version',
      'A backup cut short (the app closed, the disk full) no longer leaves '
          'half a file or replaces a good one',
      'The library file gives back space it no longer needs, a few seconds '
          'after Chapterly opens. A big library that had been 195 MB is now '
          'about 98 MB, with nothing removed',
    ],
  ),
  ChangelogEntry(
    version: '1.47.0',
    date: '2026-11-09',
    changes: [
      'See which devices use your book server: in Book server, the menu '
          'now has Devices on the server, with each app, whose it is and '
          'when it last connected. You can take an old one off the list. It '
          'needs book server 1.9.0 or newer, and shows up once each app is '
          'updated',
      'When the book server cannot be reached, Chapterly now says why: the '
          'PC is there but the server is not running, the address was not '
          'found, or Tailscale or the PC is off',
    ],
  ),
  ChangelogEntry(
    version: '1.46.1',
    date: '2026-11-08',
    changes: [
      'See your phones at a glance: in Settings > Sync with your phone, '
          'each paired phone now says whether it is here right now and when '
          'it last synced, and a new button checks again without syncing',
    ],
  ),
  ChangelogEntry(
    version: '1.46.0',
    date: '2026-11-08',
    changes: [
      'Sync with more than one phone: pair another phone from Settings > '
          'Sync with Add another phone. Each phone syncs with this PC, and '
          'what one sends reaches the others the next time you sync. Phones '
          'that are away are left alone and say nothing. You can forget or '
          'find again each phone on its own',
    ],
  ),
  ChangelogEntry(
    version: '1.45.4',
    date: '2026-11-07',
    changes: [
      'Much quicker start and no more slowdown while using the app: pages '
          'you have not opened yet are not built until you open them, and '
          'pages hidden behind the one you are on no longer redraw '
          'themselves every time your library changes. With 1,250 books, '
          'starting went from about 3.7 to 0.8 seconds in a test, and a '
          'change to the library from about 0.4 seconds to 0.05',
    ],
  ),
  ChangelogEntry(
    version: '1.45.3',
    date: '2026-11-07',
    changes: [
      'Fixed the app being slow and freezing for seconds after every click '
          'with a big library: the Read next page worked out its "By authors '
          'you like" list by going through the whole library again for each '
          'author, and did it on every click, even while hidden. It now '
          'takes a few milliseconds and is only worked out again when your '
          'library changes',
    ],
  ),
  ChangelogEntry(
    version: '1.45.2',
    date: '2026-11-07',
    changes: [
      'Chapterly now keeps a short performance_log.txt in its data folder: '
          'how long each step of starting took, slow screens, and moments '
          'when the app was busy. It holds no book details and starts fresh '
          'each time Chapterly opens. It helps find out why the app feels '
          'slow',
    ],
  ),
  ChangelogEntry(
    version: '1.45.1',
    date: '2026-11-07',
    changes: [
      'Fixed a long freeze the first time 1.45.0 opened a big library: the '
          'covers are now moved over in one go instead of one at a time',
    ],
  ),
  ChangelogEntry(
    version: '1.45.0',
    date: '2026-11-07',
    changes: [
      'Faster and lighter with a big library: cover pictures are kept apart '
          'from the books and only read when a cover is shown, so a library '
          'of thousands of books takes far less memory. The first time '
          '1.45.0 opens, it moves your covers over once, which can take a '
          'few seconds',
      'Covers are drawn at the size they are shown, so scrolling a long '
          'list is smoother',
      'Syncing a library with many covers is much quicker: pictures are no '
          'longer checked again on every sync',
      'Possible duplicates are found several times faster, and worked out '
          'again only after your library changes',
    ],
  ),
  ChangelogEntry(
    version: '1.44.0',
    date: '2026-11-07',
    changes: [
      'Reading challenges: set your own challenge between any two dates, '
          'such as 12 books by March, 2,000 pages this summer, 5 books '
          'tagged Horror in October or 10 different authors. Each one '
          'shows a progress bar, days left and whether you are on pace. '
          'Find them on Statistics',
      'Check every series: with a Hardcover token, the Series screen can '
          'ask Hardcover about all your series at once and list the books '
          'you do not have. Ones after the last book you have are ticked, '
          'ready to add to For later',
    ],
  ),
  ChangelogEntry(
    version: '1.43.0',
    date: '2026-11-07',
    changes: [
      'One pairing syncs every profile: pair your phone and PC once, and '
          'each profile syncs with the profile of the same name on the other '
          'device, without switching profiles',
      'A profile missing on one device is added there the next time you '
          'sync. A profile with a PIN is never copied, and syncs only while '
          'it is open',
    ],
  ),
  ChangelogEntry(
    version: '1.42.0',
    date: '2026-11-06',
    changes: [
      'Your Google Books key and Hardcover token are now kept in Windows\' '
          'protected storage, not in the plain settings file. They move there '
          'by themselves the first time you open this version',
      'Search settings: a group you opened stays open after you clear the '
          'search',
      'Export for Goodreads or StoryGraph no longer puts a quote mark in '
          'front of notes and titles that start with - or +',
      'Safer reading of book files: an EPUB that unpacks to something huge '
          'is skipped instead of crashing the app',
    ],
  ),
  ChangelogEntry(
    version: '1.41.0',
    date: '2026-11-06',
    changes: [
      'Search settings: a search box at the top of Settings shows only the '
          'sections that have the words you type, in their names or their '
          'descriptions. On Windows it opens the groups that match',
    ],
  ),
  ChangelogEntry(
    version: '1.40.0',
    date: '2026-11-06',
    changes: [
      'Remove a download: on the book server list, the menu on a book you '
          'downloaded has Remove download, which deletes its file but keeps '
          'the book and your place. Downloads has a Remove all button too',
    ],
  ),
  ChangelogEntry(
    version: '1.39.0',
    date: '2026-11-06',
    changes: [
      'Find ISBNs and Fix library also look on Google Books when Open '
          'Library has no ISBN for a book. Find ISBNs has a tick box for it, '
          'like Update covers, and each ISBN says where it came from',
      'On your drive: link a book to a file or folder where it already is '
          'on this PC, of any kind (EPUB, MOBI, PDF, audio folder). Nothing '
          'is copied. Open launches it with the program Windows uses for it',
    ],
  ),
  ChangelogEntry(
    version: '1.38.0',
    date: '2026-11-06',
    changes: [
      'Export for Goodreads or StoryGraph: Settings saves your books as a '
          'CSV in Goodreads\' format, with shelves, ratings, dates, series '
          'and ISBNs. Your notes go in Private Notes',
      'Author pages: "About this author" on a book now shows what you have '
          'read by them, all your books by them, and their books you do not '
          'have yet',
      'What should I read next? now also lists the next book in series you '
          'started, books by authors you rated well, and the books that have '
          'waited longest',
    ],
  ),
  ChangelogEntry(
    version: '1.37.0',
    date: '2026-11-05',
    changes: [
      'Fix library: runs the series spellings, your book files, Hardcover, '
          'ISBNs, covers and larger covers one after the other and shows '
          'everything found in one list. You tick what to apply',
      'Your book files: the series, ISBN and cover written inside your EPUB '
          'and M4B files, or known to your book server, fill in what a book '
          'is missing',
      'Hardcover: paste a free Hardcover token in Settings to find series '
          'there, and to see which books of a series you are missing on the '
          'Series screen, with their real titles',
      'Larger covers: covers chosen from Open Library and Google Books now '
          'use their bigger pictures, so they look sharper',
    ],
  ),
  ChangelogEntry(
    version: '1.36.0',
    date: '2026-11-05',
    changes: [
      'Library search: when you type in the search box at the top, buttons '
          'under it search Open Library or Google Books for the same words, '
          'in case the book is not in your library yet',
    ],
  ),
  ChangelogEntry(
    version: '1.35.0',
    date: '2026-11-05',
    changes: [
      'Update covers can also look on Google Books for books Open Library '
          'has no cover for. A tick box turns it off. It stops for the day '
          'when Google has no more searches',
    ],
  ),
  ChangelogEntry(
    version: '1.34.0',
    date: '2026-11-05',
    changes: [
      'Search Google Books yourself: a switch between Open Library and '
          'Google Books in the search screen, in Find match and in Find '
          'cover in the book editor. Without a Google Books key Google '
          'allows only a few searches a day; a free key (Settings) allows '
          'many more',
    ],
  ),
  ChangelogEntry(
    version: '1.33.0',
    date: '2026-11-05',
    changes: [
      'Find ISBNs: looks up books that have no ISBN on Open Library and '
          'shows the ISBN of the book that clearly matches. You choose which '
          'to add. Books that already have one are left alone',
    ],
  ),
  ChangelogEntry(
    version: '1.32.0',
    date: '2026-11-05',
    changes: [
      'Book editor: Find cover shows the covers Open Library has for the '
          'book, from every printing it lists, and you tap the one you want',
      'Update covers: finds books with no cover, or whose Open Library cover '
          'no longer exists, and fetches the cover Open Library has now. You '
          'choose which to use. Covers that still show are never replaced',
    ],
  ),
  ChangelogEntry(
    version: '1.31.0',
    date: '2026-11-05',
    changes: [
      'Import a CSV file: books already in your library can now take the '
          'series name and number from the file. The import window asks '
          'first and shows how many books will change',
    ],
  ),
  ChangelogEntry(
    version: '1.30.0',
    date: '2026-11-05',
    changes: [
      'Series: when one series is spelled two ways, such as "Dexter" and '
          '"Dexter Series" or "The Expanse" and "Expanse", a note at the top '
          'of the Series screen offers to join them. You pick which to join, '
          'and the book numbers stay as they are',
      'Series found in titles now use the spelling of a series you already '
          'have, even when it differs by a word like "Series" or "Saga"',
    ],
  ),
  ChangelogEntry(
    version: '1.29.0',
    date: '2026-11-05',
    changes: [
      'Use Google Books (Settings): fills in a missing cover, page count, '
          'ISBN, first published year and tags, in the background, a few '
          'books at a time and once per book. Nothing a book already has is '
          'changed, and tags are only added to books that have none. It is '
          'off by default because it sends each title and author to Google',
      'It works without a key, but then Google allows only a few books a '
          'day: Chapterly carries on the next day. A free "Google Books key" '
          '(Settings) allows many more',
    ],
  ),
  ChangelogEntry(
    version: '1.28.0',
    date: '2026-11-05',
    changes: [
      'Ask Wikidata for series (Settings): for books whose title has no '
          'series, Chapterly asks Wikidata which series a book is part of and '
          'its number, in the background and a few books at a time. It works '
          'for well-known books only. It is off by default because it sends '
          'each title and author to wikidata.org. Series you set are never '
          'changed',
    ],
  ),
  ChangelogEntry(
    version: '1.27.0',
    date: '2026-11-05',
    changes: [
      'Series are found for you: a book with its series in the title, like '
          '"Mistborn, Book 2" or "(The Expanse, #3)", gets the series and '
          'number by itself, now and as you add books. Series you set are '
          'never changed, and you can turn it off in Settings',
    ],
  ),
  ChangelogEntry(
    version: '1.26.0',
    date: '2026-11-05',
    changes: [
      'Review matches (Library menu): lists the books whose title and '
          'author look very different from their original file name, so a '
          'wrong Open Library match is easy to spot. Click Find match to fix '
          "one, or It's right to stop it being listed",
      'New on your book server: a banner at the top of your library shows '
          'the books the server found since you last looked, with a Download '
          'button for each. The server checks its folders every hour',
      'Quotes and notes (Library menu): every quote, highlight and note in '
          'one place, with All, Quotes and Notes filters. Type to search them '
          'as before',
      'Series: the next book to read in a series now has its own Open button',
      'Reading stats: Hours listened, the length of the audiobooks you '
          'finished',
      'Audiobooks remember their own speed: set 1.4x for one book and it '
          'stays 1.4x for that book, while others keep theirs',
      'Importing a Goodreads, StoryGraph or other CSV file now shows how '
          'many books are new and how many you already have before anything '
          'is added',
    ],
  ),
  ChangelogEntry(
    version: '1.25.0',
    date: '2026-11-05',
    changes: [
      'Book info: click the (i) button next to a book in the list, on the '
          'book page, or "Book info" when you right-click a book, to see its '
          'original name (the file or folder it was found as, or its file '
          'name on your book server), where it came from, and the title and '
          'author it was first matched as',
      'Edit a book: correct the title, author, series, ISBN, pages, year '
          'and cover from the pencil on the book page, "Edit book" when you '
          'right-click a book, or "Edit this book" in Book info. "Find '
          'match" searches Open Library again so you can pick the right book '
          'when the match was wrong',
      'A book from your book server can be corrected on the server too, '
          'for everyone using it. The book file itself is never changed',
      '"Reset to the matched info" puts back the details the book was '
          'added with. Your corrections sync to your phone',
    ],
  ),
  ChangelogEntry(
    version: '1.24.0',
    date: '2026-11-05',
    changes: [
      'A new look, Midnight: deep navy and teal in dark mode, and cool '
          'off-white with deeper teal in light mode. Light, Dark or follow '
          'Windows is still under Settings, Appearance. The older look is '
          'there too, as Classic, with its accent colours and paper option',
      'A new font, Manrope, comes with the app for the Midnight look. You '
          'can still pick another font in Settings',
      'The book you are reading now sits at the top of the library in a '
          '"Continue reading" card with how far along you are. Click it to '
          'open the book, or turn it off in Settings, Appearance',
      'Rounded covers with a soft shadow, a progress bar under books you '
          'are reading in the grid, and the author under each title',
      'Books without a cover picture show their title on a coloured card '
          'instead of a plain icon',
      'The side bar marks the open page with a teal pill, and shelves, '
          'buttons, cards and dialogs are rounder and calmer',
      'The book page has a bigger cover on a teal band',
    ],
  ),
  ChangelogEntry(
    version: '1.23.1',
    date: '2026-11-04',
    changes: [
      'When the book server answers "not found", Chapterly now says why: the '
          'file or its folder was moved, or the server no longer serves that '
          'folder, instead of always saying the book is gone',
    ],
  ),
  ChangelogEntry(
    version: '1.23.0',
    date: '2026-11-04',
    changes: [
      'Book server: press Paste server code to fill in the address and token '
          'in one go. Copy the server code that the server shows when you add '
          'a user or make a new token, then press Paste server code and '
          'Connect. Pasting the code into the Address box works too. Typing '
          'the address and token still works',
    ],
  ),
  ChangelogEntry(
    version: '1.22.0',
    date: '2026-11-04',
    changes: [
      'Pair with your phone by scanning a QR code: in Settings > Sync with '
          'your phone, press Pair with QR code, then scan the code with '
          'Chapterly on your phone. Chapterly finds the phone by itself, so '
          'you no longer need to type an address or a pairing code. Update '
          'Chapterly on your phone too. Typing them still works',
    ],
  ),
  ChangelogEntry(
    version: '1.21.0',
    date: '2026-11-04',
    changes: [
      'Syncing with your phone is safer: the pairing code never goes over '
          'the Wi-Fi any more, nobody else on the network can read or change '
          'your library on its way, and Chapterly checks that it is really '
          'your phone answering. Update Chapterly on your phone too; you do '
          'not need to pair again',
      'A book or deletion dated far in the future (a device with its clock '
          'wrong) no longer wins every sync',
      'Tag my library: when Open Library cannot be reached, Wikidata is '
          'still asked, and the review says which one was skipped. Wikidata '
          'matches are stricter: films, TV series and games with the same '
          'title are left out, and books by several authors are found',
      'Audiobooks from the book server with very long track names keep all '
          'their parts',
      'Wrong PINs are counted on every PIN prompt, also after a restart, '
          'and the wait gets longer each time. PINs are now stored in a way '
          'that is much slower to guess',
      'While Chapterly is locked, keyboard shortcuts no longer reach the '
          'library behind the lock screen, and you can type the PIN on the '
          'keyboard',
      'Restoring a backup first saves a copy of your library as it was',
      'A backup with the same book twice now restores, keeping the newest '
          'copy',
      'The daily update check tries again next time when it could not '
          'reach GitHub',
    ],
  ),
  ChangelogEntry(
    version: '1.20.0',
    date: '2026-11-04',
    changes: [
      'Tag my library can also ask Wikidata for a book\'s genres. Switch on '
          '"Also use Wikidata" on that screen. It is off by default because '
          'it sends each title and author to wikidata.org, and it goes slowly '
          'on purpose to stay within Wikidata\'s limits',
    ],
  ),
  ChangelogEntry(
    version: '1.19.0',
    date: '2026-11-04',
    changes: [
      'Updates are safer: Chapterly only downloads an installer from its own '
          'releases on GitHub, and checks it against the checksum GitHub '
          'gives before running it. Cancelling a download and starting '
          'again can no longer start the first one',
      'Syncing with your phone or the book server no longer loses a change '
          'you make while cover pictures are being fetched',
      'Undo after a bulk change takes back only what that change did: a '
          'rating, note or tag you added since is kept, and books the change '
          'left alone are not touched',
      'A bulk change that changes nothing on a book leaves it as it was, so '
          'it is not sent again by the next sync',
      'Restoring a backup or importing books now sticks: the next sync no '
          'longer takes the books back to what they were, or removes them '
          'again',
      'The app lock now locks when Chapterly is minimized, and covers the '
          'mini player and timer too',
      'Each profile keeps its automatic backups in a folder named after it '
          'and its id, so two profiles with names that look alike never '
          'share one (older backups stay where they were)',
      'Adding a file as a new book no longer leaves an empty book behind '
          'when the file cannot be linked',
      'Books from the book server are only saved inside your books folder, '
          'under a safe name',
      'CSV export: cells that a spreadsheet would run as a formula are '
          'saved as text',
    ],
  ),
  ChangelogEntry(
    version: '1.18.0',
    date: '2026-11-03',
    changes: [
      'Tag my library (Tags screen): finds tags for every book that has '
          'none, from Open Library, matched to your own tags. You tick or '
          'untick each one before anything is added, with Undo',
      'Test on your tagged books: hides their tags, finds tags for them, '
          'and shows how many of yours came back',
    ],
  ),
  ChangelogEntry(
    version: '1.17.0',
    date: '2026-11-03',
    changes: [
      'Files to check: "Add all" above the files that are not in your '
          'library adds every one as a new book, on the shelf you pick, with '
          'the title and author found in the file (or read from its name). An '
          'ebook and an audiobook of the same book share one book; files it '
          'cannot name, or a second ebook of the same book, stay in the list',
    ],
  ),
  ChangelogEntry(
    version: '1.16.0',
    date: '2026-11-03',
    changes: [
      'Move books between your own shelves: open one of your shelves, '
          'select books, then More > Move to another shelf of mine. The '
          'books leave that shelf and go to the one you pick (or a new '
          'one), with Undo',
      'Take books off a shelf of your own: select them, then More > Remove '
          'from the shelf. The books stay in your library',
    ],
  ),
  ChangelogEntry(
    version: '1.15.0',
    date: '2026-11-03',
    changes: [
      'Profiles: everyone who reads on this PC can have their own '
          'Chapterly, with their own books, shelves, statistics, goals, '
          'settings, phone sync, book server connection and PIN (Settings, '
          'at the top). Your library is the first profile, called "Me"; '
          'rename it any time',
      'Opening another profile restarts Chapterly with it. A profile with a '
          'PIN asks for it when it opens, and the PIN screen can open another '
          'profile',
      'Each profile pairs with the phone on its own, and syncs when the '
          'same person\'s profile is open there (Chapterly for Android '
          '1.19.0 or later)',
    ],
  ),
  ChangelogEntry(
    version: '1.14.0',
    date: '2026-11-03',
    changes: [
      'A more colourful Statistics page: coloured tiles with icons, a bar '
          'that shows how your books are spread over the shelves (each shelf '
          'has its own colour), coloured bars for formats and ratings, and '
          'every part in its own rounded block',
    ],
  ),
  ChangelogEntry(
    version: '1.13.1',
    date: '2026-11-03',
    changes: [
      'Wishlist shelf: a fifth shelf for books you want but have not got '
          'yet. They are not counted as For later, in Next up or in your '
          'reading statistics. Open the book file and it moves to In progress',
      'Syncing a big library is fast and no longer fails: cover pictures '
          'travel on their own, and only to a device that does not have them. '
          'Update the phone, the PC and the server together',
    ],
  ),
  ChangelogEntry(
    version: '1.13.0',
    date: '2026-11-03',
    changes: [
      'Book server (Library menu): connect to your own Chapterly book '
          'server, then browse and search your library there and download '
          'ebooks and audiobooks into Chapterly',
      'A book you download goes on For later, or is linked to the same book '
          'when it is already in your library',
      'Your place in those books syncs with your other devices: open a book '
          'and Chapterly carries on from the furthest place you reached',
      'Audiobook bookmarks sync through the book server too',
      'Sync my whole library (on the Book server screen): books, shelves, '
          'ratings, notes, quotes, bookmarks and the wish list sync through '
          'your server, from anywhere Tailscale reaches. A change made on '
          'each device to the same book keeps both',
      'Notes on highlights are kept on the book\'s quote, so they sync too',
      'EPUB places move between the phone and the PC: a place from the '
          'other reader opens at the same point in the book',
      'Send to my other devices: a book from the server downloads there '
          'the next time they open Chapterly',
      'Downloads (Book server): the space downloaded books use, and remove '
          'a file while keeping the book',
      'Audiobooks made of one file per chapter download as one book',
      'Reading reminder (Settings): a daily nudge when you\'re behind this '
          "year's goal, shown in Chapterly when it is open",
      'Your server token is kept in Windows\' protected storage',
    ],
  ),
  ChangelogEntry(
    version: '1.12.0',
    date: '2026-11-02',
    changes: [
      'Wish list (Library menu): books you want but do not have yet, with a '
          'priority and where to get each one. Search it, and move a book '
          'into your library (For later) when you get it',
      'The wish list syncs with Chapterly for Android 1.16.0 or later: added, '
          'edited and deleted on either side (the newer change wins)',
      'Connecting to your phone: paste the pairing code (a show/hide eye lets '
          'you check it), and copy the saved phone address with one click',
    ],
  ),
  ChangelogEntry(
    version: '1.11.0',
    date: '2026-11-01',
    changes: [
      'Audiobook bookmarks now sync with your phone (Chapterly for Android '
          '1.15.0 or later): added, edited and deleted on either side',
      'Your bookmarks move into your books the first time this version '
          'starts; the old file is kept as audio_bookmarks.moved.json '
          '(bookmarks of books no longer in your library stay only there)',
      'With an older phone app, the bookmarks on this PC are kept as they '
          'are; update the phone to sync them',
    ],
  ),
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
