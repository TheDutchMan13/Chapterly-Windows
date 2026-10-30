/// The four shelves a book can sit on.
enum Shelf { finished, inProgress, forLater, unfinished }

extension ShelfLabel on Shelf {
  String get label => switch (this) {
        Shelf.finished => 'Finished',
        Shelf.inProgress => 'In progress',
        Shelf.forLater => 'For later',
        Shelf.unfinished => 'Unfinished',
      };
}
