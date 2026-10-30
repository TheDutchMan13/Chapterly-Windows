# Chapterly for Windows

A private, offline book tracker for Windows that syncs with the
[Chapterly phone app](https://github.com/TheDutchMan13/Chapterly-Android) over
your home Wi-Fi. No account, no cloud, no tracking.

It has the same features as the phone app 1.9.0: shelves, tags, your own
shelves, ratings and rating details, reading log and timer, current page,
quotes, series, wishlist and Next up, statistics and goals, year in review,
backups, CSV and Kindle import, themes and an optional PIN. The barcode
scanner is replaced by "Look up an ISBN".

## Syncing with your phone

1. On the phone: Settings > Sync with a PC > switch on "Allow sync from my PC".
   It shows an address (such as `192.168.1.20:8765`) and a pairing code.
2. On the PC: Settings > Sync with your phone. Type the address and code, then
   press **Connect and sync**.
3. After that, press the sync button at the top of the library whenever you
   want. Chapterly must be open on the phone, and both must be on the same
   Wi-Fi.

For each book the newest change wins. Books deleted for good stay deleted on
both sides; books in the trash go to the trash on both sides. The pairing code
is kept in Windows' protected storage. The protocol is described in
[docs/SYNC.md](docs/SYNC.md).

## Where things are saved

- Library: `%APPDATA%\com.chapterly\chapterly\chapterly.db`. The exact folder
  comes from the company name in the Windows build.
- Automatic backups: `Documents\Chapterly`, the last five kept.

## Building

The Windows app is built by GitHub Actions on every push to `main`. Download
`chapterly-windows` from the run's Artifacts, unzip it, and run
`chapterly.exe`. Keep the whole folder together.

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

## Licence

GNU General Public License v3.0. See [LICENSE](LICENSE).
