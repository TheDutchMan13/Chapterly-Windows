# Chapterly for Windows

A private, offline book tracker for Windows that syncs with the
[Chapterly phone app](https://github.com/TheDutchMan13/Chapterly-Android) over
your home Wi-Fi. No account, no cloud, no tracking.

It has the same features as the phone app 1.9.0: shelves, tags, your own
shelves, ratings and rating details, reading log and timer, current page,
quotes, series, wishlist and Next up, statistics and goals, year in review,
backups, CSV and Kindle import, themes and an optional PIN. The barcode
scanner is replaced by "Look up an ISBN".

Made for a PC:

- Two panes in a wide window: the list on the left, the open book on the right
- Table view: sortable columns; double-click a title, author or page count to
  change it, click a shelf, rating or format to pick one; Ctrl+click and
  Shift+click select several books
- Add several books at once: paste a list of ISBNs or titles, check the
  matches from Open Library, and add them in one go
- Covers from your PC: drop a picture on the window, paste one with Ctrl+V,
  or choose a file (shrunk to a small JPEG so it syncs to the phone)
- Statistics laid out in two columns, and the year in review as a PDF to print
- Reading timer with a small window that stays on top while you read
- Audiobooks: add a book's audio (one file such as .m4b or .mp3, or a folder
  of files, subfolders included) and listen in Chapterly, with chapters,
  30-second skips, speed 0.5x to 3x and a sleep timer. Plays through
  media_kit. Listening time goes into the reading log, and where you are
  syncs with the phone (the audio files stay on each device)
- Keyboard shortcuts: Ctrl+F search, Ctrl+N add a book, Ctrl+Shift+N add
  several, Ctrl+S sync, Ctrl+V paste a cover, Ctrl+, Settings, Esc to close
- Right-click a book to move, favorite, add to a shelf or trash it
- Drop a backup, a CSV file or `My Clippings.txt` on the window to import it
- Remembers the window size and place
- Optional daily update check (asks GitHub for the newest release number;
  nothing about you or your books is sent)

## Syncing with your phone

1. On the phone: Settings > Sync with a PC > switch on "Allow sync from my PC".
   It shows an address (such as `192.168.1.20:8765`) and a pairing code.
2. On the PC: Settings > Sync with your phone. Type the address and code, then
   press **Connect and sync**.
   Or press **Find my phone** and Chapterly looks for it on your network.
3. After that, Chapterly syncs when it opens and every 15 minutes while it is
   open (both can be changed in Settings), whenever the phone is there. The
   top of the library shows when it last synced. Press the sync button (or
   Ctrl+S) to sync right away. Chapterly must be open on the phone, and both
   must be on the same Wi-Fi. If the router gives the phone a new address,
   press **Find my phone again**.

With **Show changes before syncing** on (the default), the sync button first
shows what will change on the PC and on the phone, and only syncs when you
agree. Automatic syncs go ahead by themselves unless they would remove books;
then the library shows a note and waits for you to review them.

For each book the newest change wins. Books deleted for good stay deleted on
both sides; books in the trash go to the trash on both sides. The pairing code
is kept in Windows' protected storage. The protocol is described in
[docs/SYNC.md](docs/SYNC.md).

## Installing with winget

`packaging/winget` has the files for listing Chapterly on winget, and the
steps for submitting them with each release.

## Where things are saved

- Library: `%APPDATA%\com.chapterly\chapterly\chapterly.db`. The exact folder
  comes from the company name in the Windows build.
- Automatic backups: `Documents\Chapterly`, the last five kept.

## Building

The Windows app is built by GitHub Actions on every push to `main`. The run's
Artifacts have `chapterly-windows-setup` (an installer, `Chapterly-Setup-<version>.exe`,
no admin rights needed) and `chapterly-windows` (the plain folder: unzip it,
keep it together and run `chapterly.exe`). The installer is made with Inno
Setup from `installer/chapterly.iss`.

To build on your own PC you need Flutter and Visual Studio with the "Desktop
development with C++" workload:

    flutter pub get
    flutter build windows --release

## Shared code with the phone app

This is a separate repo, so the code shared with the phone app is a copy:
`lib/models`, `lib/data/sync_merge.dart`, `lib/data/sync_protocol.dart`,
`lib/data/book_repository.dart` and most screens. When the phone app gets a
new book field, add it here too. Until you do, the Windows app keeps fields it
does not know (`Book.extras`) and sends them back unchanged, so a sync does
not wipe them.

The parts that are different on Windows:

- `lib/data/pc_sync.dart`: the sync client (the phone is the server)
- `lib/data/secure_code_store.dart`: the pairing code in Windows' protected
  storage
- `lib/data/sqlite_book_store.dart`: SQLite through `sqflite_common_ffi`
- `lib/data/file_io.dart`: Save and Open dialogs instead of the share sheet
- `lib/data/auto_backup.dart`: backups in `Documents\Chapterly`
- `lib/data/sync_plan.dart` and `lib/screens/sync_preview.dart`: the sync
  preview
- `lib/screens/book_table.dart`: the table view
- `lib/screens/bulk_add_screen.dart` and `lib/data/bulk_add.dart`: adding
  several books from a list
- `lib/data/cover_image.dart` and `lib/screens/cover_actions.dart`: covers
  from pictures on the PC
- `lib/data/year_review_pdf.dart`: the printable year in review
- `lib/screens/mini_timer.dart` and `lib/data/window_control.dart`: the small
  reading-timer window (window_manager plugin)

## Licence

GNU General Public License v3.0. See [LICENSE](LICENSE).
