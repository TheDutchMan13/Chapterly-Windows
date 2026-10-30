# Chapterly sync protocol (version 1)

The phone runs a small server while sync is switched on in Settings and the
app is open. A PC app on the same home Wi-Fi sends its library to the phone,
and gets back the merged library. Both sides end up with the same books.

## Connecting

1. On the phone: Settings > Sync with a PC > switch on "Allow sync from my PC".
   The phone shows its address (for example `192.168.1.20:8765`) and a
   16-character pairing code.
2. On the PC: enter the address and the code once. Remove the dashes from the
   code (`ABCD-EFGH-...` becomes `ABCDEFGH...`).

Port: 8765. The code is sent in the `Authorization` header, so only use this
on your own home network. Anyone on the same Wi-Fi with the code can read and
change your library. Press "New code" on the phone to revoke access.

## Requests

### `GET /v1/ping` (no code needed)

Reply `200`:

    {"app": "chapterly", "protocol": 1}

Use it to check that an address is a Chapterly phone before pairing.

### `POST /v1/sync`

Header: `Authorization: Bearer <code>`, `Content-Type: application/json`.

Body: the PC's whole library, including books in the trash, and the list of
books it has permanently deleted:

    {
      "app": "chapterly",
      "protocol": 1,
      "books": [ { ...book... } ],
      "tombstones": { "<book id>": "2026-03-01T12:00:00.000" }
    }

Reply `200`: the merged library in the same shape. The PC should replace its
library with it.

Errors: `401` wrong or missing code, `400` the message is not valid or needs a
newer protocol (reply has `{"error": "..."}` text), `500` the phone could not
finish.

Looking without changing anything: a body with no books and no tombstones
merges nothing into the phone's library, so the phone's library stays as it
is and the reply is simply the phone's library. The PC uses this for "Show
changes before syncing": it works out what a real sync would change on each
side, shows it, and only then sends its real library.

## A book

Fields (all optional except `id`, `title`, `shelf`, `addedAt`, `updatedAt`):

    id, title, author, shelf ("finished" | "inProgress" | "forLater" | "unfinished"),
    addedAt, updatedAt, deletedAt, tags (list), isbn, coverUrl,
    firstPublishYear, pages, rating (1-5), startedAt, finishedAt,
    format ("paperback" | "hardcover" | "ebook" | "audiobook"),
    favorite (bool), notes, series, seriesNumber,
    collections (list of shelf names),
    quotes (list of {text, page, addedAt}),
    currentPage, aspectRatings ({"plot" | "characters" | "writing" | "pacing": 1-5}),
    priority ("low" | "medium" | "high"), buyAt (shop, library or link),
    queuePosition (place in the Next up order, 0 is first),
    audio ({positionMs, lengthMs, track, trackMs, trackCount}: where you are
      in the audiobook; the audio files themselves never sync),
    readingLog (list of {date, pages, minutes}),
    previousReadings (list of {startedAt, finishedAt, rating, log})

Dates are ISO 8601 text.

`coverUrl` is usually a web address. A cover added on the PC from a picture is
stored in the book itself as a small JPEG data address
(`data:image/jpeg;base64,...`, about 400 pixels wide), so it syncs like any
other field. Both apps show either kind.

## Merging rules

Use the same rules on both sides:

1. For each book id, the copy with the newer `updatedAt` wins. On a tie the
   copy on the device that is merging wins.
2. A book whose tombstone time is the same as or later than its `updatedAt` is
   removed. A book changed after its tombstone is kept, and the tombstone is
   dropped.
3. Keep the newest tombstone time when both sides have one for the same id.

The phone's own code for these rules is in `lib/data/sync_merge.dart`, and its
tests are in `test/sync_test.dart`.
